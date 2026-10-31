/// A command-line request handled without the menu bar interface.
public enum HeadlessCommand: Equatable, Sendable {
  case status(json: Bool, local: Bool)
  case watch(cycles: Int?, json: Bool, local: Bool)
  case probe(address: String, interface: String?, count: Int, json: Bool)
  case neighbors(json: Bool)
  case authorize
  case findAccessPoint(json: Bool)
  case accept(json: Bool)
  case dismiss
  case pause
  case resume
  case listProfiles(json: Bool)
  case setProfile(ProfileUpdate)
  case removeProfile(ssid: String)
  case history(hours: Int, json: Bool)
  case incidents(days: Int, json: Bool)
  case diagnose(hours: Int, json: Bool)
  case clearHistory
  case help

  public struct UsageError: Error, Equatable, CustomStringConvertible {
    public let description: String
  }

  public static let usage = """
    Usage: LinkWatch <command> [options]

    Inspect:
      diagnose [--hours N]   Answer "what's going on with my network?": the live verdict,
                             coverage and gaps, incidents with evidence, hourly history and
                             notes for the last N hours (default 24, up to 168).
      status [--local]       Show everything the menu bar panel shows. Reads the running app's
                             live state; --local builds a fresh view instead. Sends no probes.
      watch [--cycles N] [--local]
                             Print the state every 2 seconds. Follows the running app; with
                             --local, or when the app is not running, monitors headlessly
                             (probing only networks with a saved profile, like the app).
      history [--hours N]    Show stored history for the last N hours (default 24, up to 168):
                             hourly rollups in text, every minute summary with --json.
      neighbors              List cached ARP neighbours on the Wi-Fi interface and which one
                             matches the associated BSSID. Sends no traffic.
      probe ADDRESS [--interface NAME] [--count N]
                             Send N ICMP echo requests (default 3) over the Wi-Fi interface
                             or NAME. Use only for addresses you are allowed to probe.

    Act (the same actions as the menu bar panel and Settings window):
      accept                 Monitor this network, or update its profile, as suggested.
      dismiss                "Not now": hide the current suggestion in the running app.
      find-ap                Ping every address in a private Wi-Fi subnet of /22 or smaller
                             once, so the ARP cache can reveal the AP, then show the result.
                             Sends traffic; run it only on networks you are allowed to scan.
      pause | resume         Pause or resume monitoring in the running app.
      profile list           List saved profiles.
      profile set --ssid NAME [--ap ADDRESS] [--router ADDRESS]
                  [--difference MS] [--recovery-difference MS] [--slow MS]
                  [--recovery-slow MS] [--sustained SECONDS] [--recovery SECONDS]
                  [--internet on|off] [--bridge NAME | --no-bridge]
                             Create or change a profile; omitted values keep their current
                             setting. A new profile needs --ap and --router. --internet
                             also pings Cloudflare 1.1.1.1 and Google 8.8.8.8 (default on).
                             --bridge names the device between the AP and the router, used
                             in advice such as "Restart the TP-Link powerline adapters".
      profile remove NAME    Delete a profile; its network is no longer probed.
      history clear          Delete the stored week of history, as in Settings.
      incidents [--days N]   List problems in the last N days (default 7): when, how long,
                             the most likely cause and the evidence for each link.
      authorize              Report Location permission, which is granted from the app's
                             Settings window because macOS prompts only for the app.
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
    case "watch": command = try watch(&options, json: json)
    case "probe": return try probe(options, json: json)
    case "profile": return try profile(options, json: json)
    case "history": return try history(options, json: json)
    case "incidents": return try incidents(options, json: json)
    case "diagnose": return try diagnose(options, json: json)
    default:
      let local = take(flag: "--local", from: &options)
      guard let simple = simple(name, json: json, local: local) else { return nil }
      if local, simple != .status(json: json, local: true) {
        throw UsageError(description: "--local applies only to status and watch")
      }
      command = simple
    }
    try requireEmpty(options)
    return command
  }

  private static func simple(_ name: String, json: Bool, local: Bool) -> HeadlessCommand? {
    let commands: [String: HeadlessCommand] = [
      "status": .status(json: json, local: local), "neighbors": .neighbors(json: json),
      "authorize": .authorize, "find-ap": .findAccessPoint(json: json),
      "accept": .accept(json: json), "dismiss": .dismiss, "pause": .pause, "resume": .resume,
      "help": .help, "--help": .help, "-h": .help,
    ]
    return commands[name]
  }

  private static func watch(_ options: inout [String], json: Bool) throws(UsageError)
    -> HeadlessCommand
  {
    let local = take(flag: "--local", from: &options)
    let cycles = try take(count: "--cycles", from: &options)
    return .watch(cycles: cycles, json: json, local: local)
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

  private static func profile(_ arguments: [String], json: Bool) throws(UsageError)
    -> HeadlessCommand
  {
    var options = Array(arguments.dropFirst())
    switch arguments.first {
    case "list":
      try requireEmpty(options)
      return .listProfiles(json: json)
    case "remove":
      guard options.count == 1, let ssid = options.first else {
        throw UsageError(description: "profile remove needs exactly one network name")
      }
      return .removeProfile(ssid: ssid)
    case "set":
      let update = try ProfileUpdate(parsing: &options)
      try requireEmpty(options)
      return .setProfile(update)
    default:
      throw UsageError(description: "profile needs list, set or remove")
    }
  }

  private static func history(_ arguments: [String], json: Bool) throws(UsageError)
    -> HeadlessCommand
  {
    var options = arguments
    if options.first == "clear" {
      try requireEmpty(Array(options.dropFirst()))
      return .clearHistory
    }
    let hours = try take(count: "--hours", from: &options) ?? 24
    guard hours <= 168 else { throw UsageError(description: "--hours must be at most 168") }
    try requireEmpty(options)
    return .history(hours: hours, json: json)
  }

  private static func diagnose(_ arguments: [String], json: Bool) throws(UsageError)
    -> HeadlessCommand
  {
    var options = arguments
    let hours = try take(count: "--hours", from: &options) ?? 24
    guard hours <= 168 else { throw UsageError(description: "--hours must be at most 168") }
    try requireEmpty(options)
    return .diagnose(hours: hours, json: json)
  }

  private static func incidents(_ arguments: [String], json: Bool) throws(UsageError)
    -> HeadlessCommand
  {
    var options = arguments
    let days = try take(count: "--days", from: &options) ?? 7
    guard days <= 7 else { throw UsageError(description: "--days must be at most 7") }
    try requireEmpty(options)
    return .incidents(days: days, json: json)
  }

  private static func requireEmpty(_ options: [String]) throws(UsageError) {
    guard options.isEmpty else {
      throw UsageError(description: "unexpected arguments: \(options.joined(separator: " "))")
    }
  }

  private static func take(flag: String, from options: inout [String]) -> Bool {
    guard let index = options.firstIndex(of: flag) else { return false }
    options.remove(at: index)
    return true
  }

  static func take(value name: String, from options: inout [String]) throws(UsageError)
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

/// Requested changes to one profile; nil fields keep the current or default value.
public struct ProfileUpdate: Equatable, Sendable {
  public var ssid: String
  public var accessPoint: String?
  public var router: String?
  public var difference: Double?
  public var recoveryDifference: Double?
  public var slow: Double?
  public var recoverySlow: Double?
  public var sustainedSeconds: Double?
  public var recoverySeconds: Double?
  public var internetReferences: Switch?
  /// A new bridge name, or `.some(nil)` to remove it.
  public var bridgeName: String??

  public enum Switch: Equatable, Sendable {
    case enabled
    case disabled
  }

  init(parsing options: inout [String]) throws(HeadlessCommand.UsageError) {
    guard let ssid = try HeadlessCommand.take(value: "--ssid", from: &options) else {
      throw .init(description: "profile set needs --ssid NAME")
    }
    self.ssid = ssid
    accessPoint = try HeadlessCommand.take(value: "--ap", from: &options)
    router = try HeadlessCommand.take(value: "--router", from: &options)
    difference = try Self.number("--difference", from: &options)
    recoveryDifference = try Self.number("--recovery-difference", from: &options)
    slow = try Self.number("--slow", from: &options)
    recoverySlow = try Self.number("--recovery-slow", from: &options)
    sustainedSeconds = try Self.number("--sustained", from: &options)
    recoverySeconds = try Self.number("--recovery", from: &options)
    if let bridge = try HeadlessCommand.take(value: "--bridge", from: &options) {
      bridgeName = .some(bridge)
    } else if let index = options.firstIndex(of: "--no-bridge") {
      options.remove(at: index)
      bridgeName = .some(nil)
    }
    switch try HeadlessCommand.take(value: "--internet", from: &options) {
    case nil: internetReferences = nil
    case "on": internetReferences = .enabled
    case "off": internetReferences = .disabled
    default: throw .init(description: "--internet must be on or off")
    }
  }

  /// Merges the update into an existing profile, or creates one when both addresses are given.
  public func applied(to existing: NetworkProfile?) -> NetworkProfile? {
    var profile =
      existing
      ?? accessPoint.flatMap { accessPoint in
        router.map { NetworkProfile(ssid: ssid, accessPoint: accessPoint, router: $0) }
      }
    guard profile != nil else { return nil }
    if let accessPoint { profile?.accessPoint = accessPoint }
    if let router { profile?.router = router }
    if let thresholds = profile?.thresholds { profile?.thresholds = applied(to: thresholds) }
    if let internetReferences { profile?.internetReferences = internetReferences == .enabled }
    if let bridgeName { profile?.bridgeName = bridgeName }
    return profile
  }

  private func applied(to thresholds: Thresholds) -> Thresholds {
    var thresholds = thresholds
    if let difference { thresholds.difference = difference }
    if let recoveryDifference { thresholds.recoveryDifference = recoveryDifference }
    if let slow { thresholds.slow = slow }
    if let recoverySlow { thresholds.recoverySlow = recoverySlow }
    if let sustainedSeconds { thresholds.sustainedSeconds = sustainedSeconds }
    if let recoverySeconds { thresholds.recoverySeconds = recoverySeconds }
    return thresholds
  }

  private static func number(_ name: String, from options: inout [String])
    throws(HeadlessCommand.UsageError) -> Double?
  {
    guard let text = try HeadlessCommand.take(value: name, from: &options) else { return nil }
    guard let value = Double(text), value.isFinite, value > 0 else {
      throw .init(description: "\(name) must be a positive number")
    }
    return value
  }
}
