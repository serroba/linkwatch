import Foundation
import Testing

@testable import LinkWatchCore

private let home = NetworkIdentity(ssid: "Home", bssid: "00:00:5e:00:53:01", interface: "en0")
private let profile = NetworkProfile(ssid: "Home", accessPoint: "192.0.2.2", router: "192.0.2.1")

@MainActor
private final class FakeEnvironment: NetworkEnvironment {
  var isPermitted = true
  var network: NetworkIdentity? = home

  func currentNetwork() -> NetworkIdentity? { isPermitted ? network : nil }
}

private struct StoreFailure: Error {}

private final class FakeStore: ProfileStore {
  var saved: [NetworkProfile]?
  var failsToLoad = false
  var failsToSave = false

  init(_ saved: [NetworkProfile]? = nil) { self.saved = saved }

  func load() throws -> [NetworkProfile]? {
    if failsToLoad { throw StoreFailure() }
    return saved
  }

  func save(_ profiles: [NetworkProfile]) throws {
    if failsToSave { throw StoreFailure() }
    saved = profiles
  }
}

/// Records probes and runs an optional hook on the main actor before replying.
@MainActor
private final class ProbeScript {
  var requests: [String] = []
  var outcomes: [String: ProbeOutcome] = [:]
  var beforeReply: (() -> Void)?

  func reply(address: String, interface: String) -> ProbeOutcome {
    requests.append("\(address)@\(interface)")
    beforeReply?()
    return outcomes[address] ?? .success(milliseconds: 5)
  }
}

private struct FakeProbe: LatencyProbe {
  let script: ProbeScript

  func measure(address: String, interface: String) async -> ProbeOutcome {
    await script.reply(address: address, interface: interface)
  }
}

@MainActor
private final class Clock {
  var now: TimeInterval = 100
}

@MainActor
private struct Harness {
  let environment = FakeEnvironment()
  let script = ProbeScript()
  let clock = Clock()
  let store: FakeStore
  let controller: MonitorController

  init(profiles: [NetworkProfile]? = [profile], store: FakeStore? = nil) {
    let store = store ?? FakeStore(profiles)
    let clock = clock
    self.store = store
    controller = MonitorController(
      environment: environment, probe: FakeProbe(script: script), store: store,
      uptime: { clock.now })
  }

  func cycle(advancing seconds: TimeInterval = 2) async -> TimeInterval {
    let delay = await controller.cycle()
    clock.now += seconds
    return delay
  }
}

@MainActor
@Test func unselectedNetworkSendsNoProbes() async {
  let harness = Harness(profiles: nil)
  _ = await harness.cycle()
  #expect(harness.script.requests.isEmpty)
  #expect(harness.controller.displayState == .idle)
  #expect(harness.controller.reason == "This Wi-Fi network is not selected for monitoring")
}

@MainActor
@Test func selectedNetworkProbesBothTargetsOnWiFiInterface() async {
  let harness = Harness()
  _ = await harness.cycle()
  #expect(Set(harness.script.requests) == ["192.0.2.2@en0", "192.0.2.1@en0"])
  #expect(harness.controller.session.window.samples.count == 1)
  #expect(harness.controller.accessPointLatency == 5)
  #expect(harness.controller.displayState == .healthy)
}

@MainActor
@Test func missingPermissionSendsNoProbes() async {
  let harness = Harness()
  harness.environment.isPermitted = false
  _ = await harness.cycle()
  #expect(harness.script.requests.isEmpty)
  #expect(harness.controller.network == nil)
  #expect(harness.controller.reason.hasPrefix("Location permission"))
}

@MainActor
@Test func pauseAndSleepClearHistoryAndStopProbes() async {
  let harness = Harness()
  _ = await harness.cycle()
  harness.controller.paused = true
  #expect(harness.controller.session.window.samples.isEmpty)
  _ = await harness.cycle()
  #expect(harness.script.requests.count == 2)
  #expect(harness.controller.reason == "Paused manually")

  harness.controller.paused = false
  harness.controller.setSleeping(true)
  _ = await harness.cycle()
  #expect(harness.script.requests.count == 2)
  #expect(harness.controller.reason == "Paused while Mac sleeps")
  harness.controller.setSleeping(false)
  _ = await harness.cycle()
  #expect(harness.script.requests.count == 4)
}

@MainActor
@Test func networkChangeDuringProbeDiscardsResult() async {
  let harness = Harness()
  harness.script.beforeReply = { harness.controller.networkChanged() }
  _ = await harness.cycle()
  #expect(harness.script.requests.count == 2)
  #expect(harness.controller.session.window.samples.isEmpty)
}

@MainActor
@Test func roamingToAnotherAccessPointResetsSession() async {
  let harness = Harness()
  _ = await harness.cycle()
  let generation = harness.controller.session.generation
  harness.environment.network = NetworkIdentity(
    ssid: "Home", bssid: "00:00:5e:00:53:02", interface: "en0")
  harness.controller.refresh()
  #expect(harness.controller.session.generation != generation)
  #expect(harness.controller.session.window.samples.isEmpty)
  #expect(harness.controller.network?.bssid == "00:00:5e:00:53:02")
}

@MainActor
@Test func failedLatestProbeIsUnavailableNotZero() async {
  let harness = Harness()
  _ = await harness.cycle()
  harness.script.outcomes["192.0.2.1"] = .timeout
  _ = await harness.cycle()
  #expect(harness.controller.routerLatency == nil)
  #expect(harness.controller.accessPointLatency == 5)
  #expect(harness.controller.displayState == .unreachable)
  #expect(harness.controller.reason == "No reply from router")
}

@MainActor
@Test func alertStartTimeFollowsHealthChanges() async {
  let harness = Harness()
  harness.script.outcomes["192.0.2.1"] = .success(milliseconds: 50)
  for _ in 0..<6 { _ = await harness.cycle() }
  #expect(harness.controller.displayState == .routerSlower)
  #expect(harness.controller.healthSince == 110)
}

@MainActor
@Test func cycleKeepsTwoSecondCadence() async {
  let harness = Harness()
  harness.script.beforeReply = { harness.clock.now += 0.75 }
  #expect(await harness.cycle() == 0.5)
  harness.script.beforeReply = { harness.clock.now += 5 }
  #expect(await harness.cycle() == 0.05)
}

@MainActor
@Test func unreadableOrInconsistentStoredProfilesFailClosed() async {
  let unreadable = FakeStore([profile])
  unreadable.failsToLoad = true
  let duplicate = FakeStore([
    profile, NetworkProfile(ssid: "Home", accessPoint: "192.0.2.3", router: "192.0.2.1"),
  ])
  for store in [unreadable, duplicate] {
    let harness = Harness(store: store)
    _ = await harness.cycle()
    #expect(harness.controller.profiles.isEmpty)
    #expect(harness.controller.storageError != nil)
    #expect(harness.script.requests.isEmpty)
  }
}

@MainActor
@Test func savingValidatesReplacesAndReportsFailures() {
  let harness = Harness(profiles: nil)
  #expect(!harness.controller.save(NetworkProfile(ssid: "Home", accessPoint: "1.1.1", router: "")))
  #expect(harness.controller.save(profile))
  let replacement = NetworkProfile(ssid: "Home", accessPoint: "192.0.2.3", router: "192.0.2.1")
  #expect(harness.controller.save(replacement))
  #expect(harness.controller.profiles == [replacement])
  #expect(harness.store.saved == [replacement])

  harness.store.failsToSave = true
  #expect(
    !harness.controller.save(
      NetworkProfile(ssid: "Cafe", accessPoint: "192.0.2.4", router: "192.0.2.5")))
  #expect(harness.controller.profiles == [replacement])
  #expect(harness.controller.storageError != nil)
  harness.controller.remove(replacement)
  #expect(harness.controller.profiles == [replacement])

  harness.store.failsToSave = false
  harness.controller.remove(replacement)
  #expect(harness.controller.profiles.isEmpty)
  #expect(harness.controller.storageError == nil)
}
