import Testing

@testable import LinkWatchCore

private let network = NetworkIdentity(ssid: "Home", bssid: "02:00:5e:00:53:13", interface: "en0")

private func neighbor(_ address: String, _ hardware: String, on interface: String = "en0")
  -> NeighborEntry
{
  NeighborEntry(address: address, hardwareAddress: hardware, interface: interface)
}

@Test func radioAddressMatching() {
  #expect(HardwareAddress.isRadio("00:00:5e:00:53:10", of: "00:00:5e:00:53:10"))
  #expect(HardwareAddress.isRadio("02:00:5e:00:53:10", of: "00:00:5e:00:53:10"))
  #expect(HardwareAddress.isRadio("00:00:5e:00:53:17", of: "00:00:5e:00:53:10"))
  #expect(HardwareAddress.isRadio("0:0:5e:0:53:10", of: "00:00:5e:00:53:10"))
  #expect(!HardwareAddress.isRadio("00:00:5e:00:53:18", of: "00:00:5e:00:53:10"))
  #expect(!HardwareAddress.isRadio("00:00:5f:00:53:10", of: "00:00:5e:00:53:10"))
  #expect(!HardwareAddress.isRadio("00:00:00:00:00:00", of: "00:00:00:00:00:00"))
  #expect(!HardwareAddress.isRadio("00:00:5e:00:53", of: "00:00:5e:00:53:10"))
  #expect(!HardwareAddress.isRadio("00:00:5e:00:53:1g", of: "00:00:5e:00:53:10"))
}

@Test func separateAccessPointIsProposed() {
  let discovery = NetworkDiscovery(
    network: network, router: "192.0.2.1",
    neighbors: [
      neighbor("192.0.2.1", "00:00:5e:00:53:01"), neighbor("192.0.2.2", "00:00:5e:00:53:10"),
    ])
  #expect(discovery.accessPoint == .found("192.0.2.2"))
  #expect(discovery.proposedProfile()?.accessPoint == "192.0.2.2")
  #expect(discovery.proposedProfile()?.router == "192.0.2.1")
  #expect(discovery.proposedProfile()?.ssid == "Home")
}

@Test func accessPointDiscoveryFailsClosed() {
  let router = neighbor("192.0.2.1", "00:00:5e:00:53:10")
  #expect(
    NetworkDiscovery(network: network, router: "192.0.2.1", neighbors: [router]).accessPoint
      == .router)
  let ambiguous = NetworkDiscovery(
    network: network, router: "192.0.2.1",
    neighbors: [
      neighbor("192.0.2.2", "00:00:5e:00:53:10"), neighbor("192.0.2.3", "00:00:5e:00:53:11"),
    ])
  #expect(ambiguous.accessPoint == .unknown)
  #expect(ambiguous.proposedProfile() == nil)
  let otherInterface = NetworkDiscovery(
    network: network, router: "192.0.2.1",
    neighbors: [neighbor("192.0.2.2", "00:00:5e:00:53:10", on: "en5")])
  #expect(otherInterface.accessPoint == .unknown)
  let noRouter = NetworkDiscovery(
    network: network, router: "not-an-address",
    neighbors: [neighbor("192.0.2.2", "00:00:5e:00:53:10")])
  #expect(noRouter.router == nil)
  #expect(noRouter.accessPoint == .found("192.0.2.2"))
  #expect(noRouter.proposedProfile() == nil)
}

@Test func updatingKeepsProfileIdentityAndThresholds() {
  var thresholds = Thresholds()
  thresholds.difference = 40
  let profile = NetworkProfile(
    ssid: "Home", accessPoint: "192.0.2.2", router: "192.0.2.1", thresholds: thresholds)
  let discovery = NetworkDiscovery(
    network: network, router: "192.0.2.9",
    neighbors: [neighbor("192.0.2.8", "00:00:5e:00:53:10")])
  let updated = discovery.updating(profile)
  #expect(updated.id == profile.id)
  #expect(updated.thresholds == thresholds)
  #expect(updated.router == "192.0.2.9")
  #expect(updated.accessPoint == "192.0.2.8")
  let unknownAccessPoint = NetworkDiscovery(network: network, router: "192.0.2.1", neighbors: [])
  #expect(unknownAccessPoint.updating(profile) == profile)
}
