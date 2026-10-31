import Testing

@testable import LinkWatchCore

private let restartAdvice = (
  headline: "The TP-Link is struggling.", action: Optional("Restart it.")
)
private let clearAdvice = (headline: "Everything is working normally.", action: String?.none)

/// Feeds one verdict every 10 s from `start` for `seconds`, returning the notices.
private func feed(
  _ alerts: inout ProblemAlerts, _ verdict: Verdict, from start: Double, for seconds: Double,
  monitoring: Bool = true
) -> [ProblemAlerts.Notice] {
  stride(from: start, to: start + seconds, by: 10).compactMap {
    alerts.update(
      verdict: verdict, monitoring: monitoring,
      advice: verdict == .allClear ? clearAdvice : restartAdvice, now: $0)
  }
}

@Test func lastingProblemsNotifyOnceAndThenSayTheyAreOver() {
  var alerts = ProblemAlerts()
  #expect(feed(&alerts, .bridge, from: 0, for: 170).isEmpty)
  #expect(
    feed(&alerts, .bridge, from: 170, for: 300)
      == [ProblemAlerts.Notice(title: "The TP-Link is struggling.", body: "Restart it.")])
  // A change of cause during the same problem does not notify again.
  #expect(feed(&alerts, .internet, from: 470, for: 300).isEmpty)
  #expect(feed(&alerts, .allClear, from: 770, for: 50).isEmpty)
  #expect(feed(&alerts, .allClear, from: 820, for: 20).map(\.title) == ["Back to normal"])
  #expect(feed(&alerts, .allClear, from: 840, for: 600).isEmpty)
}

@Test func blipsSpikesAndPausesDoNotNotify() {
  var alerts = ProblemAlerts()
  #expect(feed(&alerts, .bridge, from: 0, for: 120).isEmpty)
  #expect(feed(&alerts, .allClear, from: 120, for: 30).isEmpty)
  #expect(feed(&alerts, .bridge, from: 150, for: 120).isEmpty)
  #expect(feed(&alerts, .bridgeSpikes, from: 270, for: 900).isEmpty)
  #expect(feed(&alerts, .busy, from: 1170, for: 900).isEmpty)
  #expect(feed(&alerts, .routerSilent, from: 2070, for: 900).isEmpty)
  #expect(feed(&alerts, .internet, from: 2970, for: 120).isEmpty)
  #expect(feed(&alerts, .internet, from: 3090, for: 600, monitoring: false).isEmpty)
  #expect(feed(&alerts, .internet, from: 3690, for: 170).isEmpty)
}

@Test func notificationsCommandParses() throws {
  #expect(try HeadlessCommand.parse(["notifications"]) == .notifications(nil))
  #expect(try HeadlessCommand.parse(["notifications", "on"]) == .notifications(.enabled))
  #expect(throws: HeadlessCommand.UsageError.self) {
    try HeadlessCommand.parse(["notifications", "maybe"])
  }
}
