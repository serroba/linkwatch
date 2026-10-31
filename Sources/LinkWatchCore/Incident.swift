public import Foundation

/// Evidence for one link across an incident.
public struct IncidentLink: Codable, Equatable, Sendable {
  /// The slowest minute median, or nil when no minute had a reply.
  public var worstMedian: Double?
  /// Loss averaged over the incident's minutes, weighted by samples.
  public var loss: Double
}

/// A run of problem minutes on one network with the most likely cause.
public struct Incident: Codable, Equatable, Sendable {
  public var start: Date
  /// The end of the last problem minute.
  public var end: Date
  public var ssid: String
  public var verdict: Verdict
  public var problemMinutes: Int
  public var accessPoint: IncidentLink
  public var router: IncidentLink
  public var internet: IncidentLink?
  /// Bytes the Mac moved during the incident, for context on busy connections.
  public var received: UInt64?
  public var sent: UInt64?

  public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Groups stored minutes into incidents using the same rules as the live verdict.
public enum IncidentTimeline {
  /// Clear or missing minutes inside a run that still count as one incident.
  public static let allowedGapMinutes = 2
  /// Shorter runs are treated as blips rather than incidents.
  public static let minimumProblemMinutes = 2

  public static func incidents(from minutes: [MinuteSummary], profiles: [NetworkProfile])
    -> [Incident]
  {
    let thresholds = Dictionary(profiles.map { ($0.ssid, $0.thresholds) }) { first, _ in first }
    let peaks = Dictionary(grouping: minutes, by: \.ssid).mapValues {
      $0.compactMap(\.bitsPerSecond).max() ?? 0
    }
    let problems = minutes.sorted { $0.start < $1.start }.compactMap { minute in
      let verdict = Verdict(
        LinkEvidence(minute, peakBitsPerSecond: peaks[minute.ssid] ?? 0),
        thresholds: thresholds[minute.ssid] ?? Thresholds())
      return verdict.isProblem ? (minute, verdict) : nil
    }
    var runs: [[(MinuteSummary, Verdict)]] = []
    for problem in problems {
      if let last = runs.last?.last, last.0.ssid == problem.0.ssid,
        last.1.family == problem.1.family,
        problem.0.start.timeIntervalSince(last.0.start) <= Double(allowedGapMinutes + 1) * 60
      {
        runs[runs.count - 1].append(problem)
      } else {
        runs.append([problem])
      }
    }
    return merged(runs.filter { $0.count >= minimumProblemMinutes }).compactMap(incident)
  }

  /// Joins runs about the same link once blips of another link, too short to be incidents,
  /// are removed, so a one-minute interruption does not split an incident in two.
  private static func merged(_ runs: [[(MinuteSummary, Verdict)]]) -> [[(MinuteSummary, Verdict)]] {
    var result: [[(MinuteSummary, Verdict)]] = []
    for run in runs {
      if let last = result.last?.last, let first = run.first, last.0.ssid == first.0.ssid,
        last.1.family == first.1.family,
        first.0.start.timeIntervalSince(last.0.start) <= Double(allowedGapMinutes + 1) * 60
      {
        result[result.count - 1] += run
      } else {
        result.append(run)
      }
    }
    return result
  }

  private static func incident(_ run: [(MinuteSummary, Verdict)]) -> Incident? {
    guard let first = run.first?.0, let last = run.last?.0 else { return nil }
    let minutes = run.map(\.0)
    let counts = Dictionary(grouping: run.map(\.1)) { $0 }.mapValues(\.count)
    let verdict = counts.max { $0.value < $1.value || ($0.value == $1.value && $0.key < $1.key) }
    let probed = minutes.filter { $0.internet != nil }
    return Incident(
      start: first.start, end: last.start.addingTimeInterval(60), ssid: first.ssid,
      verdict: verdict?.key ?? .allClear, problemMinutes: run.count,
      accessPoint: link(minutes.map(\.accessPoint), minutes),
      router: link(minutes.map(\.router), minutes),
      internet: probed.isEmpty ? nil : link(probed.compactMap(\.internet), probed),
      received: total(minutes.map(\.received)), sent: total(minutes.map(\.sent)))
  }

  private static func link(_ targets: [TargetSummary], _ minutes: [MinuteSummary])
    -> IncidentLink
  {
    let samples = minutes.map(\.samples)
    let total = samples.reduce(0, +)
    let lost = zip(targets, samples).reduce(0.0) { $0 + $1.0.loss * Double($1.1) }
    return IncidentLink(
      worstMedian: targets.compactMap(\.median).max(),
      loss: total == 0 ? 0 : lost / Double(total))
  }

  private static func total(_ values: [UInt64?]) -> UInt64? {
    let known = values.compactMap { $0 }
    return known.isEmpty ? nil : known.reduce(0, &+)
  }
}

extension Verdict: Comparable {
  /// Orders ties towards the verdict that needs action, so advice is never understated.
  public static func < (lhs: Verdict, rhs: Verdict) -> Bool {
    lhs.priority < rhs.priority
  }

  private var priority: Int {
    switch self {
    case .allClear: 0
    case .busy: 1
    case .internetSpikes: 2
    case .accessPointSpikes: 3
    case .bridgeSpikes: 4
    case .routerSilent: 5
    case .routerUnreachable: 6
    case .internet: 7
    case .accessPoint: 8
    case .bridge: 9
    }
  }

  /// Verdicts about the same link group into one incident; a change of link starts another.
  var family: Int {
    switch self {
    case .allClear: 0
    case .accessPoint, .accessPointSpikes: 1
    case .bridge, .bridgeSpikes: 2
    case .internet, .internetSpikes: 3
    case .routerSilent, .routerUnreachable: 4
    case .busy: 5
    }
  }

  /// A short name for timelines, naming the bridge when the profile does.
  public func label(bridge: String?) -> String {
    switch self {
    case .allClear: "no problem"
    case .accessPoint: "Wi-Fi or access point"
    case .bridge: bridge ?? "link between access point and router"
    case .routerSilent: "router not answering (internet working)"
    case .routerUnreachable: "router not answering"
    case .internet: "internet provider"
    case .busy: "busy connection"
    case .accessPointSpikes: "lag spikes on Wi-Fi"
    case .bridgeSpikes: "lag spikes on " + (bridge ?? "the link between access point and router")
    case .internetSpikes: "lag spikes on the internet"
    }
  }
}

extension Incident {
  /// One readable line, for example
  /// "Sat 31 Oct 19:40–20:05 (25 min) on Home: TP-Link powerline adapters".
  public func summary(bridge: String?) -> String {
    let day = DateFormatter()
    day.setLocalizedDateFormatFromTemplate("EEE d MMM HH:mm")
    let time = DateFormatter()
    time.setLocalizedDateFormatFromTemplate("HH:mm")
    let minutes = Int(duration / 60)
    return "\(day.string(from: start))–\(time.string(from: end)) (\(minutes) min) on \(ssid): "
      + verdict.label(bridge: bridge)
  }

  /// The links' evidence in one line, so the cause can be checked rather than trusted.
  public var evidence: String {
    var parts = [
      "AP \(Self.describe(accessPoint))", "router \(Self.describe(router))",
    ]
    if let internet { parts.append("internet \(Self.describe(internet))") }
    if let received, let sent {
      parts.append(
        String(format: "↓ %.0f MB ↑ %.0f MB", Double(received) / 1e6, Double(sent) / 1e6))
    }
    return parts.joined(separator: " · ")
  }

  private static func describe(_ link: IncidentLink) -> String {
    let worst = link.worstMedian.map { String(format: "worst %.0f ms", $0) } ?? "no reply"
    return worst + String(format: ", %.0f%% lost", link.loss * 100)
  }
}

// Explicit nulls, matching the rest of the JSON output.

extension IncidentLink {
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(worstMedian, forKey: .worstMedian)
    try container.encode(loss, forKey: .loss)
  }
}

extension Incident {
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(start, forKey: .start)
    try container.encode(end, forKey: .end)
    try container.encode(ssid, forKey: .ssid)
    try container.encode(verdict, forKey: .verdict)
    try container.encode(problemMinutes, forKey: .problemMinutes)
    try container.encode(accessPoint, forKey: .accessPoint)
    try container.encode(router, forKey: .router)
    try container.encode(internet, forKey: .internet)
    try container.encode(received, forKey: .received)
    try container.encode(sent, forKey: .sent)
  }
}
