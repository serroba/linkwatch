public import Foundation

/// Everything the menu bar app shows, as plain data for headless diagnosis.
public struct StatusReport: Codable, Equatable, Sendable {
  public struct Latency: Codable, Equatable, Sendable {
    public var accessPoint: Double?
    public var router: Double?
    public var routerMinusAccessPoint: Double?
    public var accessPointLoss: Double
    public var routerLoss: Double
  }

  public struct HistoryPoint: Codable, Equatable, Sendable {
    public var elapsed: Double
    public var accessPoint: Double?
    public var router: Double?
  }

  public struct Discovery: Codable, Equatable, Sendable {
    public var router: String?
    /// One of `found`, `router` or `unknown`.
    public var accessPoint: String
    public var accessPointAddress: String?
  }

  public struct Suggestion: Codable, Equatable, Sendable {
    /// Either `monitor` for a new network or `update` for changed addresses.
    public var kind: String
    public var ready: Bool
    public var current: NetworkProfile?
    public var proposed: NetworkProfile?
  }

  public var state: DisplayState
  public var health: String
  public var reason: String
  public var permitted: Bool
  public var wifi: WiFiState
  public var paused: Bool
  public var sleeping: Bool
  public var network: NetworkIdentity?
  public var profile: NetworkProfile?
  public var latency: Latency
  public var alertSeconds: Double?
  public var evaluatingSeconds: Double?
  public var samples: Int
  public var historyFailures: Int
  public var history: [HistoryPoint]
  public var discovery: Discovery?
  public var suggestion: Suggestion?
  public var profiles: [NetworkProfile]
  public var storageError: String?

  @MainActor
  public init(controller: MonitorController, now: TimeInterval) {
    let window = controller.session.window
    state = controller.displayState
    health = Self.describe(window.health)
    reason = controller.reason
    permitted = controller.isPermitted
    wifi = controller.wifiState
    paused = controller.paused
    sleeping = controller.sleeping
    network = controller.network
    profile = controller.session.profile
    let accessPoint = controller.accessPointLatency
    let router = controller.routerLatency
    latency = Latency(
      accessPoint: accessPoint, router: router,
      routerMinusAccessPoint: accessPoint.flatMap { value in router.map { $0 - value } },
      accessPointLoss: window.accessPointLoss, routerLoss: window.routerLoss)
    let alerting = profile != nil && !window.samples.isEmpty && window.health != .healthy
    alertSeconds = alerting ? now - controller.healthSince : nil
    evaluatingSeconds = window.pendingSince.flatMap { since in
      window.samples.last.map { $0.elapsed - since }
    }
    samples = window.samples.count
    history = window.history.map {
      HistoryPoint(
        elapsed: $0.elapsed, accessPoint: $0.accessPoint.latency, router: $0.router.latency)
    }
    historyFailures = history.filter { $0.accessPoint == nil || $0.router == nil }.count
    discovery = controller.discovery.map(Self.describe)
    suggestion = controller.suggestion.map(Self.describe)
    profiles = controller.profiles
    storageError = controller.storageError
  }

  private static func describe(_ health: Health) -> String {
    switch health {
    case .healthy: "healthy"
    case .routerSlower: "routerSlower"
    case .bothSlow: "bothSlow"
    case .unreachable(let accessPoint, let router):
      "unreachable("
        + [accessPoint ? "accessPoint" : nil, router ? "router" : nil]
        .compactMap(\.self).joined(separator: ",") + ")"
    }
  }

  private static func describe(_ discovery: NetworkDiscovery) -> Discovery {
    switch discovery.accessPoint {
    case .found(let address):
      Discovery(router: discovery.router, accessPoint: "found", accessPointAddress: address)
    case .router: Discovery(router: discovery.router, accessPoint: "router")
    case .unknown: Discovery(router: discovery.router, accessPoint: "unknown")
    }
  }

  private static func describe(_ suggestion: NetworkSuggestion) -> Suggestion {
    switch suggestion {
    case .monitor(let discovery):
      let proposed = discovery.proposedProfile
      return Suggestion(kind: "monitor", ready: proposed != nil, proposed: proposed)
    case .update(let current, let proposed):
      return Suggestion(kind: "update", ready: true, current: current, proposed: proposed)
    }
  }
}

extension StatusReport {
  /// A human-readable summary; addresses are local network details, so share it with care.
  public var text: String {
    var lines = [
      "State:       \(state.rawValue) (\(health)) — \(reason)",
      "Permission:  \(permitted ? "granted" : "missing")"
        + (paused ? " · paused" : "") + (sleeping ? " · sleeping" : ""),
      "Wi-Fi:       authorization \(wifi.authorization) · interface \(wifi.interface ?? "none") · "
        + (wifi.poweredOn ? "on" : "off") + " · SSID \(wifi.ssidVisible ? "visible" : "hidden")"
        + " · BSSID \(wifi.bssidVisible ? "visible" : "hidden")",
      "Network:     "
        + (network.map { "\($0.ssid) · BSSID \($0.bssid) · \($0.interface)" } ?? "unavailable"),
      "Profile:     "
        + (profile.map { "AP \($0.accessPoint) · Router \($0.router)" } ?? "none selected"),
      "Latency:     AP \(Self.milliseconds(latency.accessPoint)) · Router \(Self.milliseconds(latency.router))"
        + (latency.routerMinusAccessPoint.map { String(format: " · Router − AP %+.1f ms", $0) }
          ?? ""),
      String(
        format: "Loss:        AP %.0f%% · Router %.0f%% over %d samples",
        latency.accessPointLoss * 100, latency.routerLoss * 100, samples),
      "Alert:       "
        + (alertSeconds.map { "active for \(Int($0)) s" }
          ?? evaluatingSeconds.map { "evaluating for \(Int($0)) s" } ?? "none"),
      "History:     \(history.count) pairs, \(historyFailures) with a failed probe",
      "Discovery:   " + (discovery.map(Self.summary) ?? "not run"),
      "Suggestion:  " + (suggestion.map(Self.summary) ?? "none"),
      "Profiles:    \(profiles.count) saved"
        + profiles.map { "\n  - \($0.ssid): AP \($0.accessPoint) · Router \($0.router)" }.joined(),
    ]
    if let storageError { lines.append("Storage:     \(storageError)") }
    return lines.joined(separator: "\n")
  }

  private static func milliseconds(_ value: Double?) -> String {
    value.map { String(format: "%.1f ms", $0) } ?? "—"
  }

  private static func summary(_ discovery: Discovery) -> String {
    let accessPoint =
      switch discovery.accessPoint {
      case "found": "AP \(discovery.accessPointAddress ?? "?")"
      case "router": "AP is the router itself"
      default: "AP not in ARP cache"
      }
    return "router \(discovery.router ?? "not detected") · \(accessPoint)"
  }

  private static func summary(_ suggestion: Suggestion) -> String {
    let target = suggestion.proposed.map { " (AP \($0.accessPoint) · Router \($0.router))" } ?? ""
    switch suggestion.kind {
    case "monitor":
      return (suggestion.ready ? "monitor this network" : "needs manual setup") + target
    default: return "update profile" + target
    }
  }
}

// Encode optionals as explicit nulls so JSON always lists every field.

extension StatusReport {
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(state, forKey: .state)
    try container.encode(health, forKey: .health)
    try container.encode(reason, forKey: .reason)
    try container.encode(permitted, forKey: .permitted)
    try container.encode(wifi, forKey: .wifi)
    try container.encode(paused, forKey: .paused)
    try container.encode(sleeping, forKey: .sleeping)
    try container.encode(network, forKey: .network)
    try container.encode(profile, forKey: .profile)
    try container.encode(latency, forKey: .latency)
    try container.encode(alertSeconds, forKey: .alertSeconds)
    try container.encode(evaluatingSeconds, forKey: .evaluatingSeconds)
    try container.encode(samples, forKey: .samples)
    try container.encode(historyFailures, forKey: .historyFailures)
    try container.encode(history, forKey: .history)
    try container.encode(discovery, forKey: .discovery)
    try container.encode(suggestion, forKey: .suggestion)
    try container.encode(profiles, forKey: .profiles)
    try container.encode(storageError, forKey: .storageError)
  }
}

extension StatusReport.Latency {
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(accessPoint, forKey: .accessPoint)
    try container.encode(router, forKey: .router)
    try container.encode(routerMinusAccessPoint, forKey: .routerMinusAccessPoint)
    try container.encode(accessPointLoss, forKey: .accessPointLoss)
    try container.encode(routerLoss, forKey: .routerLoss)
  }
}

extension StatusReport.HistoryPoint {
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(elapsed, forKey: .elapsed)
    try container.encode(accessPoint, forKey: .accessPoint)
    try container.encode(router, forKey: .router)
  }
}

extension StatusReport.Discovery {
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(router, forKey: .router)
    try container.encode(accessPoint, forKey: .accessPoint)
    try container.encode(accessPointAddress, forKey: .accessPointAddress)
  }
}

extension StatusReport.Suggestion {
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(kind, forKey: .kind)
    try container.encode(ready, forKey: .ready)
    try container.encode(current, forKey: .current)
    try container.encode(proposed, forKey: .proposed)
  }
}
