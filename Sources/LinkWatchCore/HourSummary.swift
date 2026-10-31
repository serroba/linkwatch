public import Foundation

/// One link's statistics across an hour of minute summaries.
public struct HourLink: Codable, Equatable, Sendable {
  /// Median of the minute medians.
  public var median: Double?
  /// The worst minute's 95th percentile.
  public var p95: Double?
  /// Loss weighted by each minute's samples.
  public var loss: Double

  init(_ targets: [TargetSummary], samples: [Int]) {
    let medians = targets.compactMap(\.median).sorted()
    median = medians.isEmpty ? nil : medians[medians.count / 2]
    p95 = targets.compactMap(\.p95).max()
    let total = samples.reduce(0, +)
    let lost = zip(targets, samples).reduce(0.0) { $0 + $1.0.loss * Double($1.1) }
    loss = total == 0 ? 0 : lost / Double(total)
  }
}

/// An hour of stored history, including how much of it was actually monitored.
public struct HourSummary: Codable, Equatable, Sendable {
  public var start: Date
  /// Minutes with data out of 60; low coverage means the Mac was asleep, paused or away.
  public var minutesRecorded: Int
  public var samples: Int
  public var accessPoint: HourLink
  public var router: HourLink
  /// Nil when no minute in the hour probed internet references.
  public var internet: HourLink?
  public var received: UInt64?
  public var sent: UInt64?
  public var problemMinutes: Int
  /// The most common problem verdict, or nil when every minute was clear.
  public var commonProblem: Verdict?

  public var coverage: Double { Double(minutesRecorded) / 60 }
}

/// Rolls minute summaries up into hours with the same verdict rules as the live view.
public enum HistoryRollup {
  public static func hours(
    _ minutes: [MinuteSummary], profiles: [NetworkProfile], calendar: Calendar = .current
  ) -> [HourSummary] {
    let thresholds = Dictionary(profiles.map { ($0.ssid, $0.thresholds) }) { first, _ in first }
    let peaks = Dictionary(grouping: minutes, by: \.ssid).mapValues {
      $0.compactMap(\.bitsPerSecond).max() ?? 0
    }
    let groups = Dictionary(grouping: minutes) { minute in
      calendar.dateInterval(of: .hour, for: minute.start)?.start ?? minute.start
    }
    return groups.sorted { $0.key < $1.key }.map { start, group in
      let samples = group.map(\.samples)
      let problems = group.map {
        Verdict(
          LinkEvidence($0, peakBitsPerSecond: peaks[$0.ssid] ?? 0),
          thresholds: thresholds[$0.ssid] ?? Thresholds())
      }.filter(\.isProblem)
      let probed = group.filter { $0.internet != nil }
      let counts = Dictionary(grouping: problems) { $0 }.mapValues(\.count)
      return HourSummary(
        start: start, minutesRecorded: Set(group.map(\.start)).count,
        samples: samples.reduce(0, +),
        accessPoint: HourLink(group.map(\.accessPoint), samples: samples),
        router: HourLink(group.map(\.router), samples: samples),
        internet: probed.isEmpty
          ? nil : HourLink(probed.compactMap(\.internet), samples: probed.map(\.samples)),
        received: total(group.map(\.received)), sent: total(group.map(\.sent)),
        problemMinutes: problems.count,
        commonProblem: counts.max {
          $0.value < $1.value || ($0.value == $1.value && $0.key < $1.key)
        }?.key)
    }
  }

  private static func total(_ values: [UInt64?]) -> UInt64? {
    let known = values.compactMap { $0 }
    return known.isEmpty ? nil : known.reduce(0, &+)
  }
}
