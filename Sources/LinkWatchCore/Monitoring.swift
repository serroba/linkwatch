public import Foundation

public enum ProbeOutcome: Equatable, Sendable {
  case success(milliseconds: Double)
  case timeout
  case failure
  case cancelled

  public var latency: Double? {
    if case .success(let value) = self, value.isFinite, value >= 0 { return value }
    return nil
  }
}

/// A public host used as a reference point beyond the router.
struct InternetReference: Equatable, Sendable {
  let name: String
  let address: String

  /// Two independent providers, so one provider's hiccup is not mistaken for the internet.
  static let all = [
    InternetReference(name: "Cloudflare", address: "1.1.1.1"),
    InternetReference(name: "Google", address: "8.8.8.8"),
  ]
}

public struct ProbePair: Equatable, Sendable {
  public let elapsed: TimeInterval
  public let accessPoint: ProbeOutcome
  public let router: ProbeOutcome
  /// Outcomes for `InternetReference.all`, or empty when the profile does not probe them.
  public let internet: [ProbeOutcome]

  public init(
    elapsed: TimeInterval, accessPoint: ProbeOutcome, router: ProbeOutcome,
    internet: [ProbeOutcome] = []
  ) {
    self.elapsed = elapsed
    self.accessPoint = accessPoint
    self.router = router
    self.internet = internet
  }

  /// The fastest reply from any reference, so the internet counts as slow or lost only when
  /// every reference is; nil when no reference was probed.
  public var internetBest: ProbeOutcome? {
    guard !internet.isEmpty else { return nil }
    if let fastest = internet.compactMap(\.latency).min() { return .success(milliseconds: fastest) }
    return internet.contains(.cancelled) ? .cancelled : .timeout
  }
}

public struct Thresholds: Codable, Equatable, Sendable {
  public var difference: Double = 20
  public var recoveryDifference: Double = 10
  public var slow: Double = 30
  public var recoverySlow: Double = 20
  public var sustainedSeconds: Double = 10
  public var recoverySeconds: Double = 6

  public init() {}

  public var isValid: Bool {
    let values = [
      difference, recoveryDifference, slow, recoverySlow, sustainedSeconds, recoverySeconds,
    ]
    return values.allSatisfy { $0.isFinite && $0 > 0 }
      && recoveryDifference < difference && recoverySlow < slow
  }
}

public enum Health: Equatable, Sendable {
  case healthy
  case routerSlower
  case bothSlow
  case unreachable(accessPoint: Bool, router: Bool)
}

public struct MonitoringWindow: Sendable {
  public private(set) var samples: [ProbePair] = []
  public private(set) var history: [ProbePair] = []
  public private(set) var health: Health = .healthy
  public private(set) var pendingSince: TimeInterval?
  private var pending: Health?
  private var assessed: Health = .healthy
  public let thresholds: Thresholds
  public let capacity: Int
  public let historyCapacity: Int

  public init(
    thresholds: Thresholds = Thresholds(), capacity: Int = 60, historyCapacity: Int = 1800
  ) {
    self.thresholds = thresholds.isValid ? thresholds : Thresholds()
    self.capacity = max(5, capacity)
    self.historyCapacity = max(self.capacity, historyCapacity)
  }

  public var accessPointMedian: Double? { median(samples.suffix(5).map(\.accessPoint)) }
  public var routerMedian: Double? { median(samples.suffix(5).map(\.router)) }

  public var accessPointLoss: Double { loss(samples.map(\.accessPoint)) }
  public var routerLoss: Double { loss(samples.map(\.router)) }

  /// Median of the best internet reference over the last five pairs that probed one.
  public var internetMedian: Double? { median(samples.suffix(5).compactMap(\.internetBest)) }

  /// Loss of the best internet reference, or nil when no reference was probed.
  public var internetLoss: Double? {
    let outcomes = samples.compactMap(\.internetBest)
    return outcomes.isEmpty ? nil : loss(outcomes)
  }

  /// Evidence for the verdict, from the same span as the displayed medians.
  ///
  /// Medians and loss use the last five pairs; the 95th percentile uses the last thirty,
  /// about a minute, matching what stored minutes record.
  public var evidence: LinkEvidence {
    let recent = Array(samples.suffix(5))
    let minute = Array(samples.suffix(30))
    let internet = recent.compactMap(\.internetBest)
    let internetMinute = minute.compactMap(\.internetBest)
    return LinkEvidence(
      accessPoint: TargetEvidence(
        median: accessPointMedian, loss: loss(recent.map(\.accessPoint)),
        p95: TargetSummary(minute.map(\.accessPoint)).p95),
      router: TargetEvidence(
        median: routerMedian, loss: loss(recent.map(\.router)),
        p95: TargetSummary(minute.map(\.router)).p95),
      internet: internet.isEmpty
        ? nil
        : TargetEvidence(
          median: median(internet), loss: loss(internet),
          p95: TargetSummary(internetMinute).p95))
  }

  /// Median of one reference, by its index in `InternetReference.all`.
  public func referenceMedian(_ index: Int) -> Double? {
    median(
      samples.suffix(5).compactMap {
        $0.internet.indices.contains(index) ? $0.internet[index] : nil
      })
  }

  public mutating func append(_ pair: ProbePair) {
    guard accepts(pair) else { return }
    if let previous = samples.last, pair.elapsed - previous.elapsed > 5 { clearPending() }
    record(pair)
    guard pair.accessPoint.latency != nil, pair.router.latency != nil else {
      health = .unreachable(
        accessPoint: pair.accessPoint.latency == nil, router: pair.router.latency == nil)
      clearPending()
      return
    }
    health = assessed
    guard let accessPoint = accessPointMedian, let router = routerMedian else { return }
    advance(toward: desiredHealth(accessPoint: accessPoint, router: router), at: pair.elapsed)
  }

  private func accepts(_ pair: ProbePair) -> Bool {
    pair.elapsed.isFinite && pair.elapsed >= 0
      && pair.accessPoint != .cancelled && pair.router != .cancelled
      && !pair.internet.contains(.cancelled)
      && (samples.last.map { pair.elapsed > $0.elapsed } ?? true)
  }

  private mutating func record(_ pair: ProbePair) {
    samples.append(pair)
    if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
    history.append(pair)
    if history.count > historyCapacity { history.removeFirst(history.count - historyCapacity) }
  }

  /// Returns the current health while values sit between recovery and alert thresholds.
  private func desiredHealth(accessPoint: Double, router: Double) -> Health {
    if accessPoint > thresholds.slow && router > thresholds.slow { return .bothSlow }
    if router - accessPoint > thresholds.difference { return .routerSlower }
    let recovered =
      router - accessPoint < thresholds.recoveryDifference
      && accessPoint < thresholds.recoverySlow && router < thresholds.recoverySlow
    return health == .healthy || recovered ? .healthy : health
  }

  private mutating func advance(toward desired: Health, at elapsed: TimeInterval) {
    guard desired != health else {
      clearPending()
      return
    }
    if pending != desired {
      pending = desired
      pendingSince = elapsed
    }
    let duration = desired == .healthy ? thresholds.recoverySeconds : thresholds.sustainedSeconds
    if let since = pendingSince, elapsed - since >= duration {
      health = desired
      assessed = desired
      clearPending()
    }
  }

  private mutating func clearPending() {
    pending = nil
    pendingSince = nil
  }

  private func median(_ outcomes: [ProbeOutcome]) -> Double? {
    let values = outcomes.compactMap(\.latency).sorted()
    guard !values.isEmpty else { return nil }
    let middle = values.count / 2
    return values.count.isMultiple(of: 2)
      ? (values[middle - 1] + values[middle]) / 2 : values[middle]
  }

  private func loss(_ outcomes: [ProbeOutcome]) -> Double {
    guard !outcomes.isEmpty else { return 0 }
    return Double(outcomes.filter { $0.latency == nil }.count) / Double(outcomes.count)
  }
}
