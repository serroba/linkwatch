import Foundation
import Testing

@testable import LinkWatchCore

private func evidence(
  accessPoint: Double = 5, router: Double = 12, internet: Double? = 14, busy: Bool = false
) -> LinkEvidence {
  LinkEvidence(
    accessPoint: TargetEvidence(median: 3, loss: 0, p95: accessPoint),
    router: TargetEvidence(median: 8, loss: 0, p95: router),
    internet: internet.map { TargetEvidence(median: 10, loss: 0, p95: $0) }, busy: busy)
}

@Test func spikesAreBlamedOnTheLinkWhereTheyStart() {
  let thresholds = Thresholds()
  #expect(Verdict(evidence(), thresholds: thresholds) == .allClear)
  #expect(
    Verdict(evidence(accessPoint: 150, router: 160, internet: 170), thresholds: thresholds)
      == .accessPointSpikes)
  #expect(Verdict(evidence(router: 400, internet: 410), thresholds: thresholds) == .bridgeSpikes)
  #expect(Verdict(evidence(internet: 300), thresholds: thresholds) == .internetSpikes)
  #expect(Verdict(evidence(router: 90, internet: 95), thresholds: thresholds) == .allClear)
  #expect(
    Verdict(evidence(router: 400, internet: 410, busy: true), thresholds: thresholds) == .busy)
  var slow = evidence(router: 400)
  slow.router.median = 60
  #expect(Verdict(slow, thresholds: thresholds) == .bridge)
}

@Test func spikeAdviceNamesTheBridge() {
  #expect(
    Verdict.bridgeSpikes.headline(bridge: "TP-Link powerline adapters")
      == "The connection between the access point and the router (TP-Link powerline adapters) has frequent lag spikes."
  )
  #expect(
    Verdict.bridgeSpikes.action(bridge: "TP-Link powerline adapters")?.hasPrefix(
      "If calls or video stutter, restart the TP-Link powerline adapters.") == true)
  #expect(Verdict.bridgeSpikes.label(bridge: "TP-Link") == "lag spikes on TP-Link")
  #expect(Verdict.bridgeSpikes < .routerSilent)
  #expect(Verdict.busy < .internetSpikes)
}

@Test func spikyStoredMinutesFormAnIncident() throws {
  let origin = Date(timeIntervalSinceReferenceDate: 800_000_040)
  let minutes = (0..<20).map { index in
    MinuteSummary(
      start: origin.addingTimeInterval(Double(index) * 60), ssid: "Home", samples: 30,
      accessPoint: target(3, 5, loss: 0),
      router: target(8, index % 3 == 2 ? 20 : 400, loss: 0),
      internet: target(10, index % 3 == 2 ? 22 : 410, loss: 0), worstHealth: "healthy")
  }
  let incident = try #require(IncidentTimeline.incidents(from: minutes, profiles: []).first)
  #expect(incident.verdict == .bridgeSpikes)
  #expect(incident.problemMinutes == 14)
  #expect(incident.duration == 20 * 60)
}

@MainActor
@Test func liveSpikesNeedSeveralSlowProbesPerMinute() async {
  let harness = Harness()
  var cycle = 0
  harness.script.beforeReply = {}
  func run(_ count: Int, spikeEvery: Int) async {
    for _ in 0..<count {
      cycle += 1
      harness.script.outcomes["192.0.2.1"] =
        cycle % spikeEvery == 0 ? .success(milliseconds: 350) : .success(milliseconds: 8)
      _ = await harness.cycle()
    }
  }
  await run(30, spikeEvery: 31)
  #expect(harness.controller.verdict == .allClear)
  await run(40, spikeEvery: 10)
  #expect(harness.controller.verdict == .bridgeSpikes)
  #expect(harness.controller.light == .unstable)
  #expect(harness.controller.session.window.routerMedian == 8)
}

@Test func reportsEncodeMissingValuesAsNull() throws {
  let incident = Incident(
    start: Date(timeIntervalSinceReferenceDate: 0), end: Date(timeIntervalSinceReferenceDate: 120),
    ssid: "Home", verdict: .routerUnreachable, problemMinutes: 2,
    accessPoint: IncidentLink(worstMedian: 3, loss: 0),
    router: IncidentLink(worstMedian: nil, loss: 1),
    internet: nil, received: nil, sent: nil)
  let json =
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(incident)) as? [String: Any]
  #expect(json?["internet"] is NSNull)
  #expect(json?["received"] is NSNull)
  #expect((json?["router"] as? [String: Any])?["worstMedian"] is NSNull)
  #expect(try JSONDecoder().decode(Incident.self, from: JSONEncoder().encode(incident)) == incident)
}

@Test func incidentsSplitWhenTheFailingLinkChanges() {
  let origin = Date(timeIntervalSinceReferenceDate: 800_000_040)
  func minute(_ index: Int, router: TargetSummary) -> MinuteSummary {
    MinuteSummary(
      start: origin.addingTimeInterval(Double(index) * 60), ssid: "Home", samples: 30,
      accessPoint: target(3, 5, loss: 0), router: router, internet: target(10, 14, loss: 0),
      worstHealth: "healthy")
  }
  let silent = target(nil, nil, loss: 1)
  let spiky = target(8, 400, loss: 0)
  let slow = target(60, 80, loss: 0)
  let minutes =
    (0..<5).map { minute($0, router: silent) } + (5..<9).map { minute($0, router: spiky) }
    + (9..<11).map { minute($0, router: slow) } + (11..<13).map { minute($0, router: spiky) }
  let incidents = IncidentTimeline.incidents(from: minutes, profiles: [])
  #expect(incidents.map(\.verdict) == [.routerSilent, .bridgeSpikes])
  #expect(incidents.last?.problemMinutes == 8)
}

@Test func aOneMinuteBlipOfAnotherLinkDoesNotSplitAnIncident() {
  let origin = Date(timeIntervalSinceReferenceDate: 800_000_040)
  func minute(_ index: Int, router: TargetSummary) -> MinuteSummary {
    MinuteSummary(
      start: origin.addingTimeInterval(Double(index) * 60), ssid: "Home", samples: 30,
      accessPoint: target(3, 5, loss: 0), router: router, internet: target(10, 14, loss: 0),
      worstHealth: "healthy")
  }
  let minutes =
    (0..<3).map { minute($0, router: target(60, 400, loss: 0)) }
    + [minute(3, router: target(nil, nil, loss: 1))]
    + (4..<8).map { minute($0, router: target(8, 400, loss: 0)) }
  let incidents = IncidentTimeline.incidents(from: minutes, profiles: [])
  #expect(incidents.count == 1)
  #expect(incidents.first?.problemMinutes == 7)
  #expect(incidents.first?.verdict == .bridgeSpikes)
}

@MainActor
@Test func readOnlyHistoryNeverWrites() async throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("LinkWatchReadOnly-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: directory) }
  let writer = FileHistoryStore(directory: directory)
  let old = MinuteSummary(
    start: Date(timeIntervalSinceReferenceDate: 0), ssid: "Home", samples: 30,
    accessPoint: target(3, 4, loss: 0), router: target(6, 8, loss: 0), internet: nil,
    worstHealth: "healthy")
  try writer.append(old)
  let reader = ReadOnlyHistoryStore(directory: directory)
  try reader.prune(before: .distantFuture)
  try reader.append(old)
  try reader.clear()
  #expect(try writer.load(since: .distantPast) == [old])
  #expect(try reader.load(since: .distantPast) == [old])
}
