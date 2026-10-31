import Foundation
import LinkWatchCore

/// The command-line side of the panel's update notice.
extension Headless {
  static func update(install: Bool, automatic: ProfileUpdate.Switch?) async -> Int32 {
    if let automatic {
      UpdateChecker.isEnabled = automatic == .enabled
      write("Daily update check: \(UpdateChecker.isEnabled ? "on" : "off")\n")
    }
    let updates = UpdateChecker()
    let current = UpdateChecker.currentVersion ?? "unknown"
    let available: AvailableUpdate?
    do {
      available = try await updates.check()
    } catch {
      write(
        "LinkWatch: could not reach GitHub: \(error.localizedDescription)\n", to: .standardError)
      return 69
    }
    guard let available else {
      write("LinkWatch \(current) is up to date.\n")
      return 0
    }
    write("LinkWatch \(available.version) is available (running \(current)): \(available.url)\n")
    guard install else { return 0 }
    guard updates.canInstall else {
      write(
        "This copy is not in an Applications folder, so it is not replaced. Install with "
          + "scripts/install.sh on the Mac that should run the release.\n", to: .standardError)
      return 1
    }
    guard updates.install() else {
      write("LinkWatch: \(updates.message ?? "the update could not start")\n", to: .standardError)
      return 1
    }
    write("Installing \(available.version); LinkWatch reopens in a moment.\n")
    return 0
  }
}
