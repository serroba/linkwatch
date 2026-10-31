import Foundation

extension WeeklySummary {
  /// Plain recommendations, most important first; `hotspots` lists phone hotspot networks.
  public func advice(bridgeNames: [String: String], hotspots: Set<String> = []) -> [String] {
    guard monitoredMinutes > 0 else { return ["Nothing was recorded in this period."] }
    var advice: [String] = []
    let candidates = connectionAreas.isEmpty ? areas : connectionAreas
    let total = candidates.map(\.problemMinutes).reduce(0, +)
    if let dominant = candidates.first, dominant.problemMinutes * 2 >= total,
      dominant.incidents >= 3
    {
      let hotspot = hotspots.contains(dominant.ssid)
      let name = dominant.area.name(bridge: bridgeNames[dominant.ssid], hotspot: hotspot)
      advice.append(Self.advice(for: dominant.area, name: name, hotspot: hotspot))
    } else if areas.isEmpty {
      advice.append("No problems lasting two minutes or more.")
    }
    if load.heavyMinutes >= 10, let added = load.addedLatency, added >= 50 {
      advice.append(
        String(
          format:
            "Heavy downloads and uploads add about %.0f ms for everything else. If the router offers SQM or Smart Queue QoS, turning it on usually fixes this.",
          added))
    }
    if connectionMinutes >= 20, let peak = busiestHours.first,
      peak.problemMinutes * 10 >= connectionMinutes * 3
    {
      advice.append(
        String(
          format:
            "Problems cluster around %02d:00. Look for something that happens then, such as backups, a device switching on or a busy household.",
          peak.hour))
    }
    let judged = restarts.filter { ![.measuring, .noBaseline].contains($0.outcome) }
    if judged.count >= 2 {
      let helped = judged.filter { $0.outcome == .helped }.count
      advice.append("Restarts helped \(helped) of \(judged.count) times.")
    }
    return advice
  }

  private static func advice(for area: ProblemArea, name: String, hotspot: Bool) -> String {
    switch area {
    case .wifi where hotspot:
      "Most problems were on \(name): keep the Mac and the phone close, or connect them with a cable."
    case .wifi:
      "Most problems were on \(name): use the Mac closer to the access point, move the access point, or add another one."
    case .bridge:
      "Most problems were on \(name). If restarting keeps fixing them, consider replacing it with an Ethernet cable or a mesh system with its own backhaul."
    case .internet where hotspot:
      "Most problems were \(name): use the phone where reception is better, for example near a window."
    case .internet:
      "Most problems came from \(name); if it keeps happening, share a report with them."
    case .busy:
      "Most slowdowns were \(name); schedule big downloads and backups for when nobody is on a call."
    case .routerQuiet:
      "Most alerts were \(name); if the internet worked meanwhile, nothing needs fixing."
    }
  }

  private static func count(_ value: Int, _ noun: String) -> String {
    "\(value) \(noun)\(value == 1 ? "" : "s")"
  }

  /// A readable summary for terminals and exported reports.
  public func text(bridgeNames: [String: String], hotspots: Set<String> = []) -> String {
    var lines = ["Summary of the last \(days) day\(days == 1 ? "" : "s")"]
    let share = Double(monitoredMinutes) / Double(max(days, 1) * 1440) * 100
    lines.append(
      String(
        format: "  Monitored: %.0f h (%.0f%% of the period)", Double(monitoredMinutes) / 60, share))
    let incidents = areas.map(\.incidents).reduce(0, +)
    lines.append("  Problems: \(Self.count(incidents, "incident")), \(problemMinutes) min")
    for area in areas {
      let name = area.area.name(
        bridge: bridgeNames[area.ssid], hotspot: hotspots.contains(area.ssid))
      lines.append(
        "    \(name): \(Self.count(area.incidents, "incident")), \(area.problemMinutes) min"
          + " (longest \(area.longestMinutes) min)")
    }
    if !busiestHours.isEmpty {
      let hours = busiestHours.map {
        String(format: "%02d:00 (%d min)", $0.hour, $0.problemMinutes)
      }
      lines.append("  Busiest hours: " + hours.joined(separator: ", "))
    }
    if let heavy = load.heavyLatency, let quiet = load.quietLatency {
      lines.append(
        String(
          format: "  Under heavy use (%d min at 4 Mbit/s or more): %.0f ms, otherwise %.0f ms",
          load.heavyMinutes, heavy, quiet))
    }
    if !restarts.isEmpty {
      lines.append("  Restarts: \(restarts.count)")
      lines += restarts.map { "    " + $0.sentence }
    }
    lines.append("Advice")
    lines += advice(bridgeNames: bridgeNames, hotspots: hotspots).map { "  - " + $0 }
    return lines.joined(separator: "\n") + "\n"
  }
}
