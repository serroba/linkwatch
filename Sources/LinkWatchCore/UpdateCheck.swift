public import Foundation

/// A release version such as `0.5.0`, compared numerically.
public struct ReleaseVersion: Comparable, CustomStringConvertible, Sendable {
  public let parts: [Int]

  /// Parses `v0.5.0`, `0.5.0` or a development build such as `0.5.0-3-gabc1234-dirty`, which
  /// counts as its base release.
  public init?(_ text: String) {
    let trimmed = text.hasPrefix("v") ? String(text.dropFirst()) : text
    let base = trimmed.split(separator: "-", maxSplits: 1).first.map(String.init) ?? ""
    let parts = base.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
    guard (1...4).contains(parts.count), parts.allSatisfy({ $0 != nil }) else { return nil }
    self.parts = parts.compactMap { $0 }
  }

  public var description: String { parts.map(String.init).joined(separator: ".") }

  public static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
    let count = max(lhs.parts.count, rhs.parts.count)
    for index in 0..<count {
      let left = index < lhs.parts.count ? lhs.parts[index] : 0
      let right = index < rhs.parts.count ? rhs.parts[index] : 0
      if left != right { return left < right }
    }
    return false
  }

  public static func == (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
    !(lhs < rhs) && !(rhs < lhs)
  }
}

/// The fields LinkWatch reads from GitHub's latest-release response.
public struct LatestRelease: Decodable, Equatable, Sendable {
  public var tagName: String
  public var htmlURL: String
  public var draft: Bool
  public var prerelease: Bool

  enum CodingKeys: String, CodingKey {
    case tagName = "tag_name"
    case htmlURL = "html_url"
    case draft
    case prerelease
  }

  public init(tagName: String, htmlURL: String, draft: Bool = false, prerelease: Bool = false) {
    self.tagName = tagName
    self.htmlURL = htmlURL
    self.draft = draft
    self.prerelease = prerelease
  }
}

/// A newer published release than the one running.
public struct AvailableUpdate: Codable, Equatable, Sendable {
  public var version: String
  /// The release page, for notes and manual downloads.
  public var url: String
}

/// Decides whether to check for updates and whether a release is an update.
public enum UpdateCheck {
  /// The public endpoint; requests carry no account or device information beyond what any
  /// HTTPS request reveals (the IP address and a User-Agent naming LinkWatch's version).
  public static let latestReleaseURL =
    "https://api.github.com/repos/serroba/linkwatch/releases/latest"
  /// At most one check a day.
  public static let interval: TimeInterval = 86_400

  public static func isDue(lastCheck: Date?, now: Date) -> Bool {
    guard let lastCheck else { return true }
    return now.timeIntervalSince(lastCheck) >= interval || lastCheck > now
  }

  /// The update to offer, or nil when the release is not newer, is a draft or pre-release,
  /// only links to an unexpected page, or either version cannot be read.
  public static func update(current: String?, latest: LatestRelease) -> AvailableUpdate? {
    guard !latest.draft, !latest.prerelease,
      latest.htmlURL.hasPrefix("https://github.com/serroba/linkwatch/releases/"),
      let running = current.flatMap(ReleaseVersion.init),
      let published = ReleaseVersion(latest.tagName), running < published
    else { return nil }
    return AvailableUpdate(version: published.description, url: latest.htmlURL)
  }

  /// Whether the app can update itself in place: only copies in an Applications folder, so
  /// development builds are never replaced by a release.
  public static func canInstall(appPath: String, home: String) -> Bool {
    let folder = (appPath as NSString).deletingLastPathComponent
    return folder == "/Applications"
      || folder == (home as NSString).appendingPathComponent("Applications")
  }
}
