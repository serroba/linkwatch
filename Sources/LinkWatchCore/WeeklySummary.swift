public import Foundation

/// Which part of the connection a group of incidents points to.
public enum ProblemArea: String, Codable, CaseIterable, Sendable {
  case wifi
  case bridge
  case internet
  case busy
  case routerQuiet

  init?(_ verdict: Verdict) {
    switch verdict {
    case .accessPoint, .weakSignal, .accessPointSpikes: self = .wifi
    case .bridge, .bridgeSpikes, .routerUnreachable: self = .bridge
    case .internet, .internetSpikes: self = .internet
    case .busy: self = .busy
    case .routerSilent: self = .routerQuiet
    case .allClear: return nil
    }
  }

  func name(bridge: String?, hotspot: Bool) -> String {
    switch self {
    case .wifi: hotspot ? "the link to the phone" : "the Wi-Fi link"
    case .bridge: bridge.map { "the \($0)" } ?? "the link between the access point and the router"
    case .internet: hotspot ? "the phone's mobile connection" : "the internet provider"
    case .busy: "the Mac's own large transfers"
    case .routerQuiet: "the router not answering LinkWatch"
    }
  }
}

/// Incidents about one part of the connection.
public struct AreaSummary: Codable, Equatable, Sendable {
  public var area: ProblemArea
  /// The network with the most problem minutes in this area, for naming its devices.
  public var ssid: String
  public var incidents: Int
  public var problemMinutes: Int
  public var longestMinutes: Int
}

/// Problem minutes in one hour of the day, across all days.
public struct HourOfDay: Codable, Equatable, Sendable {
  public var hour: Int
  public var problemMinutes: Int
}

/// Typical latency while the Mac moved a lot of data compared with the rest of the time.
public struct LoadEffect: Codable, Equatable, Sendable {
  /// Minutes moving at least `heavyBytes`, about 4 Mbit/s.
  public static let heavyBytes: UInt64 = 30_000_000

  public var heavyMinutes: Int
  /// Median of minute medians: internet when probed, otherwise the router.
  public var heavyLatency: Double?
  public var quietLatency: Double?

  /// Extra latency heavy transfers add for everything else, when both sides were measured.
  public var addedLatency: Double? {
    guard let heavyLatency, let quietLatency else { return nil }
    return heavyLatency - quietLatency
  }

  init(_ minutes: [MinuteSummary]) {
    func latency(_ minute: MinuteSummary) -> Double? {
      minute.internet?.median ?? minute.router.median
    }
    let heavy = minutes.filter { ($0.received ?? 0) &+ ($0.sent ?? 0) >= Self.heavyBytes }
    let quiet = minutes.filter { ($0.received ?? 0) &+ ($0.sent ?? 0) < Self.heavyBytes }
    heavyMinutes = heavy.count
    heavyLatency = Self.median(heavy.compactMap(latency))
    quietLatency = Self.median(quiet.compactMap(latency))
  }

  private static func median(_ values: [Double]) -> Double? {
    let sorted = values.sorted()
    return sorted.isEmpty ? nil : sorted[sorted.count / 2]
  }
}

/// A week at a glance: which part of the connection caused problems, when, and whether
/// heavy use or restarts made a difference, to decide whether to move or replace equipment.
public struct WeeklySummary: Codable, Equatable, Sendable {
  public var days: Int
  public var monitoredMinutes: Int
  public var areas: [AreaSummary]
  /// Up to three hours of the day with the most problem minutes.
  public var busiestHours: [HourOfDay]
  public var load: LoadEffect
  public var restarts: [RestartEffect]

  public init(
    minutes: [MinuteSummary], profiles: [NetworkProfile], events: [AppEvent], days: Int,
    now: Date, calendar: Calendar = .current
  ) {
    let since = now.addingTimeInterval(-Double(days) * 86_400)
    let window = minutes.filter { $0.start >= since && $0.start <= now }
    self.days = days
    monitoredMinutes = window.count
    let incidents = IncidentTimeline.incidents(from: window, profiles: profiles)
    areas = Self.areas(incidents)
    // A router ignoring pings is not a connection problem (often a missing Local Network
    // permission), so it neither sets the busiest hours nor outweighs real causes.
    busiestHours = Self.hours(
      incidents.filter { ProblemArea($0.verdict) != .routerQuiet }, calendar: calendar)
    load = LoadEffect(window)
    restarts = RestartEffect.effects(
      events: events.filter { $0.time >= since && $0.time <= now }, minutes: window)
  }

  public var problemMinutes: Int { areas.map(\.problemMinutes).reduce(0, +) }

  /// Areas that affect the connection, most problem minutes first.
  var connectionAreas: [AreaSummary] { areas.filter { $0.area != .routerQuiet } }
  var connectionMinutes: Int { connectionAreas.map(\.problemMinutes).reduce(0, +) }

  private static func areas(_ incidents: [Incident]) -> [AreaSummary] {
    let grouped = Dictionary(grouping: incidents) { ProblemArea($0.verdict) }
    return grouped.compactMap { area, incidents -> AreaSummary? in
      guard let area else { return nil }
      let byNetwork = Dictionary(grouping: incidents, by: \.ssid).mapValues {
        $0.map(\.problemMinutes).reduce(0, +)
      }
      return AreaSummary(
        area: area, ssid: byNetwork.max { $0.value < $1.value }?.key ?? "",
        incidents: incidents.count, problemMinutes: incidents.map(\.problemMinutes).reduce(0, +),
        longestMinutes: incidents.map { Int($0.duration / 60) }.max() ?? 0)
    }.sorted { $0.problemMinutes > $1.problemMinutes }
  }

  private static func hours(_ incidents: [Incident], calendar: Calendar) -> [HourOfDay] {
    var counts = [Int](repeating: 0, count: 24)
    for incident in incidents {
      var minute = incident.start
      while minute < incident.end {
        counts[calendar.component(.hour, from: minute)] += 1
        minute = minute.addingTimeInterval(60)
      }
    }
    return counts.enumerated().filter { $0.element > 0 }
      .sorted { $0.element > $1.element || ($0.element == $1.element && $0.offset < $1.offset) }
      .prefix(3).map { HourOfDay(hour: $0.offset, problemMinutes: $0.element) }
  }
}
