public import Foundation

/// Latency statistics for one target over one minute.
public struct TargetSummary: Codable, Equatable, Sendable {
  public var median: Double?
  public var p95: Double?
  public var loss: Double

  init(_ outcomes: [ProbeOutcome]) {
    let values = outcomes.compactMap(\.latency).sorted()
    median = Self.percentile(values, 0.5)
    p95 = Self.percentile(values, 0.95)
    loss = outcomes.isEmpty ? 0 : Double(outcomes.count - values.count) / Double(outcomes.count)
  }

  /// Nearest-rank percentile, which never invents a value that was not measured.
  private static func percentile(_ sorted: [Double], _ fraction: Double) -> Double? {
    guard !sorted.isEmpty else { return nil }
    let rank = Int((fraction * Double(sorted.count)).rounded(.up))
    return sorted[min(max(rank, 1), sorted.count) - 1]
  }
}

/// One wall-clock minute of paired measurements on one network.
public struct MinuteSummary: Codable, Equatable, Sendable {
  public var start: Date
  public var ssid: String
  public var samples: Int
  public var accessPoint: TargetSummary
  public var router: TargetSummary
  /// The best internet reference per pair; nil when the profile did not probe references.
  public var internet: TargetSummary?
  /// Bytes the Mac received and sent on the interface during the minute; nil when unknown.
  public var received: UInt64?
  public var sent: UInt64?
  /// Median Wi-Fi signal strength and noise (dBm) and transmit rate (Mbit/s) in the minute.
  public var rssi: Int?
  public var noise: Int?
  public var transmitRate: Double?
  /// The most severe state seen during the minute: `healthy`, `bothSlow`, `routerSlower` or
  /// `unreachable`.
  public var worstHealth: String
}

/// Persists minute summaries on this Mac.
public protocol HistoryStore {
  func load(since date: Date) throws -> [MinuteSummary]
  func append(_ summary: MinuteSummary) throws
  /// Removes summaries that started before the date.
  func prune(before date: Date) throws
  func clear() throws
}

/// Aggregates paired measurements into minute summaries and keeps a week of them.
public struct WeekHistory: Sendable {
  public static let retention: TimeInterval = 7 * 24 * 60 * 60

  public private(set) var minutes: [MinuteSummary]
  private var minute: Date?
  private var ssid = ""
  private var pairs: [ProbePair] = []
  private var worst = 0
  private var traffic: TrafficCounters?

  /// Bytes recorded so far in the minute in progress.
  public var currentTraffic: TrafficCounters? { traffic }
  private var signals: [WiFiSignal] = []

  public init(minutes: [MinuteSummary] = []) {
    self.minutes = minutes.sorted { $0.start < $1.start }
  }

  /// Adds a pair; returns the previous minute's summary once a new minute or network begins.
  public mutating func record(
    _ pair: ProbePair, health: Health, ssid: String, at date: Date,
    traffic delta: TrafficCounters? = nil, signal: WiFiSignal? = nil
  ) -> MinuteSummary? {
    let start = Self.minuteStart(date)
    let completed = start != minute || ssid != self.ssid ? flush() : nil
    if pairs.isEmpty {
      minute = start
      self.ssid = ssid
    }
    pairs.append(pair)
    if let signal { signals.append(signal) }
    worst = max(worst, Self.severity(health))
    if let delta {
      traffic = TrafficCounters(
        received: (traffic?.received ?? 0) &+ delta.received,
        sent: (traffic?.sent ?? 0) &+ delta.sent)
    }
    return completed
  }

  /// Completes the current partial minute, for pauses, network changes and shutdown.
  public mutating func flush() -> MinuteSummary? {
    defer {
      minute = nil
      pairs = []
      worst = 0
      traffic = nil
      signals = []
    }
    guard let minute, !pairs.isEmpty else { return nil }
    let summary = MinuteSummary(
      start: minute, ssid: ssid, samples: pairs.count,
      accessPoint: TargetSummary(pairs.map(\.accessPoint)),
      router: TargetSummary(pairs.map(\.router)),
      internet: pairs.contains { $0.internetBest != nil }
        ? TargetSummary(pairs.compactMap(\.internetBest)) : nil,
      received: traffic?.received, sent: traffic?.sent,
      rssi: Self.median(signals.map(\.rssi)), noise: Self.median(signals.map(\.noise)),
      transmitRate: Self.median(signals.map(\.transmitRate)), worstHealth: Self.labels[worst])
    minutes.append(summary)
    return summary
  }

  /// Drops summaries older than the retention period; returns the cutoff used.
  @discardableResult
  public mutating func prune(now: Date) -> Date {
    let cutoff = now.addingTimeInterval(-Self.retention)
    minutes.removeAll { $0.start < cutoff }
    return cutoff
  }

  public mutating func clear() {
    minutes = []
    _ = flush()
  }

  private static let labels = ["healthy", "bothSlow", "routerSlower", "unreachable"]

  private static func severity(_ health: Health) -> Int {
    switch health {
    case .healthy: 0
    case .bothSlow: 1
    case .routerSlower: 2
    case .unreachable: 3
    }
  }

  private static func median<Value: Comparable>(_ values: [Value]) -> Value? {
    let sorted = values.sorted()
    return sorted.isEmpty ? nil : sorted[sorted.count / 2]
  }

  private static func minuteStart(_ date: Date) -> Date {
    Date(
      timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60
    )
  }
}

// Explicit nulls, so every stored and reported minute lists all fields.

extension TargetSummary {
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(median, forKey: .median)
    try container.encode(p95, forKey: .p95)
    try container.encode(loss, forKey: .loss)
  }
}

extension MinuteSummary {
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(start, forKey: .start)
    try container.encode(ssid, forKey: .ssid)
    try container.encode(samples, forKey: .samples)
    try container.encode(accessPoint, forKey: .accessPoint)
    try container.encode(router, forKey: .router)
    try container.encode(internet, forKey: .internet)
    try container.encode(received, forKey: .received)
    try container.encode(sent, forKey: .sent)
    try container.encode(rssi, forKey: .rssi)
    try container.encode(noise, forKey: .noise)
    try container.encode(transmitRate, forKey: .transmitRate)
    try container.encode(worstHealth, forKey: .worstHealth)
  }
}
