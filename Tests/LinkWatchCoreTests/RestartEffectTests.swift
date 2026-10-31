import Foundation
import Testing

@testable import LinkWatchCore

private let restart = Date(timeIntervalSinceReferenceDate: 800_002_830)

/// Minutes from ten before the restart to fifteen after, with the router at `before` ms until
/// the restart and at `after` ms from the given minute on.
private func minutes(router before: Double, then after: Double, afterFrom first: Int = 2)
  -> [MinuteSummary]
{
  (-10..<15).compactMap { offset in
    guard offset < 0 || offset >= first else { return nil }
    let router = offset < 0 ? before : after
    return MinuteSummary(
      start: Date(timeIntervalSinceReferenceDate: 800_002_820 + Double(offset) * 60),
      ssid: "Home", samples: 30, accessPoint: target(3, 5, loss: 0),
      router: target(router, router + 10, loss: 0),
      internet: target(router + 2, router + 12, loss: 0),
      worstHealth: "healthy")
  }
}

@Test func restartThatFixesTheBridgeSaysItHelped() {
  let effect = RestartEffect(
    time: restart, device: "TP-Link", minutes: minutes(router: 85, then: 4))
  #expect(effect.before.minutes == 9)
  #expect(effect.after.minutes == 10)
  #expect(effect.outcome == .helped)
  #expect(effect.sentence == "Restarting the TP-Link helped: router 85 → 4 ms, internet 87 → 6 ms.")
}

@Test func restartOutcomesCoverWorseUnchangedAndTooEarly() {
  #expect(
    RestartEffect(time: restart, device: "router", minutes: minutes(router: 4, then: 85)).outcome
      == .worse)
  let same = RestartEffect(time: restart, device: "router", minutes: minutes(router: 8, then: 9))
  #expect(same.outcome == .noChange)
  #expect(same.sentence.contains("made no clear difference (AP 3 → 3 ms, router 8 → 9 ms"))
  let early = RestartEffect(
    time: restart, device: "router", minutes: minutes(router: 85, then: 4, afterFrom: 13))
  #expect(early.outcome == .measuring)
  #expect(early.sentence.hasPrefix("Measuring the effect of restarting the router"))
  let unknown = RestartEffect(time: restart, device: "router", minutes: [])
  #expect(unknown.outcome == .noBaseline)
}

@Test func restartLossChangesCount() {
  var lossy = minutes(router: 8, then: 8)
  for index in lossy.indices where lossy[index].start < restart {
    lossy[index].router.loss = 0.4
  }
  let effect = RestartEffect(time: restart, device: "router", minutes: lossy)
  #expect(effect.outcome == .helped)
  #expect(effect.sentence.contains("router loss 40% → 0%"))
}

@MainActor
@Test func controllerRecordsRestartsOfTheLikelyDevice() {
  var bridged = homeProfile
  bridged.bridgeName = "TP-Link powerline adapters"
  let harness = Harness(profiles: [bridged])
  harness.controller.refresh()
  #expect(harness.controller.restartEffect == nil)
  #expect(harness.controller.restarted() == "TP-Link powerline adapters")
  #expect(harness.controller.restarted("  modem \n") == "modem")
  #expect(
    harness.events.saved.filter { $0.kind == .restarted }.map(\.detail) == [
      "TP-Link powerline adapters", "modem",
    ])
  #expect(harness.controller.restartEffect?.outcome == .noBaseline)
  let report = StatusReport(controller: harness.controller, now: harness.clock.now)
  #expect(report.text.contains("Restart:     Nothing was measured before restarting the modem"))
  harness.clock.now += 3600
  #expect(harness.controller.restartEffect == nil)

  var phone = homeProfile
  phone.hotspot = true
  #expect(Harness(profiles: [phone]).controller.defaultRestartDevice == "phone")
  #expect(Harness(profiles: [homeProfile]).controller.defaultRestartDevice == "router")
}

@Test func restartedCommandParses() throws {
  #expect(try HeadlessCommand.parse(["restarted"]) == .restarted(nil, wait: false))
  #expect(
    try HeadlessCommand.parse(["restarted", "TP-Link", "--wait"])
      == .restarted("TP-Link", wait: true))
}

@MainActor
@Test func diagnosisListsRestarts() {
  let harness = Harness()
  let status = StatusReport(controller: harness.controller, now: harness.clock.now)
  let report = DiagnoseReport(
    status: status, appRunning: true, minutes: minutes(router: 85, then: 4),
    profiles: [homeProfile], hours: 1, now: restart.addingTimeInterval(1200),
    primaryInterface: nil,
    events: [AppEvent(time: restart, kind: .restarted, detail: "TP-Link")])
  #expect(report.restarts.map(\.outcome) == [.helped])
  #expect(report.text(bridgeNames: [:]).contains("Restarts\n"))
}
