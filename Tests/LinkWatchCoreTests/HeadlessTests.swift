import Foundation
import Testing

@testable import LinkWatchCore

@Test func headlessCommandsParse() throws {
  #expect(try HeadlessCommand.parse([]) == nil)
  #expect(try HeadlessCommand.parse(["-NSDocumentRevisionsDebugMode", "YES"]) == nil)
  #expect(try HeadlessCommand.parse(["status"]) == .status(json: false))
  #expect(try HeadlessCommand.parse(["status", "--json"]) == .status(json: true))
  #expect(
    try HeadlessCommand.parse(["watch", "--cycles", "3", "--json"]) == .watch(cycles: 3, json: true)
  )
  #expect(try HeadlessCommand.parse(["watch"]) == .watch(cycles: nil, json: false))
  #expect(
    try HeadlessCommand.parse(["probe", "192.0.2.1", "--interface", "en0", "--count", "2"])
      == .probe(address: "192.0.2.1", interface: "en0", count: 2, json: false))
  #expect(
    try HeadlessCommand.parse(["probe", "127.0.0.1"])
      == .probe(address: "127.0.0.1", interface: nil, count: 3, json: false))
  #expect(try HeadlessCommand.parse(["neighbors", "--json"]) == .neighbors(json: true))
  #expect(try HeadlessCommand.parse(["authorize"]) == .authorize)
  #expect(try HeadlessCommand.parse(["--help"]) == .help)
}

@Test func headlessUsageErrors() {
  let invalid: [[String]] = [
    ["probe"], ["probe", "192.0.2.1", "192.0.2.2"], ["probe", "0.0.0.0"], ["probe", "224.0.0.1"],
    ["probe", "192.0.2.010"], ["probe", "192.0.2.1", "--count", "0"],
    ["probe", "192.0.2.1", "--interface"], ["watch", "--cycles", "many"], ["status", "extra"],
  ]
  for arguments in invalid {
    #expect(throws: HeadlessCommand.UsageError.self) { try HeadlessCommand.parse(arguments) }
  }
}

@Test func addressParsingRejectsAmbiguousForms() {
  #expect(NetworkProfile.octets("192.0.2.1") == [192, 0, 2, 1])
  #expect(NetworkProfile.octets("192.0.2.01") == nil)
  #expect(NetworkProfile.octets("192.0.2") == nil)
  #expect(NetworkProfile.octets("192.0.2.256") == nil)
  #expect(!NetworkProfile.validAddress("127.0.0.1"))
  #expect(!NetworkProfile.validAddress("255.255.255.255"))
}
