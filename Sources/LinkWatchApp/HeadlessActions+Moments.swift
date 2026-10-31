import Foundation
import LinkWatchCore

/// Marks, restarts and device tests: moments a person reports so the data can be read
/// against them.
extension Headless {
  /// Only the app writes events, so the mark goes through it and is confirmed from the log.
  static func mark(_ label: String) async -> Int32 {
    guard await AppControl.liveStatus() != nil else {
      write(
        "LinkWatch: the menu bar app is not running; open LinkWatch first.\n", to: .standardError)
      return 69
    }
    let since = Date().addingTimeInterval(-1)
    AppControl.post(.mark, label: label)
    let store = ReadOnlyEventStore(directory: Monitor.supportDirectory)
    for _ in 0..<20 {
      if (try? store.load(since: since))?.contains(where: {
        $0.kind == .marked && $0.detail == label
      })
        == true
      {
        write(
          "Marked \"\(label)\" at \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)).\n"
        )
        return 0
      }
      try? await Task.sleep(for: .milliseconds(100))
    }
    write("LinkWatch: the menu bar app did not record the mark.\n", to: .standardError)
    return 1
  }

  /// Starts the test in the running app and relays its prompts until it finishes.
  static func testDevice(_ device: String) async -> Int32 {
    guard await AppControl.liveStatus() != nil else {
      write(
        "LinkWatch: the menu bar app is not running; open LinkWatch first.\n", to: .standardError)
      return 69
    }
    AppControl.post(.startDeviceTest, label: device)
    var lastPhase: DeviceTestPhase?
    var started = false
    for _ in 0..<240 {
      try? await Task.sleep(for: .seconds(1))
      guard let test = await AppControl.liveStatus()?.deviceTest else { continue }
      switch test.state {
      case "running":
        started = true
        if test.phase != lastPhase, let phase = test.phase, let instruction = test.instruction {
          lastPhase = phase
          write("[\(phase.rawValue), \(test.secondsLeft ?? 0) s] \(instruction)\n")
        }
      case "finished" where started:
        write("\n" + (test.message ?? "") + "\n")
        for phase in test.result?.phases ?? [] { write(Self.phaseLine(phase)) }
        return 0
      case "cancelled":
        write("LinkWatch: \(test.message ?? "the test was cancelled")\n", to: .standardError)
        return 1
      default:
        continue
      }
    }
    write("LinkWatch: the device test did not finish.\n", to: .standardError)
    return 1
  }

  private static func phaseLine(_ phase: DeviceTestPhaseResult) -> String {
    func spikes(_ summary: TargetSummary?) -> String {
      guard let summary else { return "—" }
      let p95 = summary.p95.map { String(format: "%.0f ms", $0) } ?? "no reply"
      return p95 + String(format: " (%.0f%% lost)", summary.loss * 100)
    }
    return "  \(phase.phase.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) "
      + "AP \(spikes(phase.accessPoint)) · router \(spikes(phase.router)) · "
      + "internet \(spikes(phase.internet)) · \(phase.samples) samples (worst 5%)\n"
  }

  /// Records a restart in the running app; with `wait`, also reports its effect once enough
  /// minutes have followed (about five).
  static func restarted(_ device: String?, wait: Bool) async -> Int32 {
    guard await AppControl.liveStatus() != nil else {
      write(
        "LinkWatch: the menu bar app is not running; open LinkWatch first.\n", to: .standardError)
      return 69
    }
    let since = Date().addingTimeInterval(-1)
    AppControl.post(.restarted, label: device)
    let store = ReadOnlyEventStore(directory: Monitor.supportDirectory)
    var recorded: AppEvent?
    for _ in 0..<20 where recorded == nil {
      recorded = (try? store.load(since: since))?.last { $0.kind == .restarted }
      if recorded == nil { try? await Task.sleep(for: .milliseconds(100)) }
    }
    guard let recorded else {
      write("LinkWatch: the menu bar app did not record the restart.\n", to: .standardError)
      return 1
    }
    let time = DateFormatter.localizedString(
      from: recorded.time, dateStyle: .none, timeStyle: .short)
    write("Recorded restarting the \(recorded.detail ?? "device") at \(time).\n")
    guard wait else {
      write("LinkWatch compares the links before and after; see `status` in about 5 minutes.\n")
      return 0
    }
    return await waitForRestartEffect()
  }

  private static func waitForRestartEffect() async -> Int32 {
    let minutes = Int((RestartEffect.settle + 60) / 60) + RestartEffect.minimumMinutes
    write("Waiting about \(minutes) minutes for measurements after the restart…\n")
    for _ in 0..<60 {
      try? await Task.sleep(for: .seconds(10))
      guard let effect = await AppControl.liveStatus()?.restart else { continue }
      if effect.outcome != .measuring {
        write(effect.sentence + "\n")
        return 0
      }
    }
    write("LinkWatch: no result yet; check `status` later.\n", to: .standardError)
    return 1
  }
}
