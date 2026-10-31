import Foundation
import Testing

@testable import LinkWatchCore

@MainActor
@Test func newNetworkIsSuggestedButNotProbedUntilAccepted() async {
  let harness = Harness(profiles: nil)
  harness.environment.router = "192.0.2.1"
  harness.environment.neighborEntries = separateAccessPoint
  harness.controller.networkChanged()
  guard case .monitor(let discovery) = harness.controller.suggestion else {
    Issue.record("Expected a suggestion to monitor the new network")
    return
  }
  #expect(discovery.accessPoint == .found("192.0.2.2"))
  _ = await harness.cycle()
  #expect(harness.script.requests.isEmpty)

  #expect(harness.controller.acceptSuggestion())
  #expect(harness.controller.profiles.map(\.accessPoint) == ["192.0.2.2"])
  #expect(harness.controller.suggestion == nil)
  _ = await harness.cycle()
  #expect(
    Set(harness.script.requests)
      == ["192.0.2.2@en0", "192.0.2.1@en0", "1.1.1.1@en0", "8.8.8.8@en0"])
}

@MainActor
@Test func newNetworkWithoutSeparateAccessPointCannotBeAccepted() {
  let harness = Harness(profiles: nil)
  harness.environment.router = "192.0.2.1"
  harness.controller.networkChanged()
  guard case .monitor(let discovery) = harness.controller.suggestion else {
    Issue.record("Expected a suggestion to set up the new network")
    return
  }
  #expect(discovery.accessPoint == .unknown)
  #expect(!harness.controller.acceptSuggestion())
  #expect(harness.controller.profiles.isEmpty)
}

@MainActor
@Test func changedRouterOffersUpdateKeepingThresholds() {
  var thresholds = Thresholds()
  thresholds.sustainedSeconds = 30
  let saved = NetworkProfile(
    ssid: "Home", accessPoint: "192.0.2.2", router: "192.0.2.1", thresholds: thresholds)
  let harness = Harness(profiles: [saved])
  harness.environment.router = "192.0.2.9"
  harness.controller.networkChanged()
  var expected = saved
  expected.router = "192.0.2.9"
  #expect(harness.controller.suggestion == .update(current: saved, proposed: expected))
  #expect(harness.controller.session.profile?.router == "192.0.2.1")
  #expect(harness.controller.acceptSuggestion())
  #expect(harness.controller.profiles == [expected])
  #expect(harness.controller.suggestion == nil)
}

@MainActor
@Test func dismissedSuggestionReturnsOnlyWhenAddressesChange() {
  let harness = Harness(profiles: nil)
  harness.environment.router = "192.0.2.1"
  harness.controller.networkChanged()
  harness.controller.dismissSuggestion()
  harness.controller.networkChanged()
  #expect(harness.controller.suggestion == nil)
  harness.environment.neighborEntries = separateAccessPoint
  harness.controller.networkChanged()
  #expect(harness.controller.suggestion != nil)
}

@MainActor
@Test func discoveryRunsOnNetworkChangesOnly() {
  let harness = Harness()
  let reads = harness.environment.neighborReads
  for _ in 0..<5 { harness.controller.refresh() }
  #expect(harness.environment.neighborReads == reads)
  harness.controller.networkChanged()
  #expect(harness.environment.neighborReads == reads + 1)
  harness.environment.network = NetworkIdentity(
    ssid: "Home", bssid: "00:00:5e:00:53:02", interface: "en0")
  harness.controller.refresh()
  #expect(harness.environment.neighborReads == reads + 2)

  harness.environment.isPermitted = false
  harness.controller.networkChanged()
  #expect(harness.controller.discovery == nil)
  #expect(harness.controller.suggestion == nil)
}

@MainActor
@Test func statusReportMirrorsControllerState() async throws {
  let harness = Harness()
  harness.environment.router = "192.0.2.1"
  harness.controller.networkChanged()
  harness.script.outcomes["192.0.2.1"] = .success(milliseconds: 50)
  for _ in 0..<7 { _ = await harness.cycle() }
  harness.script.outcomes["192.0.2.1"] = .timeout
  _ = await harness.cycle()
  let report = StatusReport(controller: harness.controller, now: harness.clock.now)
  #expect(report.state == .unreachable)
  #expect(report.health == "unreachable(router)")
  #expect(report.reason == "No reply from router")
  #expect(report.network == homeNetwork)
  #expect(report.profile == homeProfile)
  #expect(report.latency.router == nil)
  #expect(report.latency.accessPoint == 5)
  #expect(report.samples == 8)
  #expect(report.historyFailures == 1)
  #expect(report.alertSeconds == 2)
  #expect(report.discovery == StatusReport.Discovery(router: "192.0.2.1", accessPoint: "unknown"))
  #expect(report.suggestion == nil)
  #expect(
    report.text.contains("State:       unreachable (unreachable(router)) — No reply from router"))
  #expect(report.text.contains("Latency:     AP 5.0 ms · Router —"))
  #expect(report.text.contains("Wi-Fi:       authorization authorized · interface en0 · on"))
  #expect(report.text.contains("Discovery:   router 192.0.2.1 · AP not in ARP cache"))

  let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any]
  #expect(json?["suggestion"] is NSNull)
  #expect((json?["latency"] as? [String: Any])?["router"] is NSNull)
  #expect(try JSONDecoder().decode(StatusReport.self, from: JSONEncoder().encode(report)) == report)
}

@MainActor
@Test func statusReportDescribesIdleSuggestion() {
  let harness = Harness(profiles: nil)
  harness.environment.router = "192.0.2.1"
  harness.environment.neighborEntries = separateAccessPoint
  harness.controller.networkChanged()
  let report = StatusReport(controller: harness.controller, now: harness.clock.now)
  #expect(report.state == .idle)
  #expect(report.alertSeconds == nil)
  #expect(report.suggestion?.kind == "monitor")
  #expect(report.suggestion?.ready == true)
  #expect(
    report.text.contains("Suggestion:  monitor this network (AP 192.0.2.2 · Router 192.0.2.1)"))
  #expect(report.text.contains("Profiles:    0 saved"))
}

@MainActor
@Test func accessPointSearchPingsSubnetOnceAndFindsAccessPoint() async {
  let harness = Harness(profiles: nil)
  harness.environment.router = "192.168.7.1"
  harness.controller.networkChanged()
  harness.script.beforeReply = {
    harness.environment.neighborEntries = [
      NeighborEntry(address: "192.168.7.1", hardwareAddress: "00:00:5e:00:53:99", interface: "en0"),
      NeighborEntry(address: "192.168.7.2", hardwareAddress: "00:00:5e:00:53:00", interface: "en0"),
    ]
  }
  await harness.controller.searchForAccessPoint()
  #expect(harness.script.requests.count == 253)
  #expect(Set(harness.script.requests).count == 253)
  #expect(harness.script.requests.allSatisfy { $0.hasSuffix("@en0") })
  #expect(harness.controller.discovery?.accessPoint == .found("192.168.7.2"))
  #expect(
    harness.controller.accessPointSearch
      == .finished("Found the AP at 192.168.7.2 after pinging 253 addresses."))
  guard case .monitor(let discovery) = harness.controller.suggestion else {
    Issue.record("Expected a ready suggestion after the search")
    return
  }
  #expect(discovery.proposedProfile != nil)
  #expect(harness.controller.profiles.isEmpty)
  let report = StatusReport(controller: harness.controller, now: harness.clock.now)
  #expect(report.text.contains("AP search:   Found the AP at 192.168.7.2"))
}

@MainActor
@Test func accessPointSearchRefusesWithoutSendingTraffic() async {
  let harness = Harness(profiles: nil)
  harness.environment.address = InterfaceAddress(address: "203.0.113.5", netmask: "255.255.255.0")
  await harness.controller.searchForAccessPoint()
  #expect(harness.script.requests.isEmpty)
  #expect(
    harness.controller.accessPointSearch == .finished(SubnetSweep.Refusal.notPrivate.description))

  harness.environment.address = nil
  await harness.controller.searchForAccessPoint()
  #expect(harness.script.requests.isEmpty)

  harness.environment.network = nil
  harness.controller.refresh()
  await harness.controller.searchForAccessPoint()
  #expect(harness.script.requests.isEmpty)
  #expect(
    harness.controller.accessPointSearch
      == .finished("Connect to Wi-Fi before searching for the AP."))
}

@MainActor
@Test func accessPointSearchReportsWhenNothingMatches() async {
  let harness = Harness(profiles: nil)
  harness.environment.address = InterfaceAddress(
    address: "192.168.7.21", netmask: "255.255.255.252")
  await harness.controller.searchForAccessPoint()
  #expect(harness.script.requests == ["192.168.7.22@en0"])
  #expect(
    harness.controller.accessPointSearch
      == .finished("No device among 1 address matches the AP. Enter its address in Settings."))
}

@MainActor
@Test func monitoringStoresMinuteSummariesAndFlushesOnPause() async {
  let harness = Harness()
  for _ in 0..<31 { _ = await harness.cycle() }
  #expect(harness.history.saved.count == 1)
  #expect(harness.history.saved.first?.samples == 30)
  #expect(harness.history.saved.first?.ssid == "Home")
  #expect(harness.history.saved.first?.accessPoint.median == 5)
  harness.controller.paused = true
  #expect(harness.history.saved.count == 2)
  #expect(harness.history.saved.last?.samples == 1)
  #expect(harness.controller.week.minutes.count == 2)
  let report = StatusReport(controller: harness.controller, now: harness.clock.now)
  #expect(report.weekMinutes == 2)
  #expect(report.text.contains("Week:        2 minute summaries since "))
}

@MainActor
@Test func storedHistoryLoadsWithinRetentionAndCanBeCleared() {
  let history = FakeHistoryStore()
  let start = Date(timeIntervalSinceReferenceDate: 800_000_040)
  let summary = MinuteSummary(
    start: start.addingTimeInterval(-3600), ssid: "Home", samples: 30,
    accessPoint: target(2, 3, loss: 0),
    router: target(5, 9, loss: 0), worstHealth: "healthy")
  var expired = summary
  expired.start = start.addingTimeInterval(-WeekHistory.retention - 60)
  history.saved = [expired, summary]
  let harness = Harness(history: history)
  #expect(harness.controller.week.minutes == [summary])
  #expect(history.saved == [summary])
  #expect(history.prunes == [start.addingTimeInterval(-WeekHistory.retention)])
  harness.controller.clearHistory()
  #expect(history.saved.isEmpty)
  #expect(harness.controller.week.minutes.isEmpty)
}

@MainActor
@Test func historyFailuresAreReportedWithoutStoppingMonitoring() async {
  let history = FakeHistoryStore()
  history.failsToLoad = true
  let harness = Harness(history: history)
  #expect(harness.controller.historyError != nil)
  history.failsToWrite = true
  for _ in 0..<31 { _ = await harness.cycle() }
  #expect(harness.controller.session.window.samples.count == 31)
  #expect(
    harness.controller.historyError
      == "History could not be saved; the menu shows only recent measurements.")
  harness.controller.clearHistory()
  #expect(harness.controller.historyError == "History could not be cleared.")
}
