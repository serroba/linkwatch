import Foundation
import Testing

@testable import LinkWatchCore

/// iPhone personal hotspots always use this range, so it identifies no particular network.
private let phoneRouter = "172.20.10.1"

@MainActor
@Test func singleDeviceProfileIsProbedOncePerCycle() async {
  let profile = NetworkProfile(
    ssid: "Home", accessPoint: "192.0.2.1", router: "192.0.2.1", internetReferences: false)
  #expect(profile.isValid)
  #expect(profile.isSingleDevice)
  let harness = Harness(profiles: [profile])
  harness.script.outcomes["192.0.2.1"] = .success(milliseconds: 7)
  _ = await harness.cycle()
  #expect(harness.script.requests == ["192.0.2.1@en0"])
  let report = StatusReport(controller: harness.controller, now: harness.clock.now)
  #expect(report.text.contains("7"))
}

@MainActor
@Test func routerActingAsAccessPointCanBeAccepted() {
  let harness = Harness(profiles: nil)
  harness.environment.router = "192.0.2.1"
  harness.environment.neighborEntries = [
    NeighborEntry(address: "192.0.2.1", hardwareAddress: "00:00:5e:00:53:01", interface: "en0")
  ]
  harness.controller.networkChanged()
  #expect(harness.controller.discovery?.accessPoint == .router)
  #expect(!harness.controller.isHotspot)
  #expect(harness.controller.acceptSuggestion())
  let saved = harness.controller.profiles.first
  #expect(saved?.isSingleDevice == true)
  #expect(saved?.hotspot == false)
}

@MainActor
@Test func iPhoneHotspotIsDetectedFromItsAddressRange() {
  let harness = Harness(profiles: nil)
  harness.environment.router = phoneRouter
  harness.environment.address = InterfaceAddress(
    address: "172.20.10.2", netmask: "255.255.255.240")
  harness.controller.networkChanged()
  #expect(harness.controller.discovery?.accessPoint == .unknown)
  #expect(harness.controller.isHotspot)
  let report = StatusReport(controller: harness.controller, now: harness.clock.now)
  #expect(report.suggestion?.ready == true)
  #expect(harness.controller.acceptSuggestion())
  let saved = harness.controller.profiles.first
  #expect(saved?.hotspot == true)
  #expect(saved?.isSingleDevice == true)
}

@MainActor
@Test func expensivePathMarksOtherPhonesAsHotspots() {
  let harness = Harness(profiles: nil)
  harness.environment.router = "192.0.2.1"
  harness.environment.isExpensivePath = true
  harness.controller.networkChanged()
  #expect(harness.controller.isHotspot)
  #expect(harness.controller.acceptSuggestion())
  #expect(harness.controller.profiles.first?.hotspot == true)
}

@MainActor
@Test func hotspotsPingTheInternetEveryTenSeconds() async {
  let profile = NetworkProfile(
    ssid: "Home", accessPoint: "192.0.2.1", router: "192.0.2.1", hotspot: true)
  let harness = Harness(profiles: [profile])
  for _ in 0..<10 { _ = await harness.cycle() }
  #expect(harness.script.requests.filter { $0.hasPrefix("1.1.1.1@") }.count == 2)
  #expect(harness.script.requests.filter { $0.hasPrefix("192.0.2.1@") }.count == 10)
}

@MainActor
@Test func hotspotAdviceNamesThePhone() {
  let profile = NetworkProfile(
    ssid: "Home", accessPoint: "192.0.2.1", router: "192.0.2.1", hotspot: true)
  let harness = Harness(profiles: [profile])
  harness.controller.refresh()
  #expect(harness.controller.advice.headline == Verdict.allClear.headline(bridge: nil))
  #expect(Verdict.internet.headline(bridge: nil, hotspot: true).contains("mobile reception"))
  #expect(Verdict.internet.action(bridge: nil, hotspot: true)?.contains("window") == true)
  #expect(Verdict.weakSignal.action(bridge: "TP-Link", hotspot: true)?.contains("cable") == true)
  #expect(Verdict.accessPointSpikes.label(bridge: nil, hotspot: true).contains("phone"))
  #expect(Verdict.busy.headline(bridge: nil, hotspot: true) == Verdict.busy.headline(bridge: nil))
  #expect(Verdict.busy.label(bridge: nil, hotspot: true) == Verdict.busy.label(bridge: nil))
}

@Test func hotspotSwitchParsesAndApplies() throws {
  var options = ["--ssid", "Home", "--hotspot", "on"]
  let update = try ProfileUpdate(parsing: &options)
  #expect(update.applied(to: homeProfile)?.hotspot == true)
  var off = ["--ssid", "Home", "--hotspot", "off"]
  #expect(try ProfileUpdate(parsing: &off).applied(to: homeProfile)?.hotspot == false)
  var invalid = ["--ssid", "Home", "--hotspot", "maybe"]
  #expect(throws: HeadlessCommand.UsageError.self) { try ProfileUpdate(parsing: &invalid) }
}

@Test func olderProfilesDecodeAsNotHotspots() throws {
  var json =
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(homeProfile))
    as? [String: Any]
  json?.removeValue(forKey: "hotspot")
  let data = try JSONSerialization.data(withJSONObject: json ?? [:])
  #expect(try JSONDecoder().decode(NetworkProfile.self, from: data).hotspot == false)
}

@Test func iPhoneRangeAloneProposesNothingUntilFlagged() {
  let discovery = NetworkDiscovery(
    network: homeNetwork, router: phoneRouter, neighbors: [])
  #expect(discovery.looksLikeIPhoneHotspot)
  #expect(discovery.proposedProfile() == nil)
  #expect(discovery.proposedProfile(hotspot: true)?.isSingleDevice == true)
  let other = NetworkDiscovery(network: homeNetwork, router: "172.20.10.16", neighbors: [])
  #expect(!other.looksLikeIPhoneHotspot)
}
