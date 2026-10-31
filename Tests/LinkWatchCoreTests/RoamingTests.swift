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
  #expect(harness.controller.onRouterRadio)
  #expect(harness.controller.suggestion == nil)
  _ = await harness.cycle()
  #expect(harness.script.requests == ["192.0.2.1@en0"])

  harness.script.requests = []
  harness.environment.network = accessPointRadio
  harness.controller.refresh()
  #expect(!harness.controller.onRouterRadio)
  _ = await harness.cycle()
  #expect(Set(harness.script.requests) == ["192.0.2.2@en0", "192.0.2.1@en0"])
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

  harness.environment.network = accessPointRadio
  harness.controller.refresh()
  guard case .update(let current, let proposed) = harness.controller.suggestion else {
    Issue.record("Expected an offer to add the access point")
    return
  }
  #expect(current.accessPoint.isEmpty)
  #expect(proposed.accessPoint == "192.0.2.2")
  #expect(harness.controller.acceptSuggestion())

  // Back in the living room the saved AP stays, unprobed, and nothing is suggested.
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
