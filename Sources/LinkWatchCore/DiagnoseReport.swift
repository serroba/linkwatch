public import Foundation

/// Everything needed to answer "what's going on with my network?" from evidence.
public struct DiagnoseReport: Codable, Equatable, Sendable {
  public struct Gap: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date
    /// The last event before the gap, which usually explains it ("asleep", "quit").
    public var before: String?
    /// The first event after it ("awake", "launched: 0.3.0").
    public var after: String?
  }

  public var generatedAt: Date
  /// The LinkWatch version that produced the report, such as `0.2.0`.
  public var appVersion: String?
  /// Whether LinkWatch starts at login, so recording resumes after a restart.
  public var opensAtLogin: Bool
  public var hours: Int
  /// Whether the menu bar app answered; otherwise `status` is a fresh local reading.
  public var appRunning: Bool
  public var status: StatusReport
  /// The interface owning the default route, such as `en0`, or a VPN like `utun2`.
  public var primaryInterface: String?
  /// Fraction of the period with stored minutes.
  public var coverage: Double
  /// Unmonitored spans of at least ten minutes.
  public var gaps: [Gap]
  public var incidents: [Incident]
  public var hourly: [HourSummary]
  /// App and system events in the period, oldest first.
  public var events: [AppEvent]
  /// How link quality around each marked activity compares with the rest of the period.
  public var markEffects: [MarkEffect]
  public var notes: [String]

  public static let minimumGapMinutes = 10
  /// The text report lists this many recent events; JSON has them all.
  public static let textEventLimit = 40

  public init(
    status: StatusReport, appRunning: Bool, minutes: [MinuteSummary],
    profiles: [NetworkProfile], hours: Int, now: Date, primaryInterface: String?,
    appVersion: String? = nil, opensAtLogin: Bool = true, events: [AppEvent] = []
  ) {
    let since = now.addingTimeInterval(-Double(hours) * 3600)
    let window = minutes.filter { $0.start >= since && $0.start <= now }
    generatedAt = now
    self.appVersion = appVersion
    self.opensAtLogin = opensAtLogin
    self.hours = hours
    self.appRunning = appRunning
    self.status = status
    self.primaryInterface = primaryInterface
    let recorded = Set(window.map(\.start))
    coverage = min(1, Double(recorded.count) / (Double(hours) * 60))
    let windowEvents = events.filter { $0.time >= since && $0.time <= now }
      .sorted { $0.time < $1.time }
    self.events = windowEvents
    markEffects = MarkEffect.effects(events: windowEvents, minutes: window, profiles: profiles)
    gaps = Self.gaps(recorded: recorded, since: since, now: now).map { gap in
      var annotated = gap
      // The cause usually lands inside the first missing minute, and the recovery inside
      // the last one, so each side allows a minute.
      annotated.before = windowEvents.last { $0.time < gap.start.addingTimeInterval(60) }?.summary
      annotated.after = windowEvents.first { $0.time > gap.end.addingTimeInterval(-60) }?.summary
      return annotated
    }
    incidents = IncidentTimeline.incidents(from: window, profiles: profiles)
    hourly = HistoryRollup.hours(window, profiles: profiles)
    notes = []
    notes = Self.notes(for: self, profiles: profiles)
  }

  private static func gaps(recorded: Set<Date>, since: Date, now: Date) -> [Gap] {
    let first = (since.timeIntervalSinceReferenceDate / 60).rounded(.up) * 60
    var gaps: [Gap] = []
    var gapStart: Date?
    var minute = Date(timeIntervalSinceReferenceDate: first)
    while minute.addingTimeInterval(60) <= now {
      if recorded.contains(minute) {
        if let start = gapStart { gaps.append(Gap(start: start, end: minute)) }
        gapStart = nil
      } else if gapStart == nil {
        gapStart = minute
      }
      minute.addTimeInterval(60)
    }
    if let gapStart { gaps.append(Gap(start: gapStart, end: minute)) }
    return gaps.filter { $0.end.timeIntervalSince($0.start) >= Double(minimumGapMinutes) * 60 }
  }

  private static func notes(for report: DiagnoseReport, profiles: [NetworkProfile]) -> [String] {
    var notes: [String] = []
    let status = report.status
    if !report.appRunning {
      notes.append(
        "The menu bar app is not running, so nothing is being recorded; the live section is a fresh local reading."
      )
    }
    if profiles.isEmpty { notes.append("No network is set up for monitoring yet.") }
    if !report.opensAtLogin {
      notes.append(
        "LinkWatch does not open at login, so nothing is recorded after a restart until it is opened. Turn it on with open-at-login on or in Settings."
      )
    }
    if !status.permitted {
      notes.append(
        "Location permission is missing, so the Wi-Fi network cannot be identified or monitored.")
    } else if status.network == nil {
      notes.append("Wi-Fi is off or not connected, so nothing is monitored right now.")
    }
    if let signal = status.signal, signal.isWeak {
      notes.append(
        "The Wi-Fi signal is weak (\(signal.rssi) dBm, SNR \(signal.snr) dB): moving closer to the access point should help more than restarting anything."
      )
    }
    if status.verdict == .routerSilent {
      notes.append(
        "The router ignores LinkWatch while the internet works: check Local Network permission.")
    }
    if let primary = report.primaryInterface, primary != status.network?.interface,
      status.network != nil
    {
      notes.append(
        "\(primary) carries the default route (often a VPN); LinkWatch still measures over Wi-Fi.")
    }
    if !report.gaps.isEmpty {
      notes.append(
        "\(report.gaps.count) unmonitored period\(report.gaps.count == 1 ? "" : "s"): the Mac was asleep, paused, away from a monitored network or LinkWatch was not running. No conclusions can be drawn for those times."
      )
    }
    if report.incidents.isEmpty && report.coverage > 0 {
      notes.append("No problems lasting two minutes or more were recorded while monitoring.")
    }
    return notes
  }
}

extension DiagnoseReport {
  /// A readable report that leads with the answer and keeps the evidence below it.
  public func text(bridgeNames: [String: String]) -> String {
    let time = DateFormatter()
    time.setLocalizedDateFormatFromTemplate("EEE d MMM HH:mm")
    var lines = [
      "LinkWatch" + (appVersion.map { " \($0)" } ?? "")
        + " diagnosis for the last \(hours) h (generated \(time.string(from: generatedAt)))",
      "",
      "Now",
    ]
    lines += status.text.split(separator: "\n").map { "  " + $0 }
    lines.append("")
    lines.append(
      String(
        format: "Coverage: %.0f%% of the period monitored", coverage * 100)
        + (gaps.isEmpty ? "" : "; gaps:"))
    lines += gapLines(time)
    lines.append("")
    lines.append("Incidents: \(incidents.count)")
    for incident in incidents.reversed() {
      let bridge = bridgeNames[incident.ssid]
      lines.append("  " + incident.summary(bridge: bridge))
      lines.append("    " + incident.evidence)
      lines.append("    → " + (incident.verdict.action(bridge: bridge) ?? "No action needed."))
    }
    if !hourly.isEmpty {
      lines.append("")
      lines.append("Hourly")
      lines += HistoryRollup.table(hourly).split(separator: "\n").map { "  " + $0 }
    }
    if !markEffects.isEmpty {
      lines.append("")
      lines.append("Marked activities")
      for effect in markEffects { lines += Self.describe(effect) }
    }
    lines += eventLines(time)
    if !notes.isEmpty {
      lines.append("")
      lines.append("Notes")
      lines += notes.map { "  - " + $0 }
    }
    return lines.joined(separator: "\n") + "\n"
  }
}

extension DiagnoseReport {
  private func gapLines(_ time: DateFormatter) -> [String] {
    var lines: [String] = []
    for gap in gaps {
      let minutes = Int(gap.end.timeIntervalSince(gap.start) / 60)
      var context = [gap.before.map { "after \($0)" }, gap.after.map { "until \($0)" }]
        .compactMap { $0 }.joined(separator: ", ")
      if !context.isEmpty { context = " (" + context + ")" }
      lines.append("  \(time.string(from: gap.start)) for \(minutes) min\(context)")
    }
    return lines
  }

  private func eventLines(_ time: DateFormatter) -> [String] {
    var lines: [String] = []
    if !events.isEmpty {
      lines.append("")
      lines.append("Events (latest \(min(events.count, Self.textEventLimit)) of \(events.count))")
      lines += events.suffix(Self.textEventLimit).map {
        "  \(time.string(from: $0.time))  \($0.summary)"
      }
    }
    return lines
  }

  fileprivate static func describe(_ effect: MarkEffect) -> [String] {
    func spikes(_ value: Double?) -> String { value.map { String(format: "%.0f ms", $0) } ?? "—" }
    let after = effect.after
    let baseline = effect.baseline
    return [
      "  \"\(effect.label)\" × \(effect.occurrences): \(effect.conclusion)",
      "    spikes (typical p95) after → otherwise: AP \(spikes(after.accessPointP95)) → "
        + "\(spikes(baseline.accessPointP95)) · router \(spikes(after.routerP95)) → "
        + "\(spikes(baseline.routerP95)) · internet \(spikes(after.internetP95)) → "
        + "\(spikes(baseline.internetP95))",
      String(
        format: "    problem minutes %.0f%% → %.0f%%, router loss %.0f%% → %.0f%%",
        after.problemShare * 100, baseline.problemShare * 100, after.routerLoss * 100,
        baseline.routerLoss * 100),
    ]
  }
}

extension HistoryRollup {
  /// A fixed-width table of hourly rollups for terminals.
  public static func table(_ hours: [HourSummary]) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:00"
    var lines = [
      "Hour              Mins  AP median/p95  loss   Router median/p95  loss   "
        + "Internet median/p95  loss    ↓ MB    ↑ MB  RSSI  Problem minutes"
    ]
    for hour in hours {
      var line = formatter.string(from: hour.start) + "  " + pad(String(hour.minutesRecorded), 4)
      line += "  " + link(hour.accessPoint) + "  " + link(hour.router) + "  "
      line += hour.internet.map(link) ?? pad("not probed", 21)
      line += "  " + megabytes(hour.received) + "  " + megabytes(hour.sent)
      line += "  " + pad(hour.rssi.map(String.init) ?? "—", 4)
      line += "  \(hour.problemMinutes)/\(hour.minutesRecorded)"
      if let common = hour.commonProblem { line += " mostly \(common.rawValue)" }
      lines.append(line)
    }
    return lines.joined(separator: "\n") + "\n"
  }

  private static func link(_ link: HourLink) -> String {
    let median = link.median.map { String(format: "%.1f", $0) } ?? "—"
    let p95 = link.p95.map { String(format: "%.1f", $0) } ?? "—"
    return pad("\(median)/\(p95) ms", 15) + "  " + pad(String(format: "%.0f%%", link.loss * 100), 4)
  }

  private static func megabytes(_ bytes: UInt64?) -> String {
    pad(bytes.map { String(format: "%.0f", Double($0) / 1_000_000) } ?? "—", 6)
  }

  private static func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : String(repeating: " ", count: width - text.count) + text
  }
}
