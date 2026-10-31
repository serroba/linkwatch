import Foundation
import LinkWatchCore

/// Command-line equivalents of the menu bar panel and Settings window actions.
extension Headless {
  static func act(_ command: HeadlessCommand) async -> Int32 {
    switch command {
    case .accept(let json): return await accept(json: json)
    case .findAccessPoint(let json): return await findAccessPoint(json: json)
    case .dismiss: return await tellApp(.dismissSuggestion) { $0.suggestion == nil }
    case .detect: return await detect()
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
    case .openAtLogin(let setting): return openAtLogin(setting)
    case .notifications(let setting): return await notifications(setting)
    case .update(let install, let automatic):
      return await update(install: install, automatic: automatic)
    case .mark(let label): return await mark(label)
    case .testDevice(let device): return await testDevice(device)
    case .restarted(let device, let wait): return await restarted(device, wait: wait)
    default: return await report(command)
    }
  }

  /// History, events, incidents, diagnosis and exports.
  private static func report(_ command: HeadlessCommand) async -> Int32 {
    switch command {
    case .history(let hours, let json): return history(hours: hours, json: json)
    case .clearHistory: return clearHistory()
    case .events(let hours, let json): return events(hours: hours, json: json)
    case .export(let days, let directory, let redact):
      return await export(days: days, directory: directory, redact: redact)
    case .incidents(let days, let json): return incidents(days: days, json: json)
    case .summary(let days, let json): return await summary(days: days, json: json)
    case .diagnose(let hours, let json): return await diagnose(hours: hours, json: json)
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

  /// Asks the running app to recheck its path, then prints the status it reports.
  private static func detect() async -> Int32 {
    guard await AppControl.liveStatus() != nil else {
      return fail("The menu bar app is not running; open LinkWatch first.", code: 69)
    }
    AppControl.post(.detectPath)
    try? await Task.sleep(for: .milliseconds(300))
    guard let report = await AppControl.liveStatus() else {
      return fail("The menu bar app did not answer.", code: 1)
    }
    emit(report, json: false)
    return 0
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
          "\(profile.ssid): AP \(profile.accessPointText) · Router \(profile.router) · alert above "
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
    write("Saved \(profile.ssid): AP \(profile.accessPointText) · Router \(profile.router).\n")
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
    write(HistoryRollup.table(HistoryRollup.hours(minutes, profiles: profiles)))
    return 0
  }

  /// The period at a glance, the same overview that opens exported reports.
  static func summary(days: Int, json: Bool) async -> Int32 {
    let live = await AppControl.liveStatus()
    let status = await currentStatus(live: live)
    let diagnosis = Reports.diagnosis(status: status, appRunning: live != nil, hours: days * 24)
    if json {
      emit(encodable: diagnosis.summary, compact: false)
    } else {
      write(
        diagnosis.summary.text(bridgeNames: diagnosis.bridgeNames, hotspots: diagnosis.hotspots))
    }
    return 0
  }

  static func incidents(days: Int, json: Bool) -> Int32 {
    let since = Date().addingTimeInterval(-Double(days) * 86_400)
    guard
      let minutes = try? FileHistoryStore(directory: Monitor.supportDirectory).load(since: since)
    else {
      write("LinkWatch: history could not be read.\n", to: .standardError)
      return 1
    }
    let profiles = (try? UserDefaultsProfileStore().load()).flatMap { $0 } ?? []
    let incidents = IncidentTimeline.incidents(from: minutes, profiles: profiles).reversed()
    if json {
      emit(encodable: Array(incidents), compact: false)
      return 0
    }
    guard !incidents.isEmpty else {
      write("No incidents in the last \(days) day\(days == 1 ? "" : "s").\n")
      return 0
    }
    let byNetwork = Dictionary(profiles.map { ($0.ssid, $0) }) { first, _ in first }
    for incident in incidents {
      let profile = byNetwork[incident.ssid]
      let bridge = profile?.bridgeName
      let hotspot = profile?.hotspot ?? false
      let action = incident.verdict.action(bridge: bridge, hotspot: hotspot)
      write(
        incident.summary(bridge: bridge, hotspot: hotspot) + "\n  " + incident.evidence
          + "\n  → " + (action ?? "No action needed.") + "\n")
    }
    return 0
  }

  /// Bundles live state, coverage, incidents and hourly history for answering
  /// "what's going on with my network?" from evidence.
  static func diagnose(hours: Int, json: Bool) async -> Int32 {
    let live = await AppControl.liveStatus()
    let status = await currentStatus(live: live)
    let diagnosis = Reports.diagnosis(status: status, appRunning: live != nil, hours: hours)
    if json {
      emit(encodable: diagnosis.report, compact: false)
    } else {
      write(
        diagnosis.report.text(bridgeNames: diagnosis.bridgeNames, hotspots: diagnosis.hotspots))
    }
    return 0
  }

  static func export(days: Int, directory: String?, redact: Bool) async -> Int32 {
    let live = await AppControl.liveStatus()
    let status = await currentStatus(live: live)
    let target = directory.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    do {
      let folder = try Reports.export(
        status: status, appRunning: live != nil, days: days, redact: redact,
        into: target ?? Reports.directory)
      write(folder.path + "\n")
      return 0
    } catch {
      write(
        "LinkWatch: the report could not be written: \(error.localizedDescription)\n",
        to: .standardError)
      return 1
    }
  }

  /// The running app's live status, or a fresh local one when it is not running.
  private static func currentStatus(live: StatusReport?) async -> StatusReport {
    if let live { return live }
    return StatusReport(controller: await readyMonitor().controller, now: uptime)
  }

  static func notifications(_ setting: ProfileUpdate.Switch?) async -> Int32 {
    if let setting {
      let enabled = await ProblemNotifier.set(setting == .enabled)
      if setting == .enabled, !enabled {
        write(
          "LinkWatch: notifications are not allowed; allow LinkWatch in System Settings › Notifications.\n",
          to: .standardError)
        return 1
      }
    }
    write("Notifications: \(ProblemNotifier.description)\n")
    return 0
  }

  static func openAtLogin(_ setting: ProfileUpdate.Switch?) -> Int32 {
    if let setting {
      do {
        try LoginItem.set(setting == .enabled)
      } catch {
        write(
          "LinkWatch: could not change the login item: \(error.localizedDescription)\n",
          to: .standardError)
        return 1
      }
    }
    write("Open at login: \(LoginItem.description)\n")
    return 0
  }

  static func events(hours: Int, json: Bool) -> Int32 {
    let since = Date().addingTimeInterval(-Double(hours) * 3600)
    let events =
      (try? ReadOnlyEventStore(directory: Monitor.supportDirectory).load(since: since)) ?? []
    if json {
      emit(encodable: events, compact: false)
      return 0
    }
    guard !events.isEmpty else {
      write("No events in the last \(hours) h.\n")
      return 0
    }
    let time = DateFormatter()
    time.setLocalizedDateFormatFromTemplate("EEE d MMM HH:mm:ss")
    for event in events { write("\(time.string(from: event.time))  \(event.summary)\n") }
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
