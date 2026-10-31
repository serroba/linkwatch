import Foundation
import Testing

@testable import LinkWatchCore

private let minute = Date(timeIntervalSinceReferenceDate: 800_000_040)

private func pair(_ seconds: Double, accessPoint: ProbeOutcome, router: ProbeOutcome) -> ProbePair {
  ProbePair(elapsed: seconds, accessPoint: accessPoint, router: router)
}

@Test func minutesSummariseMedianP95LossAndWorstState() {
  var week = WeekHistory()
  let routerTimes: [Double] = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
  for (index, time) in routerTimes.enumerated() {
    let health: Health = index == 4 ? .routerSlower : .healthy
    let outcome: ProbeOutcome = index == 9 ? .timeout : .success(milliseconds: time)
    #expect(
      week.record(
        pair(Double(index), accessPoint: .success(milliseconds: 2), router: outcome),
        health: health, ssid: "Home", at: minute.addingTimeInterval(Double(index) * 5)) == nil)
  }
  let summary = week.record(
    pair(60, accessPoint: .success(milliseconds: 2), router: .success(milliseconds: 5)),
    health: .healthy, ssid: "Home", at: minute.addingTimeInterval(61))
  #expect(summary?.start == minute)
  #expect(summary?.samples == 10)
  #expect(summary?.accessPoint == target(2, 2, loss: 0))
  #expect(summary?.router.median == 50)
  #expect(summary?.router.p95 == 90)
  #expect(summary?.router.loss == 0.1)
  #expect(summary?.worstHealth == "routerSlower")
  #expect(week.minutes.count == 1)
}

@Test func networkChangeAndFlushCompleteMinutes() {
  var week = WeekHistory()
  let sample = pair(0, accessPoint: .success(milliseconds: 1), router: .success(milliseconds: 2))
  _ = week.record(sample, health: .healthy, ssid: "Home", at: minute)
  let switched = week.record(
    sample, health: .unreachable(accessPoint: true, router: false), ssid: "Cafe",
    at: minute.addingTimeInterval(5))
  #expect(switched?.ssid == "Home")
  let flushed = week.flush()
  #expect(flushed?.ssid == "Cafe")
  #expect(flushed?.worstHealth == "unreachable")
  #expect(week.flush() == nil)
  #expect(week.minutes.map(\.ssid) == ["Home", "Cafe"])
}

@Test func pruneKeepsSevenDaysAndClearEmpties() {
  let old = MinuteSummary(
    start: minute.addingTimeInterval(-WeekHistory.retention - 60), ssid: "Home", samples: 1,
    accessPoint: target(1, 1, loss: 0),
    router: target(2, 2, loss: 0), worstHealth: "healthy")
  var recent = old
  recent.start = minute.addingTimeInterval(-60)
  var week = WeekHistory(minutes: [recent, old])
  #expect(week.minutes.first == old)
  #expect(week.prune(now: minute) == minute.addingTimeInterval(-WeekHistory.retention))
  #expect(week.minutes == [recent])
  week.clear()
  #expect(week.minutes.isEmpty)
}

@Test func fileStoreAppendsPrunesClearsAndStaysPrivate() throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("LinkWatchTests-\(UUID().uuidString)/history")
  defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
  let store = FileHistoryStore(directory: directory)
  #expect(try store.load(since: .distantPast).isEmpty)
  let first = MinuteSummary(
    start: minute, ssid: "Home", samples: 30,
    accessPoint: target(2, 4, loss: 0),
    router: target(nil, nil, loss: 1), worstHealth: "unreachable")
  var second = first
  second.start = minute.addingTimeInterval(60)
  try store.append(first)
  try store.append(second)
  #expect(try store.load(since: .distantPast) == [first, second])

  let attributes = try FileManager.default.attributesOfItem(
    atPath: directory.appendingPathComponent("history.jsonl").path)
  #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
  let folder = try FileManager.default.attributesOfItem(atPath: directory.path)
  #expect((folder[.posixPermissions] as? NSNumber)?.intValue == 0o700)

  let handle = try FileHandle(forWritingTo: directory.appendingPathComponent("history.jsonl"))
  try handle.seekToEnd()
  try handle.write(contentsOf: Data("{not json\n".utf8))
  try handle.close()
  #expect(try store.load(since: .distantPast) == [first, second])

  try store.prune(before: second.start)
  #expect(try store.load(since: .distantPast) == [second])
  try store.clear()
  #expect(try store.load(since: .distantPast).isEmpty)
}
