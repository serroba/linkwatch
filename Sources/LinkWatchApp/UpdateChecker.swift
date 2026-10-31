import AppKit
import Combine
import Foundation
import LinkWatchCore

/// Looks for a newer release at most once a day and installs it with the installer bundled
/// in this app, so no downloaded script is ever run.
@MainActor
final class UpdateChecker: ObservableObject {
  private static let enabledKey = "checkForUpdates"
  private static let lastCheckKey = "updateLastCheck"
  private static let availableKey = "updateAvailable"

  @Published private(set) var available: AvailableUpdate?
  @Published private(set) var message: String?

  static var currentVersion: String? {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
  }

  /// On unless the person turned it off.
  static var isEnabled: Bool {
    get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
  }

  init() {
    let stored = UserDefaults.standard.data(forKey: Self.availableKey).flatMap {
      try? JSONDecoder().decode(AvailableUpdate.self, from: $0)
    }
    // Forget a stored update once this version has caught up with it.
    available = stored.flatMap { update in
      UpdateCheck.update(
        current: Self.currentVersion,
        latest: LatestRelease(tagName: update.version, htmlURL: update.url))
    }
  }

  /// Whether this copy can replace itself: it lives in an Applications folder and carries
  /// the installer.
  var canInstall: Bool {
    UpdateCheck.canInstall(appPath: Bundle.main.bundlePath, home: NSHomeDirectory())
      && Bundle.main.path(forResource: "install", ofType: "sh") != nil
  }

  func checkIfDue() async {
    let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
    guard Self.isEnabled, UpdateCheck.isDue(lastCheck: last, now: Date()) else { return }
    _ = try? await check()
  }

  /// Asks GitHub for the latest release now; returns the update, or nil when up to date.
  func check() async throws -> AvailableUpdate? {
    guard let url = URL(string: UpdateCheck.latestReleaseURL) else { return nil }
    var request = URLRequest(url: url, timeoutInterval: 15)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue(
      "LinkWatch/\(Self.currentVersion ?? "unknown")", forHTTPHeaderField: "User-Agent")
    let session = URLSession(configuration: .ephemeral)
    let (data, response) = try await session.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw URLError(.badServerResponse)
    }
    let latest = try JSONDecoder().decode(LatestRelease.self, from: data)
    UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
    available = UpdateCheck.update(current: Self.currentVersion, latest: latest)
    UserDefaults.standard.set(
      available.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.availableKey)
    return available
  }

  /// Runs the bundled installer for the offered version into this app's folder.
  ///
  /// The installer verifies the download's checksum, quits LinkWatch, replaces it and reopens it.
  @discardableResult
  func install() -> Bool {
    guard canInstall, let available,
      let script = Bundle.main.path(forResource: "install", ofType: "sh")
    else { return false }
    let log = Monitor.supportDirectory.appendingPathComponent("update.log")
    FileManager.default.createFile(
      atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [
      script, "--version", available.version,
      "--dir", (Bundle.main.bundlePath as NSString).deletingLastPathComponent,
    ]
    if let handle = try? FileHandle(forWritingTo: log) {
      process.standardOutput = handle
      process.standardError = handle
    }
    do {
      try process.run()
    } catch {
      message = "The update could not start: \(error.localizedDescription)"
      return false
    }
    message = "Updating to \(available.version); LinkWatch reopens in a moment."
    return true
  }

  func openReleasePage() {
    if let url = available.flatMap({ URL(string: $0.url) }) { NSWorkspace.shared.open(url) }
  }
}
