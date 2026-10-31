public import Foundation

/// Something that changes what LinkWatch can measure, recorded so gaps and odd periods in
/// the history explain themselves.
public struct AppEvent: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable {
    case launched
    case quit
    case paused
    case resumed
    case asleep
    case awake
    case joinedWiFi
    case leftWiFi
    case roamed
    case permissionGranted
    case permissionMissing
    case monitoringStarted
    case monitoringStopped
    case verdictChanged
    case profileSaved
    case profileRemoved
    case historyCleared
    /// A person noted what they were doing, such as "desk moved", to correlate with the data.
    case marked
    /// A guided device test started, changed phase, finished or was cancelled.
    case deviceTest
  }

  /// Turns free text into a mark label: one line, trimmed, at most 60 characters.
  public static func markLabel(_ text: String) -> String? {
    let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty ? nil : String(trimmed.prefix(60))
  }

  public var time: Date
  public var kind: Kind
  public var detail: String?

  public init(time: Date, kind: Kind, detail: String? = nil) {
    self.time = time
    self.kind = kind
    self.detail = detail
  }

  /// For example "joinedWiFi: Home".
  public var summary: String { kind.rawValue + (detail.map { ": \($0)" } ?? "") }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(time, forKey: .time)
    try container.encode(kind, forKey: .kind)
    try container.encode(detail, forKey: .detail)
  }
}

/// Persists events on this Mac.
public protocol EventStore {
  func append(_ event: AppEvent) throws
  func prune(before date: Date) throws
}

/// Stores events as JSON Lines in a private file next to the history.
public struct FileEventStore: EventStore {
  private let lines: JSONLinesFile<AppEvent>

  public init(directory: URL) {
    lines = JSONLinesFile(file: directory.appendingPathComponent("events.jsonl"))
  }

  public func append(_ event: AppEvent) throws { try lines.append(event) }
  public func load(since date: Date) throws -> [AppEvent] {
    try lines.load().filter { $0.time >= date }
  }
  public func prune(before date: Date) throws { try lines.rewrite(with: load(since: date)) }
}

/// Reads events without writing, for processes other than the menu bar app.
public struct ReadOnlyEventStore: EventStore {
  private let store: FileEventStore

  public init(directory: URL) { store = FileEventStore(directory: directory) }

  public func append(_ event: AppEvent) throws {}
  public func load(since date: Date) throws -> [AppEvent] { try store.load(since: date) }
  public func prune(before date: Date) throws {}
}

/// The state whose changes are worth an event.
struct ObservedState: Equatable {
  var permitted = true
  var ssid: String?
  var bssid: String?
  var monitoring: String?
  var paused = false
  var sleeping = false
  var verdict = Verdict.allClear

  /// Events describing how `self` differs from `previous`, in a stable order.
  func events(since previous: ObservedState, reason: String) -> [(AppEvent.Kind, String?)] {
    var events: [(AppEvent.Kind, String?)] = []
    if permitted != previous.permitted {
      events.append((permitted ? .permissionGranted : .permissionMissing, "Location"))
    }
    if sleeping != previous.sleeping { events.append((sleeping ? .asleep : .awake, nil)) }
    if paused != previous.paused { events.append((paused ? .paused : .resumed, nil)) }
    events += wifiEvents(since: previous)
    if monitoring != previous.monitoring {
      if previous.monitoring != nil { events.append((.monitoringStopped, reason)) }
      if let monitoring { events.append((.monitoringStarted, monitoring)) }
    }
    if verdict != previous.verdict {
      events.append((.verdictChanged, "\(previous.verdict.rawValue) → \(verdict.rawValue)"))
    }
    return events
  }

  private func wifiEvents(since previous: ObservedState) -> [(AppEvent.Kind, String?)] {
    if ssid != previous.ssid {
      var events: [(AppEvent.Kind, String?)] = []
      if let old = previous.ssid, ssid == nil { events.append((.leftWiFi, old)) }
      if let ssid { events.append((.joinedWiFi, ssid + (bssid.map { " via \($0)" } ?? ""))) }
      return events
    }
    if bssid != previous.bssid, let bssid { return [(.roamed, bssid)] }
    return []
  }
}
