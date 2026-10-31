import Foundation
import Testing

@testable import LinkWatchCore

private let origin = Date(timeIntervalSinceReferenceDate: 800_002_800)

/// An hour of quiet minutes, with router spikes in the minutes listed.
private func hour(spikesAt spiky: Set<Int>, accessPointSpikesAt wifi: Set<Int> = [])
  -> [MinuteSummary]
{
  (0..<60).map { index in
    MinuteSummary(
      start: origin.addingTimeInterval(Double(index) * 60), ssid: "Home", samples: 30,
      accessPoint: target(3, wifi.contains(index) ? 300 : 5, loss: 0),
      router: target(8, spiky.contains(index) ? 380 : 18, loss: 0),
      internet: target(10, spiky.contains(index) ? 390 : 20, loss: 0), worstHealth: "healthy")
  }
}

private func marks(_ label: String, at minutes: [Int]) -> [AppEvent] {
  minutes.map {
    AppEvent(time: origin.addingTimeInterval(Double($0) * 60 + 20), kind: .marked, detail: label)
  }
}

@Test func repeatedMarksImplicateTheLinkTheyDisturb() throws {
  let effects = MarkEffect.effects(
    events: marks("desk moved", at: [5, 20, 41]) + marks("Desk moved", at: [50]),
    minutes: hour(spikesAt: [5, 6, 20, 21, 41, 42, 50]), profiles: [])
  let desk = try #require(effects.first)
  #expect(desk.occurrences == 4)
  #expect(desk.after.minutes == 8)
  #expect(desk.after.routerP95 == 380)
  #expect(desk.baseline.routerP95 == 18)
  #expect(desk.after.accessPointP95 == 5)
  #expect(desk.after.problemShare == 7.0 / 8)
  #expect(
    desk.conclusion.hasPrefix(
      "Most likely affects the link between the access point and the router"))
}

@Test func marksWithoutAnEffectOrTooFewSaySo() {
  let quiet = MarkEffect.effects(
    events: marks("kettle", at: [5, 20, 41]), minutes: hour(spikesAt: []), profiles: [])
  #expect(quiet.first?.conclusion == "No clear effect on any link.")
  let few = MarkEffect.effects(
    events: marks("desk", at: [5]), minutes: hour(spikesAt: [5]), profiles: [])
  #expect(few.first?.conclusion.hasPrefix("Not enough marks yet") == true)
  let wifi = MarkEffect.effects(
    events: marks("microwave", at: [10, 30, 50]),
    minutes: hour(spikesAt: [], accessPointSpikesAt: [10, 11, 30, 31, 50, 51]), profiles: [])
  #expect(wifi.first?.conclusion == "Most likely affects the Wi-Fi link to the access point.")
  #expect(
    MarkEffect.effects(events: marks("away", at: [200]), minutes: hour(spikesAt: []), profiles: [])
      .isEmpty)
}

@MainActor
@Test func diagnosisReportsMarkedActivities() {
  let harness = Harness()
  let status = StatusReport(controller: harness.controller, now: harness.clock.now)
  let report = DiagnoseReport(
    status: status, appRunning: true, minutes: hour(spikesAt: [5, 6, 20, 21, 41, 42]),
    profiles: [homeProfile], hours: 1, now: origin.addingTimeInterval(3600), primaryInterface: nil,
    events: marks("desk moved", at: [5, 20, 41]))
  #expect(report.markEffects.count == 1)
  let text = report.text(bridgeNames: [:])
  #expect(text.contains("Marked activities"))
  #expect(
    text.contains(
      "\"desk moved\" × 3: Most likely affects the link between the access point and the router"))
  #expect(text.contains("router 380 ms → 18 ms"))
}
