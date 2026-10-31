import AppKit
import Foundation
import LinkWatchCore

/// Builds diagnoses and exported reports the same way for the panel and the command line.
@MainActor
enum Reports {
  /// Exported reports stay in LinkWatch's own folder, which Finder can reveal without the
  /// Downloads or Desktop access prompt.
  static var directory: URL {
    Monitor.supportDirectory.appendingPathComponent("Reports", isDirectory: true)
  }

  struct Diagnosis {
    let report: DiagnoseReport
    let minutes: [MinuteSummary]
    let bridgeNames: [String: String]
    let hotspots: Set<String>
    /// The period's overview, used at the top of exported reports.
    let summary: WeeklySummary
  }

  static func diagnosis(status: StatusReport, appRunning: Bool, hours: Int) -> Diagnosis {
    let now = Date()
    let since = now.addingTimeInterval(-Double(hours) * 3600)
    let minutes =
      (try? FileHistoryStore(directory: Monitor.supportDirectory).load(since: since)) ?? []
    let profiles = (try? UserDefaultsProfileStore().load()).flatMap { $0 } ?? []
    let report = DiagnoseReport(
      status: status, appRunning: appRunning, minutes: minutes, profiles: profiles,
      hours: hours, now: now, primaryInterface: SystemEnvironment().primaryInterface,
      appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
      opensAtLogin: LoginItem.isEnabled,
      events: (try? ReadOnlyEventStore(directory: Monitor.supportDirectory).load(since: since))
        ?? [])
    let bridgeNames = Dictionary(
      profiles.compactMap { profile in profile.bridgeName.map { (profile.ssid, $0) } }
    ) { first, _ in first }
    return Diagnosis(
      report: report, minutes: minutes, bridgeNames: bridgeNames,
      hotspots: Set(profiles.filter(\.hotspot).map(\.ssid)),
      summary: WeeklySummary(
        minutes: minutes, profiles: profiles, events: report.events,
        days: max(1, hours / 24), now: now))
  }

  static func export(
    status: StatusReport, appRunning: Bool, days: Int, redact: Bool, into directory: URL
  ) throws -> URL {
    let diagnosis = diagnosis(status: status, appRunning: appRunning, hours: days * 24)
    return try ExportedReport(
      report: diagnosis.report, minutes: diagnosis.minutes,
      bridgeNames: diagnosis.bridgeNames, hotspots: diagnosis.hotspots,
      summary: diagnosis.summary, redact: redact
    ).write(into: directory)
  }

  /// The panel's Export report button: a week, unredacted, revealed in Finder for sharing.
  static func exportFromPanel(_ controller: MonitorController) throws -> URL {
    controller.flushHistory()
    let status = StatusReport(controller: controller, now: ProcessInfo.processInfo.systemUptime)
    let folder = try export(
      status: status, appRunning: true, days: 7, redact: false, into: directory)
    NSWorkspace.shared.activateFileViewerSelecting([folder])
    return folder
  }
}
