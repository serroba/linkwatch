/// A command-line request handled without the menu bar interface.
public enum HeadlessCommand: Equatable, Sendable {
  case status(json: Bool)
  case watch(cycles: Int?, json: Bool)
  case probe(address: String, interface: String?, count: Int, json: Bool)
  case neighbors(json: Bool)
  case authorize
  case findAccessPoint(json: Bool)
  case help

  public struct UsageError: Error, Equatable, CustomStringConvertible {
    public let description: String
  }

  public static let usage = """
    Usage: LinkWatch <command> [options]

    Commands:
      status                 Show everything the menu bar app shows, once. Sends no probes.
      watch [--cycles N]     Run monitoring headlessly and print the state after every cycle.
                             Probes only a network with a saved profile, like the app.
      probe ADDRESS [--interface NAME] [--count N]
                             Send N ICMP echo requests (default 3) over the Wi-Fi interface
                             or NAME. Use only for addresses you are allowed to probe.
      neighbors              List cached ARP neighbours on the Wi-Fi interface and which one
                             matches the associated BSSID. Sends no traffic.
      find-ap                Ping every address in a private Wi-Fi subnet of /22 or smaller
                             once, so the ARP cache can reveal the AP, then show the result.
                             Sends traffic; run it only on networks you are allowed to scan.
      authorize              Ask macOS for the Location permission needed to read the Wi-Fi
                             name, and wait up to 60 seconds for an answer.
      help                   Show this help.

    Options:
      --json                 Print JSON (watch prints one JSON object per line).

    Without a command, LinkWatch starts the menu bar app.
    """

  /// Returns nil when the arguments do not start with a command, so the app interface launches.
  public static func parse(_ arguments: [String]) throws(UsageError) -> HeadlessCommand? {
    guard let name = arguments.first else { return nil }
    var options = Array(arguments.dropFirst())
    let json = take(flag: "--json", from: &options)
    let command: HeadlessCommand
    switch name {
    case "status": command = .status(json: json)
    case "neighbors": command = .neighbors(json: json)
    case "authorize": command = .authorize
    case "find-ap": command = .findAccessPoint(json: json)
    case "help", "--help", "-h": command = .help
    case "watch":
      let cycles = try take(count: "--cycles", from: &options)
      command = .watch(cycles: cycles, json: json)
    case "probe":
      return try probe(options, json: json)
    default:
      return nil
    }
    guard options.isEmpty else {
      throw UsageError(description: "unexpected arguments: \(options.joined(separator: " "))")
    }
    return command
  }

  private static func probe(_ arguments: [String], json: Bool) throws(UsageError)
    -> HeadlessCommand
  {
    var options = arguments
    let interface = try take(value: "--interface", from: &options)
    let count = try take(count: "--count", from: &options) ?? 3
    guard options.count == 1, let address = options.first else {
      throw UsageError(description: "probe needs exactly one IPv4 address")
    }
    guard let octets = NetworkProfile.octets(address), (1..<224).contains(octets[0]) else {
      throw UsageError(description: "\(address) is not a usable IPv4 address")
    }
    return .probe(address: address, interface: interface, count: count, json: json)
  }

  private static func take(flag: String, from options: inout [String]) -> Bool {
    guard let index = options.firstIndex(of: flag) else { return false }
    options.remove(at: index)
    return true
  }

  private static func take(value name: String, from options: inout [String]) throws(UsageError)
    -> String?
  {
    guard let index = options.firstIndex(of: name) else { return nil }
    guard index + 1 < options.count, !options[index + 1].hasPrefix("--") else {
      throw UsageError(description: "\(name) needs a value")
    }
    let value = options[index + 1]
    options.removeSubrange(index...(index + 1))
    return value
  }

  private static func take(count name: String, from options: inout [String]) throws(UsageError)
    -> Int?
  {
    guard let text = try take(value: name, from: &options) else { return nil }
    guard let value = Int(text), (1...10_000).contains(value) else {
      throw UsageError(description: "\(name) must be a whole number from 1 to 10000")
    }
    return value
  }
}
