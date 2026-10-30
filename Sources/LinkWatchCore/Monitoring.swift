import Foundation

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

public struct ProbePair: Equatable, Sendable {
  public let elapsed: TimeInterval
  public let accessPoint: ProbeOutcome
  public let router: ProbeOutcome

  public init(elapsed: TimeInterval, accessPoint: ProbeOutcome, router: ProbeOutcome) {
    self.elapsed = elapsed
    self.accessPoint = accessPoint
    self.router = router
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
  public private(set) var health: Health = .healthy
  public private(set) var pendingSince: TimeInterval?
  private var pending: Health?
  public let thresholds: Thresholds
  public let capacity: Int

  public init(thresholds: Thresholds = Thresholds(), capacity: Int = 60) {
    self.thresholds = thresholds.isValid ? thresholds : Thresholds()
    self.capacity = max(5, capacity)
  }

  public var accessPointMedian: Double? { median(samples.suffix(5).map(\.accessPoint)) }
  public var routerMedian: Double? { median(samples.suffix(5).map(\.router)) }

  public var accessPointLoss: Double { loss(samples.map(\.accessPoint)) }
  public var routerLoss: Double { loss(samples.map(\.router)) }

  public mutating func append(_ pair: ProbePair) {
    guard pair.elapsed.isFinite, pair.elapsed >= 0,
      pair.accessPoint != .cancelled, pair.router != .cancelled,
      samples.last.map({ pair.elapsed > $0.elapsed }) ?? true
    else { return }
    if let previous = samples.last, pair.elapsed - previous.elapsed > 5 {
      pending = nil
      pendingSince = nil
    }
    samples.append(pair)
    if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
    guard pair.accessPoint.latency != nil, pair.router.latency != nil else {
      health = .unreachable(
        accessPoint: pair.accessPoint.latency == nil, router: pair.router.latency == nil)
      pending = nil
      pendingSince = nil
      return
    }
    guard let accessPoint = accessPointMedian, let router = routerMedian else { return }
    let desired: Health
    if accessPoint > thresholds.slow && router > thresholds.slow {
      desired = .bothSlow
    } else if router - accessPoint > thresholds.difference {
      desired = .routerSlower
    } else if health != .healthy
      && (router - accessPoint >= thresholds.recoveryDifference
        || accessPoint >= thresholds.recoverySlow || router >= thresholds.recoverySlow)
    {
      pending = nil
      pendingSince = nil
      return
    } else {
      desired = .healthy
    }
    if desired == health {
      pending = nil
      pendingSince = nil
    } else {
      if pending != desired {
        pending = desired
        pendingSince = pair.elapsed
      }
      let duration = desired == .healthy ? thresholds.recoverySeconds : thresholds.sustainedSeconds
      if let since = pendingSince, pair.elapsed - since >= duration {
        health = desired
        pending = nil
        pendingSince = nil
      }
    }
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
