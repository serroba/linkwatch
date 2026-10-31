import Foundation
import Testing

@testable import LinkWatchCore

private func pair(_ elapsed: Double, internet: [ProbeOutcome]) -> ProbePair {
  ProbePair(
    elapsed: elapsed, accessPoint: .success(milliseconds: 2), router: .success(milliseconds: 4),
    internet: internet)
}

@Test func bestReferenceNeedsEveryProviderToFail() {
  #expect(pair(0, internet: []).internetBest == nil)
  #expect(
    pair(0, internet: [.success(milliseconds: 30), .success(milliseconds: 12)]).internetBest
      == .success(milliseconds: 12))
  #expect(
    pair(0, internet: [.timeout, .success(milliseconds: 40)]).internetBest
      == .success(milliseconds: 40))
  #expect(pair(0, internet: [.timeout, .failure]).internetBest == .timeout)
  #expect(pair(0, internet: [.cancelled, .timeout]).internetBest == .cancelled)
}

@Test func windowTracksInternetMediansAndLoss() {
  var window = MonitoringWindow()
  window.append(
    ProbePair(elapsed: 0, accessPoint: .success(milliseconds: 2), router: .success(milliseconds: 4))
  )
  #expect(window.internetLoss == nil)
  #expect(window.internetMedian == nil)
  window.append(pair(2, internet: [.success(milliseconds: 20), .success(milliseconds: 30)]))
  window.append(pair(4, internet: [.timeout, .success(milliseconds: 50)]))
  window.append(pair(6, internet: [.timeout, .timeout]))
  #expect(window.internetMedian == 35)
  #expect(window.internetLoss == 1.0 / 3.0)
  #expect(window.referenceMedian(0) == 20)
  #expect(window.referenceMedian(1) == 40)
  #expect(window.referenceMedian(2) == nil)
  window.append(pair(8, internet: [.cancelled, .timeout]))
  #expect(window.samples.count == 4)
}

@Test func profilesSavedBeforeReferencesDecodeWithThemOn() throws {
  let legacy = """
    {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","ssid":"Home","accessPoint":"192.0.2.2",
    "router":"192.0.2.1","thresholds":{"difference":20,"recoveryDifference":10,"slow":30,
    "recoverySlow":20,"sustainedSeconds":10,"recoverySeconds":6}}
    """
  let profile = try JSONDecoder().decode(NetworkProfile.self, from: Data(legacy.utf8))
  #expect(profile.internetReferences)
  var off = profile
  off.internetReferences = false
  #expect(try JSONDecoder().decode(NetworkProfile.self, from: JSONEncoder().encode(off)) == off)
}

@MainActor
@Test func controllerProbesReferencesOnlyWhenTheProfileAllows() async {
  var enabled = homeProfile
  enabled.internetReferences = true
  let harness = Harness(profiles: [enabled])
  harness.script.outcomes["1.1.1.1"] = .timeout
  harness.script.outcomes["8.8.8.8"] = .success(milliseconds: 18)
  for _ in 0..<31 { _ = await harness.cycle() }
  #expect(harness.script.requests.filter { $0 == "1.1.1.1@en0" }.count == 31)
  #expect(harness.script.requests.filter { $0 == "8.8.8.8@en0" }.count == 31)
  let pair = harness.controller.session.window.samples.last
  #expect(pair?.internet == [.timeout, .success(milliseconds: 18)])
  #expect(harness.controller.session.window.internetMedian == 18)
  #expect(harness.history.saved.first?.internet?.median == 18)
  #expect(harness.history.saved.first?.internet?.loss == 0)

  let report = StatusReport(controller: harness.controller, now: harness.clock.now)
  #expect(report.latency.internet == 18)
  #expect(report.latency.references.map(\.median) == [nil, 18])
  #expect(report.text.contains("Internet:    Cloudflare — · Google 18.0 ms · best of both lost 0%"))

  let disabled = Harness()
  _ = await disabled.cycle()
  #expect(disabled.script.requests.count == 2)
  let local = StatusReport(controller: disabled.controller, now: disabled.clock.now)
  #expect(local.latency.references.isEmpty)
  #expect(local.text.contains("Internet:    not probed for this network"))
}

@Test func internetSettingParses() throws {
  let cases: [String: ProfileUpdate.Switch] = ["on": .enabled, "off": .disabled]
  for (value, setting) in cases {
    let command = try HeadlessCommand.parse([
      "profile", "set", "--ssid", "Home", "--internet", value,
    ])
    guard case .setProfile(let update) = command else {
      Issue.record("Expected profile set")
      return
    }
    #expect(update.internetReferences == setting)
    let existing = NetworkProfile(ssid: "Home", accessPoint: "192.0.2.2", router: "192.0.2.1")
    #expect(update.applied(to: existing)?.internetReferences == (setting == .enabled))
  }
  #expect(throws: HeadlessCommand.UsageError.self) {
    try HeadlessCommand.parse(["profile", "set", "--ssid", "Home", "--internet", "maybe"])
  }
}
