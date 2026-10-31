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
  case openAtLogin(ProfileUpdate.Switch?)
  case export(days: Int, directory: String?, redact: Bool)
  case events(hours: Int, json: Bool)
  case mark(String)
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
      events [--hours N]     App and system events (launches, sleep, Wi-Fi changes, permission
                             changes, pauses, verdict changes) for the last N hours (default
                             24, up to 168), which explain gaps and odd periods.
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
      mark LABEL             Note what you are doing now, such as "desk moved", so incidents
                             and reports show it next to the measurements.
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
      export [--days N] [--dir PATH] [--redact]
                             Write a shareable report folder (report.txt, report.json and
                             minutes.json) for the last N days (default 7) and print its path.
                             --redact replaces network names and local addresses.
      incidents [--days N]   List problems in the last N days (default 7): when, how long,
                             the most likely cause and the evidence for each link.
      open-at-login [on|off] Show or change whether LinkWatch starts at login, so monitoring
                             resumes after a restart.
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
    if let command = try withArguments(name, options, json: json) { return command }
    let command: HeadlessCommand
    if name == "watch" {
      command = try watch(&options, json: json)
    } else {
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

  /// Commands that parse their own arguments.
  private static func withArguments(_ name: String, _ options: [String], json: Bool)
    throws(UsageError) -> HeadlessCommand?
  {
    switch name {
    case "probe": try probe(options, json: json)
    case "profile": try profile(options, json: json)
    case "history": try history(options, json: json)
    case "incidents": try incidents(options, json: json)
    case "diagnose": try diagnose(options, json: json)
    case "open-at-login": try openAtLogin(options)
    case "export": try export(options)
    case "events": try events(options, json: json)
    case "mark": try mark(options)
    default: nil
    }
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

  static func requireEmpty(_ options: [String]) throws(UsageError) {
    guard options.isEmpty else {
      throw UsageError(description: "unexpected arguments: \(options.joined(separator: " "))")
    }
  }

  static func take(flag: String, from options: inout [String]) -> Bool {
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

  static func take(count name: String, from options: inout [String]) throws(UsageError)
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
