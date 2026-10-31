import AppKit
import Darwin
import Foundation
import LinkWatchCore

/// Local messages from command-line runs to the running menu bar app.
///
/// Any process of this user can post distributed notifications, so messages carry no
/// settings: profiles change only through the user's own defaults, and status replies
/// are written only into a fresh private directory the requester created.
enum AppControl {
  enum Message: String {
    case reloadProfiles
    case reloadHistory
    case pause
    case resume
    case dismissSuggestion
    case requestPermission
    case reportStatus
    case mark

    var name: Notification.Name { Notification.Name("io.github.serroba.LinkWatch.\(rawValue)") }
  }

  private static let replyKey = "reply"
  private static let labelKey = "label"
  private static let replyName = "status.json"
  private static let directoryPrefix = "LinkWatch-reply-"

  static func post(_ message: Message, reply: URL? = nil, label: String? = nil) {
    var userInfo: [String: String] = [:]
    if let reply { userInfo[replyKey] = reply.path }
    if let label { userInfo[labelKey] = label }
    DistributedNotificationCenter.default().postNotificationName(
      message.name, object: nil, userInfo: userInfo.isEmpty ? nil : userInfo,
      deliverImmediately: true)
  }

  /// Asks the running app for its live status; nil when no app answers in time.
  static func liveStatus(timeout: Duration = .milliseconds(1500)) async -> StatusReport? {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(directoryPrefix + UUID().uuidString)
    guard mkdir(directory.path, 0o700) == 0 else { return nil }
    defer { try? FileManager.default.removeItem(at: directory) }
    let reply = directory.appendingPathComponent(replyName)
    post(.reportStatus, reply: reply)
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
      if let data = try? Data(contentsOf: reply),
        let report = try? JSONDecoder().decode(StatusReport.self, from: data)
      {
        return report
      }
      try? await Task.sleep(for: .milliseconds(50))
    }
    return nil
  }

  /// Handles messages in the menu bar app.
  ///
  /// Keep the returned observers alive for as long as the app should respond.
  @MainActor
  static func listen(controller: MonitorController, environment: SystemEnvironment)
    -> [any NSObjectProtocol]
  {
    let center = DistributedNotificationCenter.default()
    let handlers: [Message: @MainActor (Notification) -> Void] = [
      .reloadProfiles: { _ in controller.reloadProfiles() },
      .reloadHistory: { _ in controller.reloadHistory() },
      .pause: { _ in controller.paused = true },
      .resume: { _ in controller.paused = false },
      .dismissSuggestion: { _ in controller.dismissSuggestion() },
      .requestPermission: { _ in environment.requestPermission() },
      .mark: { notification in
        if let label = notification.userInfo?[labelKey] as? String { controller.mark(label) }
      },
      .reportStatus: { notification in
        guard let path = notification.userInfo?[replyKey] as? String else { return }
        let report = StatusReport(controller: controller, now: ProcessInfo.processInfo.systemUptime)
        writeReply(report, to: path)
      },
    ]
    return handlers.map { message, handler in
      center.addObserver(forName: message.name, object: nil, queue: .main) { notification in
        let notification = UncheckedNotification(value: notification)
        MainActor.assumeIsolated { handler(notification.value) }
      }
    }
  }

  /// Writes only to `status.json` inside a requester-created, private directory in this user's
  /// temporary directory, creating the file exclusively without following links.
  private static func writeReply(_ report: StatusReport, to path: String) {
    let reply = URL(fileURLWithPath: path).standardizedFileURL
    let directory = reply.deletingLastPathComponent()
    let temporary = FileManager.default.temporaryDirectory.standardizedFileURL
    guard reply.lastPathComponent == replyName,
      directory.lastPathComponent.hasPrefix(directoryPrefix),
      directory.deletingLastPathComponent().path == temporary.path,
      let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path),
      attributes[.type] as? FileAttributeType == .typeDirectory,
      (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
      (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700,
      let data = try? JSONEncoder().encode(report)
    else { return }
    let partial = directory.appendingPathComponent(replyName + ".partial")
    let descriptor = open(partial.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
    guard descriptor >= 0 else { return }
    let written = data.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
    close(descriptor)
    guard written == data.count else { return }
    rename(partial.path, reply.path)
  }
}

/// Carries a notification onto the main actor; it is only read there.
private struct UncheckedNotification: @unchecked Sendable {
  let value: Notification
}
