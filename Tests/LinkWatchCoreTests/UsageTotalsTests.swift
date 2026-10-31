import Foundation
import Testing

@testable import LinkWatchCore

@Test func totalsCoverTheLastHourTodayAndTheWeek() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
  let now = try #require(
    calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 1, minute: 30)))
  func minute(_ offset: TimeInterval, received: UInt64?, sent: UInt64?) -> MinuteSummary {
    var summary = MinuteSummary(
      start: now.addingTimeInterval(offset), ssid: "Home", samples: 30,
      accessPoint: target(3, 4, loss: 0), router: target(6, 8, loss: 0), internet: nil,
      worstHealth: "healthy")
    summary.received = received
    summary.sent = sent
    return summary
  }
  let minutes = [
    minute(-3 * 86_400, received: 5_000_000_000, sent: 1_000_000_000),
    minute(-2 * 3600, received: 300_000_000, sent: 30_000_000),
    minute(-600, received: 20_000_000, sent: 2_000_000),
    minute(-300, received: nil, sent: nil),
  ]
  let totals = UsageTotals(
    minutes: minutes, current: TrafficCounters(received: 1_000_000, sent: 500_000), now: now,
    calendar: calendar)
  #expect(totals.lastHour == UsageTotal(received: 21_000_000, sent: 2_500_000))
  #expect(totals.today == UsageTotal(received: 21_000_000, sent: 2_500_000))
  #expect(totals.week == UsageTotal(received: 5_321_000_000, sent: 1_032_500_000))
  #expect(totals.week.summary == "↓ 5.32 GB · ↑ 1.03 GB")
  #expect(UsageTotal(received: 0, sent: 999).summary == "↓ 0 bytes · ↑ 999 bytes")
}

@MainActor
@Test func controllerTotalsIncludeTheMinuteInProgress() async {
  let harness = Harness()
  var received: UInt64 = 0
  harness.environment.counters = TrafficCounters(received: 0, sent: 0)
  for _ in 0..<35 {
    received += 1_000_000
    harness.environment.counters = TrafficCounters(received: received, sent: received / 4)
    _ = await harness.cycle()
  }
  let totals = harness.controller.usageTotals
  #expect(totals.week.received == 34_000_000)
  #expect(totals.week.sent == 8_500_000)
  let status = StatusReport(controller: harness.controller, now: harness.clock.now)
  #expect(status.usageTotals == totals)
  #expect(status.text.contains("Totals:      today"))
  #expect(status.text.contains("7 days ↓ 34 MB · ↑ 8.5 MB"))
}
