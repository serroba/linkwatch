/// Parsers for commands that take their own arguments.
extension HeadlessCommand {
  static func probe(_ arguments: [String], json: Bool) throws(UsageError)
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

  static func profile(_ arguments: [String], json: Bool) throws(UsageError)
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

  static func history(_ arguments: [String], json: Bool) throws(UsageError)
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

  static func testDevice(_ arguments: [String]) throws(UsageError) -> HeadlessCommand {
    guard let device = AppEvent.markLabel(arguments.joined(separator: " ")) else {
      throw UsageError(description: "test-device needs a device name, such as \"desk\"")
    }
    return .testDevice(device)
  }

  static func restarted(_ arguments: [String]) -> HeadlessCommand {
    var options = arguments
    let wait = options.contains("--wait")
    options.removeAll { $0 == "--wait" }
    return .restarted(AppEvent.markLabel(options.joined(separator: " ")), wait: wait)
  }

  static func mark(_ arguments: [String]) throws(UsageError) -> HeadlessCommand {
    guard let label = AppEvent.markLabel(arguments.joined(separator: " ")) else {
      throw UsageError(description: "mark needs a short label, such as \"desk moved\"")
    }
    return .mark(label)
  }

  static func events(_ arguments: [String], json: Bool) throws(UsageError)
    -> HeadlessCommand
  {
    var options = arguments
    let hours = try take(count: "--hours", from: &options) ?? 24
    guard hours <= 168 else { throw UsageError(description: "--hours must be at most 168") }
    try requireEmpty(options)
    return .events(hours: hours, json: json)
  }

  static func export(_ arguments: [String]) throws(UsageError) -> HeadlessCommand {
    var options = arguments
    let redact = take(flag: "--redact", from: &options)
    let directory = try take(value: "--dir", from: &options)
    let days = try take(count: "--days", from: &options) ?? 7
    guard days <= 7 else { throw UsageError(description: "--days must be at most 7") }
    try requireEmpty(options)
    return .export(days: days, directory: directory, redact: redact)
  }

  static func openAtLogin(_ arguments: [String]) throws(UsageError) -> HeadlessCommand {
    switch arguments {
    case []: return .openAtLogin(nil)
    case ["on"]: return .openAtLogin(.enabled)
    case ["off"]: return .openAtLogin(.disabled)
    default: throw UsageError(description: "open-at-login takes on, off or nothing")
    }
  }

  static func diagnose(_ arguments: [String], json: Bool) throws(UsageError)
    -> HeadlessCommand
  {
    var options = arguments
    let hours = try take(count: "--hours", from: &options) ?? 24
    guard hours <= 168 else { throw UsageError(description: "--hours must be at most 168") }
    try requireEmpty(options)
    return .diagnose(hours: hours, json: json)
  }

  static func incidents(_ arguments: [String], json: Bool) throws(UsageError)
    -> HeadlessCommand
  {
    var options = arguments
    let days = try take(count: "--days", from: &options) ?? 7
    guard days <= 7 else { throw UsageError(description: "--days must be at most 7") }
    try requireEmpty(options)
    return .incidents(days: days, json: json)
  }
}
