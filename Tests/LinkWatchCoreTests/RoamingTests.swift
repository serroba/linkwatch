import Foundation
import Testing

@testable import LinkWatchCore

/// The router's own radio, as seen in the living room.
private let routerRadio = NetworkIdentity(
  ssid: "Home", bssid: "00:00:5e:00:53:21", interface: "en0")
/// The access point's radio behind the powerline adapters, elsewhere in the house.
private let accessPointRadio = NetworkIdentity(
  ssid: "Home", bssid: "00:00:5e:00:53:41", interface: "en0")

private let house = [
  NeighborEntry(address: "192.0.2.1", hardwareAddress: "00:00:5e:00:53:20", interface: "en0"),
  NeighborEntry(address: "192.0.2.2", hardwareAddress: "00:00:5e:00:53:40", interface: "en0"),
]

@MainActor
@Test func movingAroundTheHouseFollowsTheConnectedRadio() async {
  let harness = Harness()
  harness.environment.router = "192.0.2.1"
  harness.environment.neighborEntries = house
  harness.environment.network = routerRadio
  harness.controller.networkChanged()
  #expect(harness.controller.connectionPath == .router)
  #expect(harness.controller.onRouterRadio)
  #expect(harness.controller.suggestion == nil)
  // The access point is still pinged, across the bridge, from the router's Wi-Fi.
  _ = await harness.cycle()
  #expect(Set(harness.script.requests) == ["192.0.2.2@en0", "192.0.2.1@en0"])

  harness.environment.network = accessPointRadio
  harness.controller.refresh()
  #expect(harness.controller.connectionPath == .accessPoint)
  #expect(!harness.controller.onRouterRadio)
}

@MainActor
@Test func aSlowAccessPointOnlyInformsWhileOnTheRouterWiFi() async {
  var profile = homeProfile
  profile.bridgeName = "TP-Link powerline adapters"
  let harness = Harness(profiles: [profile])
  harness.environment.router = "192.0.2.1"
  harness.environment.neighborEntries = house
  harness.environment.network = routerRadio
  harness.controller.networkChanged()
  harness.script.outcomes = [
    "192.0.2.1": .success(milliseconds: 5), "192.0.2.2": .success(milliseconds: 90),
  ]
  for _ in 0..<15 { _ = await harness.cycle() }
  #expect(harness.controller.verdict == .allClear)
  #expect(
    harness.controller.accessPointNote?.hasPrefix(
      "The access point is slow to reach through the TP-Link powerline adapters.") == true)
  harness.script.outcomes["192.0.2.2"] = .timeout
  for _ in 0..<60 { _ = await harness.cycle() }
  #expect(harness.controller.verdict == .allClear)
  #expect(
    harness.controller.accessPointNote?.hasPrefix("The access point is not answering") == true)
  let report = StatusReport(controller: harness.controller, now: harness.clock.now)
  #expect(report.path == .router)
  #expect(report.text.contains("Path:        router's own Wi-Fi"))
  #expect(report.text.contains("AP note:     The access point is not answering"))
  harness.controller.flushHistory()
  #expect(harness.history.saved.last?.path == .router)
}

@MainActor
@Test func latencyTellsThePathWhenAddressesDoNotMatch() async {
  let harness = Harness()
  harness.environment.router = "192.0.2.1"
  harness.controller.networkChanged()
  #expect(harness.controller.connectionPath == nil)
  harness.script.outcomes = [
    "192.0.2.2": .success(milliseconds: 3), "192.0.2.1": .success(milliseconds: 9),
  ]
  for _ in 0..<5 { _ = await harness.cycle() }
  #expect(harness.controller.connectionPath == .accessPoint)
  let report = StatusReport(controller: harness.controller, now: harness.clock.now)
  #expect(report.text.contains("Path:        through the access point"))
}

@Test func pathsFromLatencyNeedAClearDifference() {
  func path(_ accessPoint: Double, _ router: Double) -> ConnectionPath? {
    ConnectionPath(
      profile: homeProfile, discovery: nil,
      evidence: LinkEvidence(
        accessPoint: TargetEvidence(median: accessPoint, loss: 0),
        router: TargetEvidence(median: router, loss: 0), internet: nil))
  }
  #expect(path(3, 9) == .accessPoint)
  #expect(path(15, 5) == .router)
  #expect(path(5, 6) == nil)
  let single = NetworkProfile(ssid: "Home", accessPoint: "", router: "192.0.2.1")
  #expect(
    ConnectionPath(
      profile: single, discovery: nil,
      evidence: LinkEvidence(
        accessPoint: TargetEvidence(median: nil, loss: 1),
        router: TargetEvidence(median: nil, loss: 1), internet: nil)) == .router)
}

@Test func storedMinutesOnTheRouterWiFiAreJudgedByTheRouter() {
  var minute = MinuteSummary(
    start: Date(timeIntervalSinceReferenceDate: 800_000_000), ssid: "Home", samples: 30,
    accessPoint: target(90, 120, loss: 0), router: target(5, 8, loss: 0),
    internet: target(12, 20, loss: 0), worstHealth: "healthy")
  #expect(Verdict(LinkEvidence(minute), thresholds: Thresholds()) != .allClear)
  minute.path = .router
  #expect(Verdict(LinkEvidence(minute), thresholds: Thresholds()) == .allClear)
}

@MainActor
@Test func theConnectedDeviceIsRecheckedEveryMinuteAndOnRequest() {
  let harness = Harness()
  harness.environment.router = "192.0.2.1"
  harness.environment.network = accessPointRadio
  harness.controller.networkChanged()
  #expect(harness.controller.discovery?.accessPoint == .unknown)
  harness.environment.neighborEntries = house
  harness.controller.refresh()
  #expect(harness.controller.discovery?.accessPoint == .unknown)
  harness.clock.now += 60
  harness.controller.refresh()
  #expect(harness.controller.discovery?.accessPoint == .found("192.0.2.2"))
  harness.environment.neighborEntries = []
  harness.controller.detectPath()
  #expect(harness.controller.discovery?.accessPoint == .unknown)
}

@Test func detectCommandParses() throws {
  #expect(try HeadlessCommand.parse(["detect"]) == .detect)
}

@MainActor
@Test func aNetworkFirstSeenOnTheRouterRadioGainsItsAccessPointLater() {
  let harness = Harness(profiles: nil)
  harness.environment.router = "192.0.2.1"
  harness.environment.neighborEntries = house
  harness.environment.network = routerRadio
  harness.controller.networkChanged()
  #expect(harness.controller.acceptSuggestion())
  #expect(harness.controller.profiles.first?.accessPoint.isEmpty == true)
  #expect(harness.controller.profiles.first?.accessPointText == "none")

  // Joining the access point saves it with the network; nothing needs accepting.
  harness.environment.network = accessPointRadio
  harness.controller.refresh()
  #expect(harness.controller.profiles.first?.accessPoint == "192.0.2.2")
  #expect(harness.controller.suggestion == nil)

  // Back in the living room the saved AP stays, still pinged, and nothing is suggested.
  harness.environment.network = routerRadio
  harness.controller.refresh()
  #expect(harness.controller.suggestion == nil)
  #expect(harness.controller.onRouterRadio)
  #expect(harness.controller.profiles.first?.accessPoint == "192.0.2.2")
}

@MainActor
@Test func profilesWithoutAnAccessPointSaveFromSettings() {
  let harness = Harness(profiles: nil)
  let draft = NetworkProfile(ssid: "Home", accessPoint: "", router: "192.0.2.1")
  #expect(draft.isValid)
  #expect(harness.controller.save(draft))
  #expect(!NetworkProfile(ssid: "Home", accessPoint: "router", router: "192.0.2.1").isValid)
}

@Test func profilesCanBeCreatedAndClearedWithoutAnAccessPoint() throws {
  var create = ["--ssid", "Home", "--router", "192.0.2.1"]
  let created = try ProfileUpdate(parsing: &create).applied(to: nil)
  #expect(created?.accessPoint.isEmpty == true)
  #expect(created?.isValid == true)
  var clear = ["--ssid", "Home", "--ap", "none"]
  #expect(try ProfileUpdate(parsing: &clear).applied(to: homeProfile)?.isSingleDevice == true)
}

/// Only the router is in the ARP cache, as on a laptop whose profile has no access point.
private let routerOnly = [
  NeighborEntry(address: "192.0.2.1", hardwareAddress: "00:00:5e:00:53:20", interface: "en0")
]

@MainActor
@Test func aProfileWithoutAnAccessPointNoticesItIsBehindOneAndRemembersIt() {
  let noAccessPoint = NetworkProfile(
    ssid: "Home", accessPoint: "", router: "192.0.2.1", internetReferences: false)
  let harness = Harness(profiles: [noAccessPoint])
  harness.environment.router = "192.0.2.1"
  harness.environment.neighborEntries = routerOnly
  harness.environment.network = routerRadio
  harness.controller.networkChanged()
  #expect(harness.controller.connectionPath == .router)
  #expect(!harness.controller.behindUnknownAccessPoint)

  harness.environment.network = accessPointRadio
  harness.controller.refresh()
  #expect(harness.controller.connectionPath == .accessPoint)
  #expect(harness.controller.behindUnknownAccessPoint)
  let report = StatusReport(controller: harness.controller, now: harness.clock.now)
  #expect(report.text.contains("Path:        through an access point the profile does not know"))

  // Find it fills the ARP cache; the AP is then saved with the network.
  harness.environment.neighborEntries = house
  harness.controller.detectPath()
  #expect(harness.controller.profiles.first?.accessPoint == "192.0.2.2")
  #expect(harness.store.saved?.first?.accessPoint == "192.0.2.2")
  #expect(!harness.controller.behindUnknownAccessPoint)
  #expect(harness.controller.connectionPath == .accessPoint)
}

@MainActor
@Test func aSavedAccessPointIsNeverOverwrittenAutomatically() {
  var other = homeProfile
  other.accessPoint = "192.0.2.9"
  let harness = Harness(profiles: [other])
  harness.environment.router = "192.0.2.1"
  harness.environment.neighborEntries = house
  harness.environment.network = accessPointRadio
  harness.controller.networkChanged()
  #expect(harness.controller.profiles.first?.accessPoint == "192.0.2.9")
  guard case .update(_, let proposed) = harness.controller.suggestion else {
    Issue.record("Expected an offer to update the access point")
    return
  }
  #expect(proposed.accessPoint == "192.0.2.2")
}

@MainActor
@Test func hotspotsAreTheRouterWhateverTheirRadioLooksLike() {
  let phone = NetworkProfile(ssid: "Home", accessPoint: "", router: "192.0.2.1", hotspot: true)
  let harness = Harness(profiles: [phone])
  harness.environment.router = "192.0.2.1"
  harness.environment.neighborEntries = routerOnly
  harness.environment.network = accessPointRadio
  harness.controller.networkChanged()
  #expect(harness.controller.connectionPath == .router)
  #expect(!harness.controller.behindUnknownAccessPoint)
}

@Test func radiosFurtherFromTheWiredAddressStillMatchWhenUnambiguous() {
  let farRadio = NetworkIdentity(ssid: "Home", bssid: "00:00:5e:00:53:5f", interface: "en0")
  let discovery = NetworkDiscovery(network: farRadio, router: "192.0.2.1", neighbors: house)
  #expect(discovery.accessPoint == .found("192.0.2.2"))
  let twin = NeighborEntry(
    address: "192.0.2.3", hardwareAddress: "00:00:5e:00:53:70", interface: "en0")
  let ambiguous = NetworkDiscovery(
    network: farRadio, router: "192.0.2.1", neighbors: house + [twin])
  #expect(ambiguous.accessPoint == .unknown)
}

@MainActor
@Test func anUnknownAccessPointIsSearchedForOncePerRadioAndHalfHour() async {
  let noAccessPoint = NetworkProfile(
    ssid: "Home", accessPoint: "", router: "192.0.2.1", internetReferences: false)
  let harness = Harness(profiles: [noAccessPoint])
  harness.environment.router = "192.0.2.1"
  harness.environment.neighborEntries = routerOnly
  harness.environment.network = routerRadio
  harness.controller.networkChanged()
  #expect(!harness.controller.accessPointSearchIsDue)

  harness.environment.network = accessPointRadio
  harness.controller.refresh()
  #expect(harness.controller.accessPointSearchIsDue)
  harness.script.outcomes = ["192.168.7.2": .timeout]
  await harness.controller.searchForAccessPoint()
  #expect(!harness.controller.accessPointSearchIsDue)
  #expect(
    harness.controller.accessPointSearch
      == .finished(
        "No device among 253 addresses (252 answered) matches the AP's radio 00:00:5e:00:53:41. Enter its address in Settings."
      ))
  harness.clock.now += MonitorController.automaticSearchInterval
  #expect(harness.controller.accessPointSearchIsDue)

  // The sweep fills the ARP cache; the AP is saved and nothing more is searched.
  harness.script.beforeReply = { harness.environment.neighborEntries = house }
  await harness.controller.searchForAccessPoint()
  #expect(harness.controller.profiles.first?.accessPoint == "192.0.2.2")
  #expect(!harness.controller.accessPointSearchIsDue)
}
