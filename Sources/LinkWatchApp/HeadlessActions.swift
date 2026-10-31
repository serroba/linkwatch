import Foundation
import LinkWatchCore

/// Command-line equivalents of the menu bar panel and Settings window actions.
extension Headless {
  static func act(_ command: HeadlessCommand) async -> Int32 {
    switch command {
    case .accept(let json): return await accept(json: json)
    case .findAccessPoint(let json): return await findAccessPoint(json: json)
    case .dismiss: return await tellApp(.dismissSuggestion) { $0.suggestion == nil }
    case .pause: return await tellApp(.pause) { $0.paused }
    case .resume: return await tellApp(.resume) { !$0.paused }
    case .authorize: return await authorize()
    default: return await manage(command)
    }
  }

  /// Profile and history management, as in the Settings window.
  private static func manage(_ command: HeadlessCommand) async -> Int32 {
    switch command {
    case .listProfiles(let json): return await listProfiles(json: json)
    case .setProfile(let update): return await setProfile(update)
    case .removeProfile(let ssid): return await removeProfile(ssid)
    case .history(let hours, let json): return history(hours: hours, json: json)
    case .clearHistory: return clearHistory()
    default:
      write("LinkWatch: unsupported command\n", to: .standardError)
      return 64
    }
  }

  private static func accept(json: Bool) async -> Int32 {
    let monitor = await readyMonitor()
    let controller = monitor.controller
    guard let suggestion = controller.suggestion else {
      return fail("There is no suggestion to accept for the current Wi-Fi network.", code: 1)
    }
    guard controller.acceptSuggestion() else {
      if case .monitor = suggestion {
        return fail(
          "The AP is not known yet. Run find-ap, or set it with profile set --ssid NAME --ap ADDRESS.",
          code: 1)
      }
      return fail(controller.storageError ?? "The profile could not be saved.", code: 1)
    }
    AppControl.post(.reloadProfiles)
    if !json { write("Saved the profile; monitoring starts on this network.\n") }
    return await status(json: json, local: false)
  }

  private static func findAccessPoint(json: Bool) async -> Int32 {
    let monitor = await readyMonitor()
    if !json { write("Searching the Wi-Fi subnet for the AP; this pings each address once.\n") }
    await monitor.controller.searchForAccessPoint()
    emit(StatusReport(controller: monitor.controller, now: uptime), json: json)
    guard case .found = monitor.controller.discovery?.accessPoint else { return 1 }
    if !json { write("Run accept to monitor this network.\n") }
    return 0
  }

  /// Sends a message to the running app and confirms the change through its live status.
  private static func tellApp(
    _ message: AppControl.Message, until applied: (StatusReport) -> Bool
  ) async -> Int32 {
    guard await AppControl.liveStatus() != nil else {
      return fail("The menu bar app is not running; open LinkWatch first.", code: 69)
    }
    AppControl.post(message)
    for _ in 0..<10 {
      if let report = await AppControl.liveStatus(), applied(report) {
        emit(report, json: false)
        return 0
      }
      try? await Task.sleep(for: .milliseconds(200))
    }
    return fail("The menu bar app did not confirm the change.", code: 1)
  }

  /// macOS shows the Location prompt only for the app, so ask the running app to request it.
  private static func authorize() async -> Int32 {
    let environment = SystemEnvironment()
    for _ in 0..<20 where environment.authorizationDescription == "not determined" {
      try? await Task.sleep(for: .milliseconds(50))
    }
    if environment.isPermitted {
      write("Location permission is granted.\n")
      return 0
    }
    if environment.isDenied {
      return fail(
        "Location permission is \(environment.authorizationDescription). Enable LinkWatch in System Settings › Privacy & Security › Location Services.",
        code: 77)
    }
    guard await AppControl.liveStatus() != nil else {
      return fail("Open the LinkWatch menu bar app, then run authorize again.", code: 69)
    }
    AppControl.post(.requestPermission)
    write("Asked the menu bar app to request Location permission; answer the macOS prompt.\n")
    for _ in 0..<120 {
      if environment.isPermitted {
        write("Location permission granted.\n")
        return 0
      }
      if environment.isDenied { break }
      try? await Task.sleep(for: .milliseconds(500))
    }
    return fail("Location permission is \(environment.authorizationDescription).", code: 77)
  }

  private static func listProfiles(json: Bool) async -> Int32 {
    let profiles = await readyMonitor().controller.profiles
    if json {
      emit(encodable: profiles, compact: false)
    } else if profiles.isEmpty {
      write("No profiles saved.\n")
    } else {
      for profile in profiles {
        let thresholds = profile.thresholds
        write(
          "\(profile.ssid): AP \(profile.accessPoint) · Router \(profile.router) · alert above "
            + "\(thresholds.difference) ms difference or \(thresholds.slow) ms both, after "
            + "\(thresholds.sustainedSeconds) s; recover below \(thresholds.recoveryDifference) ms"
            + " / \(thresholds.recoverySlow) ms for \(thresholds.recoverySeconds) s; internet "
            + (profile.internetReferences ? "on" : "off") + "\n")
      }
    }
    return 0
  }

  private static func setProfile(_ update: ProfileUpdate) async -> Int32 {
    let controller = await readyMonitor().controller
    let existing = controller.profiles.first { $0.ssid == update.ssid }
    guard let profile = update.applied(to: existing) else {
      return fail("A new profile needs both --ap and --router.", code: 64)
    }
    guard profile.isValid else {
      return fail(
        "Invalid profile: use distinct IPv4 addresses, a name of 1–32 bytes, and recovery thresholds below alert thresholds.",
        code: 64)
    }
    guard controller.save(profile) else {
      return fail(controller.storageError ?? "The profile could not be saved.", code: 1)
    }
    AppControl.post(.reloadProfiles)
    write("Saved \(profile.ssid): AP \(profile.accessPoint) · Router \(profile.router).\n")
    return 0
  }

  private static func removeProfile(_ ssid: String) async -> Int32 {
    let controller = await readyMonitor().controller
    guard let profile = controller.profiles.first(where: { $0.ssid == ssid }) else {
      return fail("No profile named \(ssid).", code: 1)
    }
    controller.remove(profile)
    guard !controller.profiles.contains(profile) else {
      return fail(controller.storageError ?? "The profile could not be removed.", code: 1)
    }
    AppControl.post(.reloadProfiles)
    write("Removed \(ssid); it is no longer probed.\n")
    return 0
  }

  private static func fail(_ message: String, code: Int32) -> Int32 {
    write("LinkWatch: \(message)\n", to: .standardError)
    return code
  }
}

/// Reading and clearing the stored week of history from the command line.
extension Headless {
  static func history(hours: Int, json: Bool) -> Int32 {
    let store = FileHistoryStore(directory: Monitor.supportDirectory)
    let minutes: [MinuteSummary]
    do {
      minutes = try store.load(since: Date().addingTimeInterval(-Double(hours) * 3600))
    } catch {
      write(
        "LinkWatch: history could not be read: \(error.localizedDescription)\n", to: .standardError)
      return 1
    }
    if json {
      emit(encodable: minutes, compact: false)
      return 0
    }
    guard !minutes.isEmpty else {
      write(
        "No history in the last \(hours) h. Minutes are stored once a profiled network is monitored.\n"
      )
      return 0
    }
    let profiles = (try? UserDefaultsProfileStore().load()).flatMap { $0 } ?? []
    write(HistoryTable.text(minutes, profiles: profiles))
    return 0
  }

  static func clearHistory() -> Int32 {
    do {
      try FileHistoryStore(directory: Monitor.supportDirectory).clear()
    } catch {
      write(
        "LinkWatch: history could not be cleared: \(error.localizedDescription)\n",
        to: .standardError)
      return 1
    }
    AppControl.post(.reloadHistory)
    write("Cleared the stored history.\n")
    return 0
  }
}

/// Hourly rollups of minute summaries for terminal output.
enum HistoryTable {
  static func text(_ minutes: [MinuteSummary], profiles: [NetworkProfile]) -> String {
    let thresholds = Dictionary(profiles.map { ($0.ssid, $0.thresholds) }) { first, _ in first }
    let hours = Dictionary(grouping: minutes) { minute in
      Calendar.current.dateInterval(of: .hour, for: minute.start)?.start ?? minute.start
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:00"
    var lines = [
      "Hour              Samples  AP median/p95  loss   Router median/p95  loss   "
        + "Internet median/p95  loss   Problem minutes"
    ]
    for (hour, group) in hours.sorted(by: { $0.key < $1.key }) {
      let samples = group.reduce(0) { $0 + $1.samples }
      let verdicts = group.map {
        Verdict(LinkEvidence($0), thresholds: thresholds[$0.ssid] ?? Thresholds())
      }
      let problems = verdicts.filter(\.isProblem)
      let common = Dictionary(grouping: problems) { $0 }.max { $0.value.count < $1.value.count }
      lines.append(
        formatter.string(from: hour) + "  " + pad(String(samples), 7) + "  "
          + target(group.map(\.accessPoint), samples: group.map(\.samples)) + "  "
          + target(group.map(\.router), samples: group.map(\.samples)) + "  "
          + internet(group) + "     " + "\(problems.count)/\(group.count)"
          + (common.map { " mostly \($0.key.rawValue)" } ?? ""))
    }
    return lines.joined(separator: "\n") + "\n"
  }

  private static func internet(_ minutes: [MinuteSummary]) -> String {
    let probed = minutes.filter { $0.internet != nil }
    guard !probed.isEmpty else { return pad("not probed", 21) }
    return target(probed.compactMap(\.internet), samples: probed.map(\.samples))
  }

  /// Median of minute medians, worst minute p95, and sample-weighted loss.
  private static func target(_ summaries: [TargetSummary], samples: [Int]) -> String {
    let medians = summaries.compactMap(\.median).sorted()
    let median = medians.isEmpty ? "—" : String(format: "%.1f", medians[medians.count / 2])
    let p95 = summaries.compactMap(\.p95).max().map { String(format: "%.1f", $0) } ?? "—"
    let total = samples.reduce(0, +)
    let lost = zip(summaries, samples).reduce(0.0) { $0 + $1.0.loss * Double($1.1) }
    let loss = total == 0 ? 0 : lost / Double(total) * 100
    return pad("\(median)/\(p95) ms", 15) + "  " + pad(String(format: "%.0f%%", loss), 4)
  }

  private static func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : String(repeating: " ", count: width - text.count) + text
  }
}
