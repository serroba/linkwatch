import Foundation
import Testing

@testable import LinkWatchCore

@Test func observedChangesBecomeEvents() {
  let start = ObservedState()
  var joined = start
  joined.ssid = "Home"
  joined.bssid = "00:00:5e:00:53:01"
  joined.monitoring = "Home"
  #expect(joined.events(since: start, reason: "").map(\.0) == [.joinedWiFi, .monitoringStarted])
  #expect(joined.events(since: start, reason: "").first?.1 == "Home via 00:00:5e:00:53:01")
  var roamed = joined
  roamed.bssid = "00:00:5e:00:53:02"
  #expect(roamed.events(since: joined, reason: "").map(\.0) == [.roamed])
  var paused = roamed
  paused.paused = true
  paused.monitoring = nil
  let pauseEvents = paused.events(since: roamed, reason: "Paused manually")
  #expect(pauseEvents.map(\.0) == [.paused, .monitoringStopped])
  #expect(pauseEvents.last?.1 == "Paused manually")
  var asleep = paused
  asleep.sleeping = true
  asleep.permitted = false
  asleep.ssid = nil
  asleep.bssid = nil
  #expect(
    asleep.events(since: paused, reason: "").map(\.0) == [.permissionMissing, .asleep, .leftWiFi])
  var degraded = joined
  degraded.verdict = .bridgeSpikes
  #expect(degraded.events(since: joined, reason: "").first?.1 == "allClear → bridgeSpikes")
  #expect(joined.events(since: joined, reason: "").isEmpty)
}

@MainActor
@Test func controllerRecordsTransitionsOnceAndUserActions() async {
  let harness = Harness()
  #expect(harness.events.kinds == [.joinedWiFi, .monitoringStarted])
  for _ in 0..<3 { harness.controller.refresh() }
  #expect(harness.events.kinds.count == 2)
  harness.controller.paused = true
  harness.controller.paused = false
  harness.controller.setSleeping(true)
  harness.controller.setSleeping(false)
  #expect(
    Array(harness.events.kinds.dropFirst(2))
      == [
        .paused, .monitoringStopped, .resumed, .monitoringStarted, .asleep, .monitoringStopped,
        .awake, .monitoringStarted,
      ])
  harness.script.outcomes["192.0.2.1"] = .success(milliseconds: 80)
  for _ in 0..<8 { _ = await harness.cycle() }
  #expect(harness.events.saved.last?.summary == "verdictChanged: allClear → bridge")
  #expect(harness.controller.mark("  desk moved\nignored line  "))
  #expect(!harness.controller.mark("   "))
  #expect(harness.events.saved.last?.summary == "marked: desk moved")
  harness.controller.clearHistory()
  harness.controller.remove(homeProfile)
  #expect(harness.events.kinds.contains(.historyCleared))
  #expect(harness.events.kinds.last == .profileRemoved)
}

@Test func eventFilesAppendPruneAndStayReadOnlyForOthers() throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("LinkWatchEvents-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = FileEventStore(directory: directory)
  let old = AppEvent(
    time: Date(timeIntervalSinceReferenceDate: 0), kind: .launched, detail: "0.3.0")
  let recent = AppEvent(
    time: Date(timeIntervalSinceReferenceDate: 600), kind: .marked, detail: "desk")
  try store.append(old)
  try store.append(recent)
  let reader = ReadOnlyEventStore(directory: directory)
  try reader.append(old)
  try reader.prune(before: .distantFuture)
  #expect(try reader.load(since: .distantPast) == [old, recent])
  try store.prune(before: Date(timeIntervalSinceReferenceDate: 300))
  #expect(try store.load(since: .distantPast) == [recent])
}

@MainActor
@Test func diagnosisExplainsGapsWithEvents() {
  let harness = Harness()
  let status = StatusReport(controller: harness.controller, now: harness.clock.now)
  let start = Date(timeIntervalSinceReferenceDate: 800_002_800)
  let minutes = (0..<20).map { index in
    MinuteSummary(
      start: start.addingTimeInterval(Double(index < 10 ? index : index + 30) * 60), ssid: "Home",
      samples: 30, accessPoint: target(3, 4, loss: 0), router: target(6, 8, loss: 0),
      internet: nil, worstHealth: "healthy")
  }
  let events = [
    AppEvent(time: start.addingTimeInterval(605), kind: .asleep),
    AppEvent(time: start.addingTimeInterval(2390), kind: .awake),
    AppEvent(time: start.addingTimeInterval(3000), kind: .marked, detail: "desk moved"),
  ]
  let report = DiagnoseReport(
    status: status, appRunning: true, minutes: minutes, profiles: [homeProfile], hours: 1,
    now: start.addingTimeInterval(3600), primaryInterface: nil, events: events)
  #expect(report.gaps.count >= 1)
  #expect(report.gaps.first?.before == "asleep")
  #expect(report.gaps.first?.after == "awake")
  let text = report.text(bridgeNames: [:])
  #expect(text.contains("(after asleep, until awake)"))
  #expect(text.contains("Events (latest 3 of 3)"))
  #expect(text.contains("marked: desk moved"))
}

@Test func eventAndMarkCommandsParse() throws {
  #expect(try HeadlessCommand.parse(["events"]) == .events(hours: 24, json: false))
  #expect(
    try HeadlessCommand.parse(["events", "--hours", "2", "--json"]) == .events(hours: 2, json: true)
  )
  #expect(try HeadlessCommand.parse(["mark", "desk", "up"]) == .mark("desk up"))
  #expect(throws: HeadlessCommand.UsageError.self) { try HeadlessCommand.parse(["mark"]) }
  #expect(AppEvent.markLabel(String(repeating: "x", count: 80))?.count == 60)
}
