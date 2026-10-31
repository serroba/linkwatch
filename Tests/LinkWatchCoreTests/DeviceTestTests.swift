import Foundation
import Testing

@testable import LinkWatchCore

private func pairs(router: Double, spikeEvery: Int = 0, accessPoint: Double = 3) -> [ProbePair] {
  (0..<15).map { (index: Int) -> ProbePair in
    let spiking = spikeEvery > 0 && index % spikeEvery == 0
    let routerLatency: Double = spiking ? 400 : router
    return ProbePair(
      elapsed: Double(index) * 2, accessPoint: .success(milliseconds: accessPoint),
      router: .success(milliseconds: routerLatency),
      internet: [.success(milliseconds: routerLatency + 2)])
  }
}

private func result(baseline: [ProbePair], active: [ProbePair], off: [ProbePair])
  -> DeviceTestResult
{
  DeviceTestResult(
    device: "desk",
    phases: [
      DeviceTestPhaseResult(.baseline, pairs: baseline),
      DeviceTestPhaseResult(.deviceOn, pairs: active),
      DeviceTestPhaseResult(.deviceOff, pairs: off),
    ])
}

@Test func deviceTestNamesTheDisturbedLink() {
  let calm = pairs(router: 8)
  #expect(
    result(baseline: calm, active: pairs(router: 8, spikeEvery: 3), off: calm).conclusion
      == "The desk most likely disturbs the link between the access point and the router, such as powerline adapters. It recovered once it was off."
  )
  #expect(
    result(
      baseline: calm, active: pairs(router: 8, spikeEvery: 3), off: pairs(router: 8, spikeEvery: 3)
    )
    .conclusion.hasSuffix("It had not recovered 30 s after turning it off."))
  #expect(
    result(baseline: calm, active: calm, off: calm).conclusion
      == "No clear effect while the desk was on.")
  #expect(
    result(baseline: calm, active: pairs(router: 200, accessPoint: 190), off: calm).conclusion
      .hasPrefix("The desk most likely disturbs the Wi-Fi link"))
  #expect(
    DeviceTestResult(device: "desk", phases: [DeviceTestPhaseResult(.deviceOn, pairs: calm)])
      .conclusion
      == "The test did not complete.")
}

@MainActor
@Test func guidedTestRunsThroughItsPhasesAndRecordsEvents() async throws {
  let harness = Harness()
  _ = await harness.cycle()
  #expect(harness.controller.startDeviceTest("desk"))
  #expect(!harness.controller.startDeviceTest("desk"))
  #expect(harness.controller.deviceTestSecondsLeft(now: harness.clock.now) == 30)
  var cycle = 0
  func run(_ count: Int, spiky: Bool) async {
    for _ in 0..<count {
      cycle += 1
      harness.script.outcomes["192.0.2.1"] =
        spiky && cycle % 3 == 0 ? .success(milliseconds: 400) : .success(milliseconds: 5)
      _ = await harness.cycle()
    }
  }
  await run(16, spiky: false)
  guard case .running(_, .deviceOn, _) = harness.controller.deviceTest else {
    Issue.record("Expected the on phase, got \(harness.controller.deviceTest)")
    return
  }
  let status = StatusReport(controller: harness.controller, now: harness.clock.now)
  #expect(status.deviceTest?.instruction == "Turn the desk on now, or keep it moving.")
  #expect(status.text.contains("Device test: desk, on phase"))
  await run(15, spiky: true)
  await run(15, spiky: false)
  guard case .finished(let outcome) = harness.controller.deviceTest else {
    Issue.record("Expected a finished test, got \(harness.controller.deviceTest)")
    return
  }
  #expect(
    outcome.conclusion.hasPrefix(
      "The desk most likely disturbs the link between the access point and the router"))
  #expect(outcome.phases.allSatisfy { $0.samples >= DeviceTestState.minimumSamples })
  let details = harness.events.saved.filter { $0.kind == .deviceTest }.compactMap(\.detail)
  #expect(details.prefix(3) == ["desk: started", "desk: on", "desk: off"])
  #expect(details.last?.hasPrefix("desk: The desk most likely disturbs") == true)
  harness.controller.dismissDeviceTest()
  #expect(harness.controller.deviceTest == .idle)
}

@MainActor
@Test func deviceTestNeedsMonitoringAndStopsWithIt() async {
  let unmonitored = Harness(profiles: nil)
  #expect(!unmonitored.controller.startDeviceTest("desk"))
  #expect(
    unmonitored.controller.deviceTest
      == .cancelled("Start monitoring a network before testing a device."))
  let harness = Harness()
  _ = await harness.cycle()
  #expect(harness.controller.startDeviceTest("heater"))
  harness.controller.paused = true
  #expect(
    harness.controller.deviceTest
      == .cancelled("Monitoring stopped or the network changed, so the test was cancelled."))
  #expect(harness.events.saved.last { $0.kind == .deviceTest }?.detail == "heater: cancelled")
}

@Test func testDeviceCommandParses() throws {
  #expect(
    try HeadlessCommand.parse(["test-device", "standing", "desk"]) == .testDevice("standing desk"))
  #expect(throws: HeadlessCommand.UsageError.self) { try HeadlessCommand.parse(["test-device"]) }
}

@Test func deviceTestInstructionsAndIncompleteResults() {
  #expect(
    DeviceTestPhase.baseline.instruction(device: "desk")
      == "Leave the desk off and use the Mac as usual.")
  #expect(DeviceTestPhase.deviceOff.instruction(device: "desk") == "Turn the desk off now.")
  #expect(DeviceTestResult(device: "desk", phases: []).conclusion == "The test did not complete.")
}

@MainActor
@Test func deviceTestReportsEachStateForStatus() async throws {
  let harness = Harness()
  #expect(DeviceTestReport(controller: harness.controller, now: harness.clock.now) == nil)
  _ = await harness.cycle()
  #expect(harness.controller.startDeviceTest("heater"))
  let running = try #require(
    DeviceTestReport(controller: harness.controller, now: harness.clock.now))
  #expect(running.state == "running")
  #expect(running.summary.hasPrefix("heater, baseline phase, "))
  let json = String(bytes: try JSONEncoder().encode(running), encoding: .utf8) ?? ""
  #expect(json.contains("\"result\":null"))
  harness.controller.paused = true
  let cancelled = try #require(
    DeviceTestReport(controller: harness.controller, now: harness.clock.now))
  #expect(cancelled.state == "cancelled")
  #expect(cancelled.summary.hasPrefix("Monitoring stopped"))
}
