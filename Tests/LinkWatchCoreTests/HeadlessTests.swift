import Foundation
import Testing

@testable import LinkWatchCore

@Test func headlessCommandsParse() throws {
  #expect(try HeadlessCommand.parse([]) == nil)
  #expect(try HeadlessCommand.parse(["-NSDocumentRevisionsDebugMode", "YES"]) == nil)
  #expect(try HeadlessCommand.parse(["status"]) == .status(json: false, local: false))
  #expect(
    try HeadlessCommand.parse(["status", "--json", "--local"]) == .status(json: true, local: true))
  #expect(
    try HeadlessCommand.parse(["watch", "--cycles", "3", "--json"])
      == .watch(cycles: 3, json: true, local: false))
  #expect(
    try HeadlessCommand.parse(["watch", "--local"]) == .watch(cycles: nil, json: false, local: true)
  )
  #expect(
    try HeadlessCommand.parse(["probe", "192.0.2.1", "--interface", "en0", "--count", "2"])
      == .probe(address: "192.0.2.1", interface: "en0", count: 2, json: false))
  #expect(
    try HeadlessCommand.parse(["probe", "127.0.0.1"])
      == .probe(address: "127.0.0.1", interface: nil, count: 3, json: false))
  #expect(try HeadlessCommand.parse(["neighbors", "--json"]) == .neighbors(json: true))
  #expect(try HeadlessCommand.parse(["authorize"]) == .authorize)
  #expect(try HeadlessCommand.parse(["find-ap", "--json"]) == .findAccessPoint(json: true))
  #expect(try HeadlessCommand.parse(["accept"]) == .accept(json: false))
  #expect(try HeadlessCommand.parse(["dismiss"]) == .dismiss)
  #expect(try HeadlessCommand.parse(["pause"]) == .pause)
  #expect(try HeadlessCommand.parse(["resume"]) == .resume)
  #expect(try HeadlessCommand.parse(["--help"]) == .help)
}

@Test func profileCommandsParse() throws {
  #expect(try HeadlessCommand.parse(["profile", "list", "--json"]) == .listProfiles(json: true))
  #expect(try HeadlessCommand.parse(["profile", "remove", "Home"]) == .removeProfile(ssid: "Home"))
  let command = try HeadlessCommand.parse([
    "profile", "set", "--ssid", "Home Wi-Fi", "--ap", "192.0.2.2", "--router", "192.0.2.1",
    "--difference", "25", "--recovery", "8",
  ])
  guard case .setProfile(let update) = command else {
    Issue.record("Expected profile set")
    return
  }
  #expect(update.ssid == "Home Wi-Fi")
  #expect(update.accessPoint == "192.0.2.2")
  #expect(update.router == "192.0.2.1")
  #expect(update.difference == 25)
  #expect(update.recoverySeconds == 8)
  #expect(update.slow == nil)
}

@Test func headlessUsageErrors() {
  let invalid: [[String]] = [
    ["probe"], ["probe", "192.0.2.1", "192.0.2.2"], ["probe", "0.0.0.0"], ["probe", "224.0.0.1"],
    ["probe", "192.0.2.010"], ["probe", "192.0.2.1", "--count", "0"],
    ["probe", "192.0.2.1", "--interface"], ["watch", "--cycles", "many"], ["status", "extra"],
    ["find-ap", "x"], ["pause", "--local"], ["profile"], ["profile", "rename"],
    ["profile", "list", "extra"], ["profile", "remove"], ["profile", "remove", "a", "b"],
    ["profile", "set"], ["profile", "set", "--ssid", "Home", "--slow", "0"],
    ["profile", "set", "--ssid", "Home", "--difference", "fast"],
    ["profile", "set", "--ssid", "Home", "--unknown", "1"],
  ]
  for arguments in invalid {
    #expect(throws: HeadlessCommand.UsageError.self) { try HeadlessCommand.parse(arguments) }
  }
}

private func parsedUpdate(_ arguments: String...) throws -> ProfileUpdate {
  var options = ["--ssid", "Home"] + arguments
  return try ProfileUpdate(parsing: &options)
}

@Test func profileUpdatesMergeIntoExistingProfiles() throws {
  var update = try parsedUpdate()
  #expect(update.applied(to: nil) == nil)
  update = try parsedUpdate("--ap", "192.0.2.2")
  #expect(update.applied(to: nil) == nil)
  update = try parsedUpdate("--ap", "192.0.2.2", "--router", "192.0.2.1")
  let created = update.applied(to: nil)
  #expect(created?.ssid == "Home")
  #expect(created?.thresholds == Thresholds())

  var existing = NetworkProfile(ssid: "Home", accessPoint: "192.0.2.5", router: "192.0.2.6")
  existing.thresholds.slow = 50
  let tweak = try parsedUpdate("--difference", "30", "--sustained", "20")
  let changed = tweak.applied(to: existing)
  #expect(changed?.id == existing.id)
  #expect(changed?.accessPoint == "192.0.2.5")
  #expect(changed?.thresholds.slow == 50)
  #expect(changed?.thresholds.difference == 30)
  #expect(changed?.thresholds.sustainedSeconds == 20)
}

@Test func addressParsingRejectsAmbiguousForms() {
  #expect(NetworkProfile.octets("192.0.2.1") == [192, 0, 2, 1])
  #expect(NetworkProfile.octets("192.0.2.01") == nil)
  #expect(NetworkProfile.octets("192.0.2") == nil)
  #expect(NetworkProfile.octets("192.0.2.256") == nil)
  #expect(!NetworkProfile.validAddress("127.0.0.1"))
  #expect(!NetworkProfile.validAddress("255.255.255.255"))
}

@Test func historyCommandsParse() throws {
  #expect(try HeadlessCommand.parse(["history"]) == .history(hours: 24, json: false))
  #expect(
    try HeadlessCommand.parse(["history", "--hours", "168", "--json"])
      == .history(hours: 168, json: true))
  #expect(try HeadlessCommand.parse(["history", "clear"]) == .clearHistory)
  for invalid in [["history", "--hours", "169"], ["history", "clear", "now"], ["history", "x"]] {
    #expect(throws: HeadlessCommand.UsageError.self) { try HeadlessCommand.parse(invalid) }
  }
}
