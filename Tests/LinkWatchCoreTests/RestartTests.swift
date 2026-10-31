import Foundation
import Testing

@testable import LinkWatchCore

/// A history directory that is removed when the test ends.
private final class TemporaryHistory {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("LinkWatchRestart-\(UUID().uuidString)")
  var store: FileHistoryStore { FileHistoryStore(directory: directory) }
  deinit { try? FileManager.default.removeItem(at: directory) }
}

/// Wraps the file store so the harness can use it like the fake.
private final class FileBackedHistory: FakeHistoryStore {
  let file: FileHistoryStore
  init(_ file: FileHistoryStore) { self.file = file }
  override func load(since date: Date) throws -> [MinuteSummary] { try file.load(since: date) }
  override func append(_ summary: MinuteSummary) throws { try file.append(summary) }
  override func prune(before date: Date) throws { try file.prune(before: date) }
  override func clear() throws { try file.clear() }
}

@MainActor
private func run(_ harness: Harness, cycles: Int) async {
  for _ in 0..<cycles { _ = await harness.cycle() }
}

@MainActor
@Test func historyAndProfilesSurviveAQuitAndRelaunch() async throws {
  let temporary = TemporaryHistory()
  let profiles = FakeStore([homeProfile])
  let first = Harness(store: profiles, history: FileBackedHistory(temporary.store))
  await run(first, cycles: 75)
  first.controller.flushHistory()
  let recorded = try temporary.store.load(since: .distantPast)
  #expect(recorded.map(\.samples) == [30, 30, 15])

  let relaunched = Harness(store: profiles, history: FileBackedHistory(temporary.store))
  #expect(relaunched.controller.profiles == [homeProfile])
  #expect(relaunched.controller.week.minutes == recorded)
  #expect(relaunched.controller.session.profile == homeProfile)
}

@MainActor
@Test func aCrashLosesAtMostThePartialMinute() async throws {
  let temporary = TemporaryHistory()
  let crashed = Harness(history: FileBackedHistory(temporary.store))
  await run(crashed, cycles: 75)
  // No flush: the process was killed mid-minute.
  #expect(try temporary.store.load(since: .distantPast).map(\.samples) == [30, 30])

  let relaunched = Harness(history: FileBackedHistory(temporary.store))
  #expect(relaunched.controller.week.minutes.count == 2)
  relaunched.clock.now = crashed.clock.now + 3600
  await run(relaunched, cycles: 31)
  #expect(try temporary.store.load(since: .distantPast).count == 3)
}

@Test func openAtLoginCommandParses() throws {
  #expect(try HeadlessCommand.parse(["open-at-login"]) == .openAtLogin(nil))
  #expect(try HeadlessCommand.parse(["open-at-login", "on"]) == .openAtLogin(.enabled))
  #expect(try HeadlessCommand.parse(["open-at-login", "off"]) == .openAtLogin(.disabled))
  #expect(throws: HeadlessCommand.UsageError.self) {
    try HeadlessCommand.parse(["open-at-login", "maybe"])
  }
}

@MainActor
@Test func diagnosisWarnsWhenLinkWatchWillNotStartAfterARestart() {
  let harness = Harness()
  let status = StatusReport(controller: harness.controller, now: harness.clock.now)
  let now = Date(timeIntervalSinceReferenceDate: 800_003_640)
  func report(_ opensAtLogin: Bool) -> DiagnoseReport {
    DiagnoseReport(
      status: status, appRunning: true, minutes: [], profiles: [homeProfile], hours: 1, now: now,
      primaryInterface: nil, opensAtLogin: opensAtLogin)
  }
  #expect(report(false).notes.contains { $0.hasPrefix("LinkWatch does not open at login") })
  #expect(!report(true).notes.contains { $0.hasPrefix("LinkWatch does not open at login") })
}
