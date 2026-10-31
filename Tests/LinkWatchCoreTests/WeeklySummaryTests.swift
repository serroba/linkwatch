import Foundation
import Testing

@testable import LinkWatchCore

/// Midnight UTC, so hours of the day are predictable.
private let firstDay = Date(timeIntervalSinceReferenceDate: 799_977_600)
private let now = firstDay.addingTimeInterval(7 * 86_400)

private var utc: Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
  return calendar
}

private func minute(
  _ start: Date, router: Double = 8, internet: Double = 10, bytes: UInt64 = 1_000
) -> MinuteSummary {
  var summary = MinuteSummary(
    start: start, ssid: "Home", samples: 30, accessPoint: target(3, 5, loss: 0),
    router: target(router, router + 10, loss: 0),
    internet: target(internet, internet + 10, loss: 0), worstHealth: "healthy")
  summary.received = bytes
  summary.sent = 0
  return summary
}

/// Evenings 18:00–20:00 on days one to three with the bridge failing 19:00–19:09, and a
/// morning of heavy downloads with bufferbloat on day four.
private func week() -> [MinuteSummary] {
  var minutes: [MinuteSummary] = []
  for day in 1...3 {
    let evening = firstDay.addingTimeInterval(Double(day) * 86_400 + 18 * 3600)
    for offset in 0..<120 {
      let failing = (60..<70).contains(offset)
      minutes.append(
        minute(
          evening.addingTimeInterval(Double(offset) * 60), router: failing ? 200 : 8,
          internet: failing ? 210 : 10))
    }
  }
  let morning = firstDay.addingTimeInterval(4 * 86_400 + 10 * 3600)
  for offset in 0..<45 {
    let heavy = offset < 15
    minutes.append(
      minute(
        morning.addingTimeInterval(Double(offset) * 60), internet: heavy ? 110 : 10,
        bytes: heavy ? 60_000_000 : 1_000))
  }
  return minutes
}

private func restarts() -> [AppEvent] {
  (1...2).map { day in
    AppEvent(
      time: firstDay.addingTimeInterval(Double(day) * 86_400 + 19 * 3600 + 600),
      kind: .restarted, detail: "TP-Link powerline adapters")
  }
}

@Test func weeklySummaryNamesTheWeakLinkAndWhenItFails() throws {
  let summary = WeeklySummary(
    minutes: week(), profiles: [homeProfile], events: restarts(), days: 7, now: now,
    calendar: utc)
  #expect(summary.monitoredMinutes == 405)
  let bridge = try #require(summary.areas.first)
  #expect(bridge.area == .bridge)
  #expect(bridge.incidents == 3)
  #expect(bridge.problemMinutes == 30)
  #expect(bridge.longestMinutes == 10)
  #expect(summary.busiestHours.first == HourOfDay(hour: 19, problemMinutes: 30))
  #expect(summary.load.heavyMinutes == 15)
  #expect(summary.load.addedLatency == 100)
  #expect(summary.restarts.map(\.outcome) == [.helped, .helped])

  let advice = summary.advice(bridgeNames: ["Home": "TP-Link powerline adapters"])
  #expect(advice[0].hasPrefix("Most problems were on the TP-Link powerline adapters."))
  #expect(advice.contains { $0.hasPrefix("Heavy downloads and uploads add about 100 ms") })
  #expect(advice.contains { $0.hasPrefix("Problems cluster around 19:00.") })
  #expect(advice.contains("Restarts helped 2 of 2 times."))

  let text = summary.text(bridgeNames: [:])
  #expect(text.hasPrefix("Summary of the last 7 days\n"))
  #expect(text.contains("the link between the access point and the router: 3 incidents, 30 min"))
  #expect(text.contains("Busiest hours: 19:00 (30 min)"))
  #expect(text.contains("Under heavy use (15 min at 4 Mbit/s or more): 110 ms, otherwise 10 ms"))
}

@Test func quietOrEmptyWeeksSaySo() {
  let empty = WeeklySummary(
    minutes: [], profiles: [], events: [], days: 7, now: now, calendar: utc)
  #expect(empty.advice(bridgeNames: [:]) == ["Nothing was recorded in this period."])
  let quiet = WeeklySummary(
    minutes: (0..<60).map { minute(firstDay.addingTimeInterval(Double($0) * 60 + 86_400)) },
    profiles: [homeProfile], events: [], days: 7, now: now, calendar: utc)
  #expect(quiet.areas.isEmpty)
  #expect(quiet.advice(bridgeNames: [:]) == ["No problems lasting two minutes or more."])
}

@Test func hotspotAreasNameThePhone() {
  #expect(ProblemArea.wifi.name(bridge: nil, hotspot: true) == "the link to the phone")
  #expect(ProblemArea.internet.name(bridge: nil, hotspot: true) == "the phone's mobile connection")
  #expect(ProblemArea(.routerSilent) == .routerQuiet)
  #expect(ProblemArea(.allClear) == nil)
}

@Test func summaryCommandParses() throws {
  #expect(try HeadlessCommand.parse(["summary"]) == .summary(days: 7, json: false))
  #expect(
    try HeadlessCommand.parse(["summary", "--days", "3", "--json"]) == .summary(days: 3, json: true)
  )
  #expect(throws: HeadlessCommand.UsageError.self) {
    try HeadlessCommand.parse(["summary", "--days", "9"])
  }
}
