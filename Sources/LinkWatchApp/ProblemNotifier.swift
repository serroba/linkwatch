import Foundation
import LinkWatchCore
import UserNotifications

/// Opt-in notifications for problems that last a few minutes.
///
/// Off until the person turns them on, which is also when macOS asks for permission.
@MainActor
final class ProblemNotifier {
  private static let enabledKey = "notifyProblems"
  /// Follows the verdict even while notifications are off, so turning them on during a
  /// problem does not restart its clock.
  private var alerts = ProblemAlerts()

  static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

  static var description: String { isEnabled ? "on" : "off" }

  /// Turns notifications on, asking macOS the first time, or off; returns whether they are on.
  @discardableResult
  static func set(_ enabled: Bool) async -> Bool {
    var granted = false
    if enabled {
      granted =
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [
          .alert, .sound,
        ])) ?? false
    }
    UserDefaults.standard.set(granted, forKey: enabledKey)
    return granted
  }

  func update(_ controller: MonitorController) {
    let notice = alerts.update(
      verdict: controller.verdict,
      monitoring: controller.light != .idle, advice: controller.advice,
      now: ProcessInfo.processInfo.systemUptime)
    guard let notice, Self.isEnabled else { return }
    let content = UNMutableNotificationContent()
    content.title = notice.title
    content.body = notice.body
    content.sound = .default
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
  }
}
