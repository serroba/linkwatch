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
      Headless.finish(64)
    }
    LinkWatchApp.main()
  }
}

/// Runs a command with the same environment and controller as the menu bar app.
@MainActor
enum Headless {
  static func start(_ command: HeadlessCommand) -> Never {
    record("pid", String(getpid()))
    Task { @MainActor in finish(await run(command)) }
    dispatchMain()
  }

  /// Exits, first recording the status for `scripts/linkwatch`, which launches through
  /// LaunchServices and so cannot read the exit code directly.
  nonisolated static func finish(_ status: Int32) -> Never {
    record("status", String(status))
    exit(status)
  }

  /// Writes a value into the wrapper's private run directory when one is provided.
  nonisolated private static func record(_ name: String, _ value: String) {
    guard let directory = ProcessInfo.processInfo.environment["LINKWATCH_RUN_DIR"] else { return }
    try? Data(value.utf8).write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
  }

  nonisolated static func write(_ text: String, to handle: FileHandle = .standardOutput) {
    handle.write(Data(text.utf8))
  }

  private static func run(_ command: HeadlessCommand) async -> Int32 {
    switch command {
    case .help:
      write(HeadlessCommand.usage + "\n")
      return 0
    case .status(let json, let local):
      return await status(json: json, local: local)
    case .watch(let cycles, let json, let local):
      await watch(cycles: cycles, json: json, local: local)
      return 0
    case .probe(let address, let interface, let count, let json):
      return await probe(address: address, interface: interface, count: count, json: json)
    case .neighbors(let json):
      emit(await neighbors(), json: json)
      return 0
    default:
      return await act(command)
    }
  }

  static func status(json: Bool, local: Bool) async -> Int32 {
    if !local, let live = await AppControl.liveStatus() {
      emit(live, json: json)
      return 0
    }
    if !local && !json {
      write("(The menu bar app is not running; showing a fresh local view.)\n", to: .standardError)
    }
    let monitor = await readyMonitor()
    emit(StatusReport(controller: monitor.controller, now: uptime), json: json)
    return 0
  }

  /// CoreLocation reports "not determined" until locationd answers, so wait up to a second
  /// for a decision before reading the Wi-Fi identity.
  static func readyMonitor() async -> Monitor {
    let monitor = Monitor()
    for _ in 0..<20 where monitor.environment.authorizationDescription == "not determined" {
      try? await Task.sleep(for: .milliseconds(50))
    }
    monitor.controller.networkChanged()
    return monitor
  }

  static var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

  private static func watch(cycles: Int?, json: Bool, local: Bool) async {
    if !local, await AppControl.liveStatus() != nil {
      await follow(cycles: cycles, json: json)
      return
    }
    let monitor = await readyMonitor()
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

  /// Prints the running app's live state every two seconds without probing anything itself.
  private static func follow(cycles: Int?, json: Bool) async {
    var completed = 0
    while cycles.map({ completed < $0 }) ?? true {
      guard let report = await AppControl.liveStatus() else {
        write("LinkWatch: the menu bar app stopped responding.\n", to: .standardError)
        return
      }
      completed += 1
      if json {
        emit(report, json: true, compact: true)
      } else {
        write("— update \(completed) —\n\(report.text)\n")
      }
      if cycles.map({ completed < $0 }) ?? true { try? await Task.sleep(for: .seconds(2)) }
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

  private static func neighbors() async -> NeighborReport {
    let monitor = await readyMonitor()
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

  static func emit(_ report: StatusReport, json: Bool, compact: Bool = false) {
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

  static func emit(encodable value: some Encodable, compact: Bool) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
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
