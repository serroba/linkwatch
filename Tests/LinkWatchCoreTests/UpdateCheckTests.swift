import Foundation
import Testing

@testable import LinkWatchCore

private let page = "https://github.com/serroba/linkwatch/releases/tag/v0.6.0"

@Test func releaseVersionsCompareNumerically() throws {
  let parsed = try #require(ReleaseVersion("v0.10.0"))
  #expect(parsed.description == "0.10.0")
  #expect(try #require(ReleaseVersion("0.9.9")) < parsed)
  #expect(ReleaseVersion("0.5") == ReleaseVersion("0.5.0"))
  #expect(ReleaseVersion("0.5.0-3-gabc1234-dirty") == ReleaseVersion("0.5.0"))
  for invalid in ["", "v", "abc", "1..2", "1.2.3.4.5", "2756eee"] {
    #expect(ReleaseVersion(invalid) == nil)
  }
}

@Test func onlyNewerPublishedReleasesAreOffered() {
  let latest = LatestRelease(tagName: "v0.6.0", htmlURL: page)
  #expect(
    UpdateCheck.update(current: "0.5.0", latest: latest)
      == AvailableUpdate(version: "0.6.0", url: page))
  #expect(UpdateCheck.update(current: "0.6.0", latest: latest) == nil)
  #expect(UpdateCheck.update(current: "0.7.0", latest: latest) == nil)
  // A development build counts as its base release.
  #expect(UpdateCheck.update(current: "0.6.0-2-g1234567", latest: latest) == nil)
  #expect(UpdateCheck.update(current: nil, latest: latest) == nil)
  #expect(UpdateCheck.update(current: "2756eee", latest: latest) == nil)
  for unsafe in [
    LatestRelease(tagName: "v0.6.0", htmlURL: page, draft: true),
    LatestRelease(tagName: "v0.6.0", htmlURL: page, prerelease: true),
    LatestRelease(tagName: "v0.6.0", htmlURL: "https://example.com/linkwatch"),
  ] {
    #expect(UpdateCheck.update(current: "0.5.0", latest: unsafe) == nil)
  }
}

@Test func gitHubResponsesDecode() throws {
  let json = """
    {"tag_name": "v0.6.0", "html_url": "\(page)", "draft": false, "prerelease": false,
     "name": "LinkWatch 0.6.0", "assets": []}
    """
  #expect(
    try JSONDecoder().decode(LatestRelease.self, from: Data(json.utf8))
      == LatestRelease(tagName: "v0.6.0", htmlURL: page))
}

@Test func updateChecksRunAtMostDaily() {
  let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
  #expect(UpdateCheck.isDue(lastCheck: nil, now: now))
  #expect(!UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-3600), now: now))
  #expect(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-86_400), now: now))
  // A clock moved backwards does not postpone checks indefinitely.
  #expect(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(3600), now: now))
}

@Test func onlyInstalledCopiesUpdateThemselves() {
  #expect(UpdateCheck.canInstall(appPath: "/Applications/LinkWatch.app", home: "/Users/a"))
  #expect(
    UpdateCheck.canInstall(appPath: "/Users/a/Applications/LinkWatch.app", home: "/Users/a"))
  #expect(
    !UpdateCheck.canInstall(
      appPath: "/Users/a/projects/linkwatch/dist/LinkWatch.app", home: "/Users/a"))
}

@Test func updateCommandParses() throws {
  #expect(try HeadlessCommand.parse(["update"]) == .update(install: false, automatic: nil))
  #expect(
    try HeadlessCommand.parse(["update", "--install", "--auto", "off"])
      == .update(install: true, automatic: .disabled))
  #expect(throws: HeadlessCommand.UsageError.self) {
    try HeadlessCommand.parse(["update", "--auto", "sometimes"])
  }
  #expect(throws: HeadlessCommand.UsageError.self) { try HeadlessCommand.parse(["update", "now"]) }
}
