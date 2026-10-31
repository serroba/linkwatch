import AppKit
import Dispatch
import Foundation
import LinkWatchCore
import LinkWatchNetworking
import SwiftUI

@main
enum Entry {
  static func main() {
    let arguments = Array(CommandLine.arguments.dropFirst())
    do throws(HeadlessCommand.UsageError) {
      if let command = try HeadlessCommand.parse(arguments) {
        MainActor.assumeIsolated { Headless.start(command) }
      }
    } catch {
      Headless.write("LinkWatch: \(error)\n\n\(HeadlessCommand.usage)\n", to: .standardError)
      exit(64)
    }
    LinkWatchApp.main()
  }
}

/// Runs a command with the same environment and controller as the menu bar app.
@MainActor
enum Headless {
  static func start(_ command: HeadlessCommand) -> Never {
    Task { @MainActor in exit(await run(command)) }
    guard command == .authorize else { dispatchMain() }
    // CoreLocation only presents its prompt for a running application.
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    application.activate(ignoringOtherApps: true)
    application.run()
    exit(0)
  }

  nonisolated static func write(_ text: String, to handle: FileHandle = .standardOutput) {
    handle.write(Data(text.utf8))
  }

  private static func run(_ command: HeadlessCommand) async -> Int32 {
    switch command {
    case .help:
      write(HeadlessCommand.usage + "\n")
    case .status(let json):
      let monitor = Monitor()
      emit(StatusReport(controller: monitor.controller, now: uptime), json: json)
    case .watch(let cycles, let json):
      await watch(cycles: cycles, json: json)
    case .probe(let address, let interface, let count, let json):
      return await probe(address: address, interface: interface, count: count, json: json)
    case .neighbors(let json):
      emit(neighbors(), json: json)
    case .authorize:
      return await authorize()
    }
    return 0
  }

  private static var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

  private static func authorize() async -> Int32 {
    let environment = SystemEnvironment()
    if environment.isPermitted {
      write("Location permission is already granted.\n")
      return 0
    }
    if environment.isDenied {
      write(
        "Location permission is \(environment.authorizationDescription); macOS will not ask again. Enable LinkWatch in System Settings › Privacy & Security › Location Services.\n",
        to: .standardError)
      return 77
    }
    write("Requesting Location permission. Answer the macOS prompt within 60 seconds.\n")
    environment.requestAuthorization()
    for _ in 0..<120 {
      if environment.isPermitted {
        write("Location permission granted.\n")
        return 0
      }
      if environment.isDenied { break }
      try? await Task.sleep(for: .milliseconds(500))
    }
    write(
      "Location permission is \(environment.authorizationDescription). Enable LinkWatch in System Settings › Privacy & Security › Location Services, or use Allow Wi-Fi identification in the app's Settings.\n",
      to: .standardError)
    return 77
  }

  private static func watch(cycles: Int?, json: Bool) async {
    let monitor = Monitor()
    var completed = 0
    while cycles.map({ completed < $0 }) ?? true {
      let delay = await monitor.controller.cycle()
      completed += 1
      let report = StatusReport(controller: monitor.controller, now: uptime)
      if json {
        emit(report, json: true, compact: true)
      } else {
        write("— cycle \(completed) —\n\(report.text)\n")
      }
      if cycles.map({ completed < $0 }) ?? true { try? await Task.sleep(for: .seconds(delay)) }
    }
  }

  private static func probe(address: String, interface: String?, count: Int, json: Bool) async
    -> Int32
  {
    guard let interface = interface ?? SystemEnvironment().wifiInterfaceName else {
      write("LinkWatch: no Wi-Fi interface found; pass --interface NAME\n", to: .standardError)
      return 69
    }
    let probe = ICMPLatencyProbe()
    var report = ProbeReport(
      address: address, interface: interface, results: [], milliseconds: [], sent: count,
      received: 0)
    for index in 0..<count {
      let outcome = await probe.measure(address: address, interface: interface)
      switch outcome {
      case .success(let value):
        report.results.append(String(format: "%.2f ms", value))
        report.milliseconds.append(value)
      case .timeout: report.results.append("timeout")
      case .failure: report.results.append("failure")
      case .cancelled: report.results.append("cancelled")
      }
      if !json { write("\(address) via \(interface): \(report.results[index])\n") }
      if index + 1 < count { try? await Task.sleep(for: .milliseconds(500)) }
    }
    report.received = report.milliseconds.count
    if json {
      emit(report)
    } else {
      let sorted = report.milliseconds.sorted()
      let range =
        sorted.isEmpty
        ? ""
        : String(
          format: ", min %.2f / median %.2f / max %.2f ms", sorted[0], sorted[sorted.count / 2],
          sorted[sorted.count - 1])
      write("\(report.received)/\(report.sent) replies\(range)\n")
    }
    return report.received == 0 ? 1 : 0
  }

  private static func neighbors() -> NeighborReport {
    let monitor = Monitor()
    let network = monitor.controller.network
    let interface = network?.interface ?? monitor.environment.wifiInterfaceName
    let entries = NeighborTable.entries().filter { $0.interface == interface }
    return NeighborReport(
      interface: interface, bssid: network?.bssid,
      entries: entries.map { .init(address: $0.address, hardwareAddress: $0.hardwareAddress) },
      discovery: StatusReport(controller: monitor.controller, now: uptime).discovery,
      note: network == nil
        ? "Wi-Fi identity unavailable (Location permission missing or disconnected); BSSID matching skipped."
        : nil)
  }

  private static func emit(_ report: StatusReport, json: Bool, compact: Bool = false) {
    if json { emit(encodable: report, compact: compact) } else { write(report.text + "\n") }
  }

  private static func emit(_ report: NeighborReport, json: Bool) {
    if json { return emit(encodable: report, compact: false) }
    var lines = [
      "Interface:   \(report.interface ?? "none")", "BSSID:       \(report.bssid ?? "unavailable")",
    ]
    lines += report.entries.map { "  \($0.address)  \($0.hardwareAddress)" }
    if report.entries.isEmpty { lines.append("  (no cached neighbours)") }
    if let discovery = report.discovery {
      lines.append(
        "Match:       router \(discovery.router ?? "not detected") · AP \(discovery.accessPointAddress ?? discovery.accessPoint)"
      )
    }
    if let note = report.note { lines.append("Note:        \(note)") }
    write(lines.joined(separator: "\n") + "\n")
  }

  private static func emit(_ report: ProbeReport) {
    emit(encodable: report, compact: false)
  }

  private static func emit(encodable value: some Encodable, compact: Bool) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = compact ? [.sortedKeys] : [.sortedKeys, .prettyPrinted]
    guard let data = try? encoder.encode(value) else {
      write("LinkWatch: could not encode output\n", to: .standardError)
      return
    }
    write((String(bytes: data, encoding: .utf8) ?? "") + "\n")
  }
}

private struct ProbeReport: Codable {
  var address: String
  var interface: String
  var results: [String]
  var milliseconds: [Double]
  var sent: Int
  var received: Int
}

private struct NeighborReport: Codable {
  var interface: String?
  var bssid: String?
  var entries: [NeighborReportEntry]
  var discovery: StatusReport.Discovery?
  var note: String?
}

private struct NeighborReportEntry: Codable {
  var address: String
  var hardwareAddress: String
}
