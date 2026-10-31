import Foundation
import Testing

@testable import LinkWatchCore

private func evidence(_ accessPoint: Double?, _ router: Double?, internet: Double?? = nil)
  -> LinkEvidence
{
  func target(_ median: Double?) -> TargetEvidence {
    TargetEvidence(median: median, loss: median == nil ? 1 : 0)
  }
  return LinkEvidence(
    accessPoint: target(accessPoint), router: target(router), internet: internet.map(target))
}

private struct Case {
  let evidence: LinkEvidence
  let verdict: Verdict
}

@Test func verdictsFollowTheDecisionTable() {
  let cases = [
    Case(evidence: evidence(2, 6, internet: 10), verdict: .allClear),
    Case(evidence: evidence(2, 6), verdict: .allClear),
    Case(evidence: evidence(2, 60, internet: 70), verdict: .bridge),
    Case(evidence: evidence(2, nil, internet: .some(nil)), verdict: .bridge),
    Case(evidence: evidence(2, nil), verdict: .routerUnreachable),
    Case(evidence: evidence(2, nil, internet: 12), verdict: .routerSilent),
    Case(evidence: evidence(45, 50, internet: 60), verdict: .accessPoint),
    Case(evidence: evidence(nil, 6, internet: 10), verdict: .accessPoint),
    Case(evidence: evidence(2, 6, internet: 150), verdict: .internet),
    Case(evidence: evidence(2, 6, internet: .some(nil)), verdict: .internet),
    Case(evidence: evidence(2, 6, internet: 90), verdict: .allClear),
  ]
  for test in cases {
    #expect(Verdict(test.evidence, thresholds: Thresholds()) == test.verdict)
  }
  var lossy = evidence(2, 6, internet: 10)
  lossy.router.loss = 0.6
  #expect(Verdict(lossy, thresholds: Thresholds()) == .routerSilent)
  lossy.router.loss = 0.4
  #expect(Verdict(lossy, thresholds: Thresholds()) == .allClear)
}

@Test func adviceNamesTheBridgeWhenKnown() {
  #expect(Verdict.allClear.action(bridge: nil) == nil)
  #expect(
    Verdict.bridge.action(bridge: "TP-Link powerline adapters")
      == "Restart the TP-Link powerline adapters.")
  #expect(
    Verdict.bridge.action(bridge: nil)
      == "Restart the device linking the access point to the router, such as powerline adapters.")
  #expect(
    Verdict.bridge.headline(bridge: "TP-Link powerline adapters")
      == "The connection between the access point and the router (TP-Link powerline adapters) is struggling."
  )
  #expect(Verdict.routerSilent.action(bridge: nil)?.contains("Local Network") == true)
  #expect(
    Verdict.routerUnreachable.action(bridge: "TP-Link")?.hasPrefix(
      "If the internet is not working either, restart the TP-Link.") == true)
  for verdict in [Verdict.accessPoint, .internet, .routerUnreachable] {
    #expect(verdict.isProblem)
    #expect(verdict.action(bridge: nil) != nil)
  }
}

@Test func storedMinutesClassifyLikeLiveEvidence() {
  let minute = MinuteSummary(
    start: Date(timeIntervalSinceReferenceDate: 800_000_040), ssid: "Home", samples: 30,
    accessPoint: target(3, 6, loss: 0), router: target(nil, nil, loss: 1),
    internet: target(11, 14, loss: 0), worstHealth: "unreachable")
  #expect(Verdict(LinkEvidence(minute), thresholds: Thresholds()) == .routerSilent)
  var noReferences = minute
  noReferences.internet = nil
  #expect(Verdict(LinkEvidence(noReferences), thresholds: Thresholds()) == .routerUnreachable)
}

@Test func bridgeNamesDecodeValidateAndParse() throws {
  var profile = NetworkProfile(
    ssid: "Home", accessPoint: "192.0.2.2", router: "192.0.2.1", bridgeName: "TP-Link")
  #expect(profile.isValid)
  #expect(
    try JSONDecoder().decode(NetworkProfile.self, from: JSONEncoder().encode(profile)) == profile)
  profile.bridgeName = "  "
  #expect(!profile.isValid)
  profile.bridgeName = String(repeating: "x", count: 61)
  #expect(!profile.isValid)

  guard
    case .setProfile(let named) = try HeadlessCommand.parse([
      "profile", "set", "--ssid", "Home", "--bridge", "TP-Link powerline adapters",
    ]),
    case .setProfile(let cleared) = try HeadlessCommand.parse([
      "profile", "set", "--ssid", "Home", "--no-bridge",
    ])
  else {
    Issue.record("Expected profile set commands")
    return
  }
  profile.bridgeName = "Old"
  #expect(named.applied(to: profile)?.bridgeName == "TP-Link powerline adapters")
  #expect(cleared.applied(to: profile)?.bridgeName == nil)
}

@MainActor
@Test func liveVerdictWaitsForTheAlertAndRecoveryTimes() async {
  var named = homeProfile
  named.bridgeName = "TP-Link powerline adapters"
  let harness = Harness(profiles: [named])
  _ = await harness.cycle()
  #expect(harness.controller.verdict == .allClear)
  harness.script.outcomes["192.0.2.1"] = .success(milliseconds: 80)
  for _ in 0..<5 { _ = await harness.cycle() }
  #expect(harness.controller.verdict == .allClear)
  for _ in 0..<3 { _ = await harness.cycle() }
  #expect(harness.controller.verdict == .bridge)
  let report = StatusReport(controller: harness.controller, now: harness.clock.now)
  #expect(report.verdict == .bridge)
  #expect(report.action == "Restart the TP-Link powerline adapters.")
  #expect(
    report.text.hasPrefix(
      "Verdict:     The connection between the access point and the router (TP-Link powerline adapters) is struggling. → Restart the TP-Link powerline adapters."
    ))

  harness.script.outcomes["192.0.2.1"] = nil
  for _ in 0..<5 { _ = await harness.cycle() }
  #expect(harness.controller.verdict == .bridge)
  for _ in 0..<3 { _ = await harness.cycle() }
  #expect(harness.controller.verdict == .allClear)
  harness.script.outcomes["192.0.2.1"] = .success(milliseconds: 80)
  for _ in 0..<8 { _ = await harness.cycle() }
  harness.controller.networkChanged()
  #expect(harness.controller.verdict == .allClear)
}

@MainActor
@Test func pausingClearsTheVerdict() async {
  let harness = Harness()
  harness.script.outcomes["192.0.2.1"] = .success(milliseconds: 80)
  for _ in 0..<8 { _ = await harness.cycle() }
  #expect(harness.controller.verdict == .bridge)
  harness.controller.paused = true
  #expect(harness.controller.verdict == .allClear)
}
