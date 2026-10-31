import Foundation
import Testing

@testable import LinkWatchCore

private let hourStart = Date(timeIntervalSinceReferenceDate: 800_002_800)

private func stored(_ minute: Int, router: Double? = 6, received: UInt64? = 1_000_000)
  -> MinuteSummary
{
  var summary = MinuteSummary(
    start: hourStart.addingTimeInterval(Double(minute) * 60), ssid: "Home", samples: 30,
    accessPoint: target(3, 5, loss: 0),
    router: target(router, router, loss: router == nil ? 1 : 0),
    internet: target(10, 14, loss: 0), worstHealth: "healthy")
  summary.received = received
  summary.sent = received.map { $0 / 2 }
  return summary
}

@Test func hourlyRollupsReportCoverageEvidenceAndCommonProblem() {
  var utc = Calendar(identifier: .gregorian)
  utc.timeZone = TimeZone(identifier: "UTC") ?? .current
  let minutes = (0..<30).map { stored($0, router: $0 < 20 ? 6 : nil) } + [stored(65)]
  let hours = HistoryRollup.hours(minutes, profiles: [], calendar: utc)
  #expect(hours.count == 2)
  let first = hours[0]
  #expect(first.minutesRecorded == 30)
  #expect(first.coverage == 0.5)
  #expect(first.samples == 900)
  #expect(first.router.loss == 10.0 / 30)
  #expect(first.router.median == 6)
  #expect(first.internet?.median == 10)
  #expect(first.received == 30_000_000)
  #expect(first.problemMinutes == 10)
  #expect(first.commonProblem == .routerSilent)
  #expect(hours[1].commonProblem == nil)
  let table = HistoryRollup.table(hours)
  #expect(table.contains("10/30 mostly routerSilent"))
  #expect(table.contains("    30      15  "))
}

@MainActor
@Test func diagnosisFindsGapsAndExplainsMissingData() {
  let harness = Harness(profiles: nil)
  harness.environment.isPermitted = false
  harness.controller.refresh()
  let status = StatusReport(controller: harness.controller, now: harness.clock.now)
  let now = hourStart.addingTimeInterval(3600)
  let minutes = (0..<20).map { stored($0) } + (40..<60).map { stored($0) }
  let report = DiagnoseReport(
    status: status, appRunning: false, minutes: minutes, profiles: [], hours: 1, now: now,
    primaryInterface: "utun2")
  #expect(report.coverage == 40.0 / 60)
  #expect(
    report.gaps == [
      DiagnoseReport.Gap(
        start: hourStart.addingTimeInterval(1200), end: hourStart.addingTimeInterval(2400))
    ])
  #expect(report.incidents.isEmpty)
  #expect(report.notes.contains { $0.hasPrefix("The menu bar app is not running") })
  #expect(report.notes.contains("No network is set up for monitoring yet."))
  #expect(report.notes.contains { $0.hasPrefix("Location permission is missing") })
  #expect(report.notes.contains { $0.hasPrefix("1 unmonitored period") })
  #expect(report.notes.contains { $0.hasPrefix("No problems lasting two minutes") })
  #expect(!report.notes.contains { $0.contains("utun2") })
  let text = report.text(bridgeNames: [:])
  #expect(text.contains("Coverage: 67% of the period monitored; gaps:"))
  #expect(text.contains("for 20 min"))
  #expect(text.contains("Incidents: 0"))
}

@MainActor
@Test func diagnosisReportsIncidentsVpnAndPermissionHints() async throws {
  var named = homeProfile
  named.bridgeName = "TP-Link powerline adapters"
  let harness = Harness(profiles: [named])
  _ = await harness.cycle()
  let status = StatusReport(controller: harness.controller, now: harness.clock.now)
  let now = hourStart.addingTimeInterval(3600)
  let minutes = (0..<60).map { stored($0, router: (10..<15).contains($0) ? 90 : 6) }
  let report = DiagnoseReport(
    status: status, appRunning: true, minutes: minutes, profiles: [named], hours: 1, now: now,
    primaryInterface: "utun2", appVersion: "0.2.0")
  #expect(report.text(bridgeNames: [:]).hasPrefix("LinkWatch 0.2.0 diagnosis for the last 1 h"))
  #expect(report.coverage == 1)
  #expect(report.gaps.isEmpty)
  #expect(report.incidents.count == 1)
  #expect(report.incidents.first?.verdict == .bridge)
  #expect(
    report.notes == [
      "utun2 carries the default route (often a VPN); LinkWatch still measures over Wi-Fi."
    ])
  let text = report.text(bridgeNames: ["Home": "TP-Link powerline adapters"])
  #expect(text.contains("Incidents: 1"))
  #expect(text.contains("→ Restart the TP-Link powerline adapters."))
  #expect(text.contains("Hourly"))
  let encoder = JSONEncoder()
  encoder.dateEncodingStrategy = .iso8601
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .iso8601
  #expect(
    try decoder.decode(DiagnoseReport.self, from: encoder.encode(report)).incidents
      == report.incidents)
}

@Test func diagnoseCommandParses() throws {
  #expect(try HeadlessCommand.parse(["diagnose"]) == .diagnose(hours: 24, json: false))
  #expect(
    try HeadlessCommand.parse(["diagnose", "--hours", "168", "--json"])
      == .diagnose(hours: 168, json: true))
  #expect(throws: HeadlessCommand.UsageError.self) {
    try HeadlessCommand.parse(["diagnose", "--hours", "200"])
  }
}
