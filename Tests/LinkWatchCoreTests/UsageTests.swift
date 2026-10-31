import Foundation
import Testing

@testable import LinkWatchCore

@MainActor
@Test func usageRatesAndMinuteBytesFollowTheCounters() async {
  let harness = Harness()
  harness.environment.counters = TrafficCounters(received: 1_000_000, sent: 500_000)
  _ = await harness.cycle()
  #expect(harness.controller.usage == nil)
  #expect(
    StatusReport(controller: harness.controller, now: harness.clock.now).text.contains(
      "Usage:       measuring"))

  harness.environment.counters = TrafficCounters(received: 1_500_000, sent: 750_000)
  _ = await harness.cycle()
  #expect(
    harness.controller.usage
      == Usage(downloadBitsPerSecond: 2_000_000, uploadBitsPerSecond: 1_000_000))
  let report = StatusReport(controller: harness.controller, now: harness.clock.now)
  #expect(report.downloadBitsPerSecond == 2_000_000)
  #expect(report.text.contains("Usage:       ↓ 2.0 Mbit/s · ↑ 1.0 Mbit/s"))

  // A counter that goes backwards starts a new baseline instead of reporting a spike.
  harness.environment.counters = TrafficCounters(received: 10, sent: 10)
  _ = await harness.cycle()
  #expect(harness.controller.usage == nil)
  harness.environment.counters = TrafficCounters(received: 2_010, sent: 1_010)
  _ = await harness.cycle()
  #expect(
    harness.controller.usage == Usage(downloadBitsPerSecond: 8_000, uploadBitsPerSecond: 4_000))

  harness.controller.paused = true
  #expect(harness.controller.usage == nil)
  #expect(harness.history.saved.last?.received == 502_000)
  #expect(harness.history.saved.last?.sent == 251_000)
}

@MainActor
@Test func missingCountersLeaveUsageUnknown() async {
  let harness = Harness()
  for _ in 0..<3 { _ = await harness.cycle() }
  #expect(harness.controller.usage == nil)
  harness.controller.paused = true
  #expect(harness.history.saved.last?.received == nil)
}

@Test func ratesUseFamiliarUnits() {
  #expect(StatusReport.rate(950) == "950 bit/s")
  #expect(StatusReport.rate(64_000) == "64 kbit/s")
  #expect(StatusReport.rate(12_340_000) == "12.3 Mbit/s")
}

@Test func busyMeansHeavyRelativeToTheNetworksPeak() {
  #expect(!Load.isBusy(900_000, peak: 0))
  #expect(Load.isBusy(12_000_000, peak: 12_000_000))
  #expect(Load.isBusy(6_000_000, peak: 12_000_000))
  #expect(!Load.isBusy(5_000_000, peak: 12_000_000))
}

@Test func slowLinksUnderLoadAreBusyButLossIsNot() {
  func evidence(_ router: Double?, internet: Double, busy: Bool) -> LinkEvidence {
    LinkEvidence(
      accessPoint: TargetEvidence(median: 3, loss: 0),
      router: TargetEvidence(median: router, loss: router == nil ? 1 : 0),
      internet: TargetEvidence(median: internet, loss: 0), busy: busy)
  }
  #expect(Verdict(evidence(42, internet: 42, busy: true), thresholds: Thresholds()) == .busy)
  #expect(Verdict(evidence(42, internet: 42, busy: false), thresholds: Thresholds()) == .bridge)
  #expect(Verdict(evidence(6, internet: 300, busy: true), thresholds: Thresholds()) == .busy)
  #expect(
    Verdict(evidence(nil, internet: 12, busy: true), thresholds: Thresholds()) == .routerSilent)
  var slowAccessPoint = evidence(50, internet: 60, busy: true)
  slowAccessPoint.accessPoint.median = 45
  #expect(Verdict(slowAccessPoint, thresholds: Thresholds()) == .busy)
  #expect(Verdict.busy.action(bridge: "TP-Link")?.hasPrefix("Nothing is broken") == true)
}

@Test func minuteRatesUseTheFasterDirection() {
  var minute = MinuteSummary(
    start: Date(timeIntervalSinceReferenceDate: 800_000_040), ssid: "Home", samples: 30,
    accessPoint: target(3, 4, loss: 0), router: target(42, 60, loss: 0),
    internet: target(43, 70, loss: 0), worstHealth: "routerSlower")
  #expect(minute.bitsPerSecond == nil)
  #expect(LinkEvidence(minute, peakBitsPerSecond: 90_000_000).busy == false)
  minute.received = 90_000_000
  minute.sent = 1_000_000
  #expect(minute.bitsPerSecond == 12_000_000)
  #expect(
    Verdict(LinkEvidence(minute, peakBitsPerSecond: 12_000_000), thresholds: Thresholds()) == .busy)
  #expect(
    Verdict(LinkEvidence(minute, peakBitsPerSecond: 40_000_000), thresholds: Thresholds())
      == .bridge)
}

@MainActor
@Test func heavyDownloadKeepsTheVerdictOffTheBridge() async {
  let harness = Harness()
  var received: UInt64 = 0
  harness.environment.counters = TrafficCounters(received: received, sent: 0)
  _ = await harness.cycle()
  harness.script.outcomes["192.0.2.1"] = .success(milliseconds: 42)
  for _ in 0..<8 {
    received += 3_000_000
    harness.environment.counters = TrafficCounters(received: received, sent: 0)
    _ = await harness.cycle()
  }
  #expect(harness.controller.verdict == .busy)
  // Once the transfer stops, recent rates drain over five cycles, then the bridge verdict
  // must hold for the 10 s alert time.
  for _ in 0..<8 {
    harness.environment.counters = TrafficCounters(received: received, sent: 0)
    _ = await harness.cycle()
  }
  #expect(harness.controller.verdict == .busy)
  for _ in 0..<4 {
    harness.environment.counters = TrafficCounters(received: received, sent: 0)
    _ = await harness.cycle()
  }
  #expect(harness.controller.verdict == .bridge)
}
