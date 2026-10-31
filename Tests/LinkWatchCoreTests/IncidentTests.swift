import Foundation
import Testing

@testable import LinkWatchCore

private let origin = Date(timeIntervalSinceReferenceDate: 800_000_040)

/// A stored minute; `router: nil` means the router never replied.
private func minute(
  _ index: Int, router: Double? = 6, internet: Double? = 10, ssid: String = "Home",
  received: UInt64? = nil
) -> MinuteSummary {
  var summary = MinuteSummary(
    start: origin.addingTimeInterval(Double(index) * 60), ssid: ssid, samples: 30,
    accessPoint: target(3, 4, loss: 0), router: target(router, router, loss: router == nil ? 1 : 0),
    internet: target(internet, internet, loss: internet == nil ? 1 : 0), worstHealth: "healthy")
  summary.received = received
  summary.sent = received.map { _ in 0 }
  return summary
}

@Test func problemMinutesGroupAcrossShortGaps() {
  let minutes = [
    minute(0), minute(1, router: 80), minute(2, router: 80), minute(3), minute(4),
    minute(5, router: 80), minute(9, router: 80), minute(10, router: 80), minute(11),
  ]
  let incidents = IncidentTimeline.incidents(from: minutes, profiles: [])
  #expect(incidents.count == 2)
  #expect(incidents.first?.start == origin.addingTimeInterval(60))
  #expect(incidents.first?.end == origin.addingTimeInterval(6 * 60))
  #expect(incidents.first?.problemMinutes == 3)
  #expect(incidents.first?.verdict == .bridge)
  #expect(incidents.last?.problemMinutes == 2)
}

@Test func blipsAndNetworkChangesDoNotFormIncidents() {
  let minutes = [
    minute(0, router: 80), minute(1, router: 80, ssid: "Cafe"), minute(5, router: 80),
  ]
  #expect(IncidentTimeline.incidents(from: minutes, profiles: []).isEmpty)
}

@Test func incidentVerdictIsTheMostCommonWithActionableTies() {
  let majority = [minute(0, router: 80), minute(1, router: nil), minute(2, router: nil)]
  #expect(IncidentTimeline.incidents(from: majority, profiles: []).first?.verdict == .routerSilent)
  let tie = [minute(0, router: 80), minute(1, router: nil)]
  #expect(IncidentTimeline.incidents(from: tie, profiles: []).first?.verdict == .bridge)
  #expect(Verdict.busy < .bridge)
}

@Test func incidentsUseProfileThresholdsAndLoad() {
  var tolerant = NetworkProfile(ssid: "Home", accessPoint: "192.0.2.2", router: "192.0.2.1")
  tolerant.thresholds.difference = 100
  tolerant.thresholds.recoveryDifference = 50
  let slow = [minute(0, router: 80), minute(1, router: 80)]
  #expect(IncidentTimeline.incidents(from: slow, profiles: [tolerant]).isEmpty)
  let loaded = [
    minute(0, router: 80, received: 90_000_000), minute(1, router: 80, received: 90_000_000),
  ]
  let busy = IncidentTimeline.incidents(from: loaded, profiles: [])
  #expect(busy.first?.verdict == .busy)
  #expect(busy.first?.received == 180_000_000)
}

@Test func incidentEvidenceAndSummaryAreReadable() throws {
  var lossy = minute(1, router: 120)
  lossy.router = target(120, 150, loss: 0.5)
  let minutes = [minute(0, router: 80), lossy, minute(2, router: 60, internet: nil)]
  let incident = try #require(IncidentTimeline.incidents(from: minutes, profiles: []).first)
  #expect(incident.router.worstMedian == 120)
  #expect(incident.router.loss == 0.5 / 3)
  #expect(incident.internet?.loss == 1.0 / 3)
  #expect(incident.duration == 180)
  #expect(incident.evidence.hasPrefix("AP worst 3 ms, 0% lost · router worst 120 ms, 17% lost"))
  #expect(incident.summary(bridge: "TP-Link").hasSuffix("(3 min) on Home: TP-Link"))
  #expect(incident.summary(bridge: nil).hasSuffix("link between access point and router"))
  #expect(try JSONDecoder().decode(Incident.self, from: JSONEncoder().encode(incident)) == incident)
}

@Test func incidentsCommandParses() throws {
  #expect(try HeadlessCommand.parse(["incidents"]) == .incidents(days: 7, json: false))
  #expect(
    try HeadlessCommand.parse(["incidents", "--days", "1", "--json"])
      == .incidents(days: 1, json: true))
  #expect(throws: HeadlessCommand.UsageError.self) {
    try HeadlessCommand.parse(["incidents", "--days", "8"])
  }
}

@MainActor
@Test func panelShowsTheLastDaysIncidentsNewestFirst() {
  let history = FakeHistoryStore()
  let now = Date(timeIntervalSinceReferenceDate: 800_000_040)
  func stored(_ minutesAgo: Int) -> MinuteSummary {
    var summary = minute(0, router: 80)
    summary.start = now.addingTimeInterval(Double(-minutesAgo) * 60)
    return summary
  }
  history.saved = [stored(2000), stored(1999), stored(120), stored(119), stored(30), stored(29)]
  let harness = Harness(history: history)
  let incidents = harness.controller.recentIncidents
  #expect(incidents.count == 2)
  #expect(incidents.first?.start == now.addingTimeInterval(-30 * 60))
}
