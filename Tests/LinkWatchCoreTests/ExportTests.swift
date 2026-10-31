import Foundation
import Testing

@testable import LinkWatchCore

@MainActor
private func exported(ssid: String, redact: Bool) async -> ExportedReport {
  var profile = homeProfile
  profile.ssid = ssid
  profile.internetReferences = true
  let harness = Harness(profiles: [profile])
  harness.environment.network = NetworkIdentity(
    ssid: ssid, bssid: "00:00:5e:00:53:01", interface: "en0")
  harness.environment.router = "192.0.2.1"
  harness.controller.networkChanged()
  for _ in 0..<31 { _ = await harness.cycle() }
  harness.controller.flushHistory()
  let status = StatusReport(controller: harness.controller, now: harness.clock.now)
  let now = harness.clock.date
  let report = DiagnoseReport(
    status: status, appRunning: true, minutes: harness.history.saved, profiles: [profile],
    hours: 1, now: now, primaryInterface: "en0", appVersion: "0.3.0")
  return ExportedReport(
    report: report, minutes: harness.history.saved, bridgeNames: [ssid: "TP-Link"],
    redact: redact)
}

private func text(_ report: ExportedReport, _ name: String) -> String {
  (String(bytes: report.files[name] ?? Data(), encoding: .utf8) ?? "")
}

@MainActor
@Test func exportContainsReadableAndMachineReports() async throws {
  let report = await exported(ssid: "Home", redact: false)
  #expect(Set(report.files.keys) == ["report.txt", "report.json", "minutes.json"])
  #expect(report.folderName.hasPrefix("LinkWatch report "))
  #expect(!report.folderName.contains(":"))
  let readable = text(report, "report.txt")
  #expect(readable.hasPrefix("This report contains the network name and local addresses."))
  #expect(readable.contains("LinkWatch 0.3.0 diagnosis"))
  #expect(readable.contains("192.0.2.2"))
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .iso8601
  let minutes = try decoder.decode(
    [MinuteSummary].self, from: report.files["minutes.json"] ?? Data())
  #expect(minutes.count == 2)
  let diagnosis = try decoder.decode(
    DiagnoseReport.self, from: report.files["report.json"] ?? Data())
  #expect(diagnosis.appVersion == "0.3.0")
}

@MainActor
@Test func redactionReplacesNamesAddressesAndDevicesConsistently() async {
  let report = await exported(ssid: #"Casa "Wi/Fi" 192.0.2.9"#, redact: true)
  for name in ["report.txt", "report.json", "minutes.json"] {
    let content = text(report, name)
    #expect(!content.contains("Casa"), "network name leaked in \(name)")
    #expect(!content.contains("192.0.2."), "local address leaked in \(name)")
    #expect(!content.contains("00:00:5e:00:53:01"), "hardware address leaked in \(name)")
  }
  let readable = text(report, "report.txt")
  #expect(readable.hasPrefix("Network names, local addresses and hardware addresses are replaced"))
  #expect(readable.contains("network-1"))
  #expect(readable.contains("BSSID device-1"))
  #expect(readable.contains("Cloudflare"))
  let json = text(report, "report.json")
  #expect(json.contains("\"1.1.1.1\""))
  #expect(json.contains("\"8.8.8.8\""))
  #expect(json.contains("\"accessPoint\" : \"address-"))
}

@Test func redactionNumbersEachValueOnce() {
  let redactor = Redactor(replacing: [])
  let result = redactor.apply("10.0.0.1 then 10.0.0.2, again 10.0.0.1 and 1.1.1.1; v0.3.0")
  #expect(result == "address-1 then address-2, again address-1 and 1.1.1.1; v0.3.0")
}

@MainActor
@Test func exportWritesAPrivateFolder() async throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("LinkWatchExport-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: directory) }
  let report = await exported(ssid: "Home", redact: false)
  let folder = try report.write(into: directory)
  #expect(
    try Data(contentsOf: folder.appendingPathComponent("report.txt")) == report.files["report.txt"])
  let attributes = try FileManager.default.attributesOfItem(atPath: folder.path)
  #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
  let file = try FileManager.default.attributesOfItem(
    atPath: folder.appendingPathComponent("report.txt").path)
  #expect((file[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test func exportCommandParses() throws {
  #expect(try HeadlessCommand.parse(["export"]) == .export(days: 7, directory: nil, redact: false))
  #expect(
    try HeadlessCommand.parse(["export", "--days", "2", "--dir", "~/Desktop", "--redact"])
      == .export(days: 2, directory: "~/Desktop", redact: true))
  #expect(throws: HeadlessCommand.UsageError.self) {
    try HeadlessCommand.parse(["export", "--days", "9"])
  }
}
