import Foundation
import Testing

@testable import LinkWatchCore

private let profile = NetworkProfile(
  ssid: "Test network", accessPoint: "192.0.2.2", router: "192.0.2.1")
private let network = NetworkIdentity(ssid: "Test network", bssid: "test-ap", interface: "en0")

@Test func profileValidationFailsClosed() {
  #expect(profile.isValid)
  for address in ["", "example.com", "127.0.0.1", "224.0.0.1", "1.2.3.256", "01.2.3.4"] {
    #expect(!NetworkProfile.validAddress(address))
  }
  #expect((try? JSONDecoder().decode(NetworkProfile.self, from: Data("{}".utf8))) == nil)
}

@Test func permissionAndSelectionGateMonitoring() {
  var session = MonitoringSession()
  session.select(network: network, profiles: [profile], permitted: false, paused: false)
  #expect(session.profile == nil)
  session.select(network: network, profiles: [], permitted: true, paused: false)
  #expect(session.profile == nil)
  session.select(network: network, profiles: [profile], permitted: true, paused: true)
  #expect(session.profile == nil)
  session.select(network: network, profiles: [profile, profile], permitted: true, paused: false)
  #expect(session.profile == nil)
  session.select(network: network, profiles: [profile], permitted: true, paused: false)
  #expect(session.profile == profile)
}

@Test func roamingAndResetRejectStaleResults() {
  var session = MonitoringSession()
  session.select(network: network, profiles: [profile], permitted: true, paused: false)
  let previous = session.generation
  let pair = ProbePair(
    elapsed: 0, accessPoint: .success(milliseconds: 1), router: .success(milliseconds: 2))
  session.accept(pair, generation: previous)
  #expect(session.window.samples.count == 1)
  let roamed = NetworkIdentity(ssid: network.ssid, bssid: "another-ap", interface: "en0")
  session.select(network: roamed, profiles: [profile], permitted: true, paused: false)
  session.accept(pair, generation: previous)
  #expect(session.window.samples.isEmpty)
  let beforeReset = session.generation
  session.reset()
  session.accept(pair, generation: beforeReset)
  #expect(session.window.samples.isEmpty)
  session.select(network: nil, profiles: [profile], permitted: true, paused: false)
  session.accept(pair, generation: session.generation)
  #expect(session.window.samples.isEmpty)
}
