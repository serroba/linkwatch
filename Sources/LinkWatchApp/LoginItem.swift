import Foundation
import ServiceManagement

/// Starts LinkWatch at login so monitoring resumes after a restart without anyone
/// opening it; otherwise a reboot leaves silent gaps in the history.
enum LoginItem {
  /// The person's choice; absent means the default, on.
  private static let wantedKey = "openAtLogin"

  /// A short description for status output.
  static var description: String {
    switch SMAppService.mainApp.status {
    case .enabled: "on"
    case .requiresApproval: "waiting for approval in System Settings › General › Login Items"
    case .notRegistered: "off"
    case .notFound: "unavailable"
    @unknown default: "unknown"
    }
  }

  static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

  static func set(_ enabled: Bool) throws {
    UserDefaults.standard.set(enabled, forKey: wantedKey)
    if enabled {
      try SMAppService.mainApp.register()
    } else {
      try SMAppService.mainApp.unregister()
    }
  }

  /// Registers this copy of the app at every launch while the person wants it, so a copy
  /// installed or moved later replaces an older registration.
  static func applyPreference() {
    let wanted = UserDefaults.standard.object(forKey: wantedKey) as? Bool ?? true
    guard wanted else { return }
    try? SMAppService.mainApp.register()
  }
}
