import Foundation

/// Typical link quality over a set of stored minutes.
public struct LinkSnapshot: Codable, Equatable, Sendable {
  public var minutes: Int
  /// Medians of the minutes' 95th percentiles: how bad the spikes typically were.
  public var accessPointP95: Double?
  public var routerP95: Double?
  public var internetP95: Double?
  public var routerLoss: Double
  /// The share of minutes with a problem verdict.
  public var problemShare: Double

  init(_ minutes: [MinuteSummary], problems: Set<Date>) {
    self.minutes = minutes.count
    accessPointP95 = Self.median(minutes.compactMap(\.accessPoint.p95))
    routerP95 = Self.median(minutes.compactMap(\.router.p95))
    internetP95 = Self.median(minutes.compactMap { $0.internet?.p95 })
    routerLoss =
      minutes.isEmpty ? 0 : minutes.map(\.router.loss).reduce(0, +) / Double(minutes.count)
    problemShare =
      minutes.isEmpty
      ? 0 : Double(minutes.filter { problems.contains($0.start) }.count) / Double(minutes.count)
  }

  private static func median(_ values: [Double]) -> Double? {
    let sorted = values.sorted()
    return sorted.isEmpty ? nil : sorted[sorted.count / 2]
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(minutes, forKey: .minutes)
    try container.encode(accessPointP95, forKey: .accessPointP95)
    try container.encode(routerP95, forKey: .routerP95)
    try container.encode(internetP95, forKey: .internetP95)
    try container.encode(routerLoss, forKey: .routerLoss)
    try container.encode(problemShare, forKey: .problemShare)
  }
}

/// How link quality around a marked activity compares with the rest of the period.
public struct MarkEffect: Codable, Equatable, Sendable {
  /// Marks needed before LinkWatch draws a conclusion.
  public static let minimumOccurrences = 3

  public var label: String
  public var occurrences: Int
  /// Minutes containing or following each mark.
  public var after: LinkSnapshot
  /// All other monitored minutes.
  public var baseline: LinkSnapshot
  /// A cautious one-line reading of the comparison.
  public var conclusion: String

  /// Groups marks by label (ignoring case) and compares the minutes they touch with the rest.
  public static func effects(
    events: [AppEvent], minutes: [MinuteSummary], profiles: [NetworkProfile]
  ) -> [MarkEffect] {
    let marks = events.filter { $0.kind == .marked }
    let problems = problemMinutes(minutes, profiles: profiles)
    let groups = Dictionary(grouping: marks) { ($0.detail ?? "").lowercased() }
    return groups.compactMap { _, group -> MarkEffect? in
      guard let label = group.first?.detail else { return nil }
      let touched = Set(group.flatMap { mark in affectedMinutes(by: mark.time) })
      let after = minutes.filter { touched.contains($0.start) }
      let baseline = minutes.filter { !touched.contains($0.start) }
      guard !after.isEmpty else { return nil }
      let effect = (
        after: LinkSnapshot(after, problems: problems),
        baseline: LinkSnapshot(baseline, problems: problems)
      )
      return MarkEffect(
        label: label, occurrences: group.count, after: effect.after, baseline: effect.baseline,
        conclusion: conclusion(
          occurrences: group.count, after: effect.after, baseline: effect.baseline))
    }.sorted { $0.occurrences > $1.occurrences }
  }

  /// The minute containing the mark and the next one, since a motor run or a restart can
  /// straddle a minute boundary.
  private static func affectedMinutes(by time: Date) -> [Date] {
    let start = (time.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60
    return [0, 60].map { Date(timeIntervalSinceReferenceDate: start + $0) }
  }

  private static func problemMinutes(_ minutes: [MinuteSummary], profiles: [NetworkProfile])
    -> Set<Date>
  {
    let thresholds = Dictionary(profiles.map { ($0.ssid, $0.thresholds) }) { first, _ in first }
    return Set(
      minutes.filter {
        Verdict(LinkEvidence($0), thresholds: thresholds[$0.ssid] ?? Thresholds()).isProblem
      }.map(\.start))
  }

  /// Names the first link whose spikes grow by at least 50 ms and double after the marks.
  static func conclusion(occurrences: Int, after: LinkSnapshot, baseline: LinkSnapshot)
    -> String
  {
    guard occurrences >= minimumOccurrences else {
      return "Not enough marks yet: mark it at least \(minimumOccurrences) times to compare."
    }
    func worse(_ after: Double?, _ baseline: Double?) -> Bool {
      guard let after, let baseline else { return false }
      return after - baseline >= 50 && after >= baseline * 2
    }
    if worse(after.accessPointP95, baseline.accessPointP95) {
      return "Most likely affects the Wi-Fi link to the access point."
    }
    if worse(after.routerP95, baseline.routerP95) || after.routerLoss - baseline.routerLoss >= 0.1 {
      return
        "Most likely affects the link between the access point and the router, such as powerline adapters."
    }
    if worse(after.internetP95, baseline.internetP95) {
      return "Coincides with slower internet; home links look unaffected."
    }
    return "No clear effect on any link."
  }
}
