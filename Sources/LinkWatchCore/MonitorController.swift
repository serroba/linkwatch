public import Foundation
public import Observation

/// Sends one latency probe to an address over a named interface.
public protocol LatencyProbe: Sendable {
  func measure(address: String, interface: String) async -> ProbeOutcome
}

/// Raw Wi-Fi facts behind the network identity, for diagnosing why it is unavailable.
public struct WiFiState: Codable, Equatable, Sendable {
  public var authorization: String
  public var interface: String?
  public var poweredOn: Bool
  public var ssidVisible: Bool
  public var bssidVisible: Bool

  public init(
    authorization: String, interface: String?, poweredOn: Bool, ssidVisible: Bool,
    bssidVisible: Bool
  ) {
    self.authorization = authorization
    self.interface = interface
    self.poweredOn = poweredOn
    self.ssidVisible = ssidVisible
    self.bssidVisible = bssidVisible
  }
}

/// An interface's IPv4 address and netmask.
public struct InterfaceAddress: Equatable, Sendable {
  public let address: String
  public let netmask: String

  public init(address: String, netmask: String) {
    self.address = address
    self.netmask = netmask
  }
}

/// Progress of an explicitly requested access point search.
public enum AccessPointSearch: Equatable, Sendable {
  case idle
  case searching(hosts: Int)
  case finished(String)
}

/// Reports permission, the current Wi-Fi network and passive routing facts.
@MainActor
public protocol NetworkEnvironment: AnyObject {
  var isPermitted: Bool { get }
  var wifiState: WiFiState { get }
  func currentNetwork() -> NetworkIdentity?
  /// The IPv4 router assigned to this interface's network service, or nil when ambiguous.
  func defaultRouter(for interface: String) -> String?
  /// Existing ARP cache entries; implementations must not send traffic to populate it.
  func neighbors() -> [NeighborEntry]
  func interfaceAddress(_ interface: String) -> InterfaceAddress?
}

/// Persists approved network profiles on this Mac.
public protocol ProfileStore {
  /// Returns nil when nothing has been saved yet.
  func load() throws -> [NetworkProfile]?
  func save(_ profiles: [NetworkProfile]) throws
}

/// A setup change offered to the user; nothing is probed or saved until it is accepted.
public enum NetworkSuggestion: Equatable, Sendable {
  /// The current Wi-Fi network has no profile.
  case monitor(NetworkDiscovery)
  /// Discovered addresses differ from the saved profile.
  case update(current: NetworkProfile, proposed: NetworkProfile)
}

/// The overall state shown in the menu bar.
public enum DisplayState: String, Codable, Equatable, Sendable {
  case idle
  case healthy
  case routerSlower
  case bothSlow
  case unreachable
}

/// Coordinates profile selection, paired probes and lifecycle invalidation.
@MainActor
@Observable
public final class MonitorController {
  public private(set) var session = MonitoringSession()
  public private(set) var profiles: [NetworkProfile] = []
  public private(set) var network: NetworkIdentity?
  public private(set) var reason = "Choose a Wi-Fi network in Settings"
  public private(set) var storageError: String?
  public private(set) var healthSince: TimeInterval
  public var paused = false {
    didSet { refresh() }
  }
  public private(set) var sleeping = false
  public private(set) var discovery: NetworkDiscovery?
  public private(set) var suggestion: NetworkSuggestion?
  public private(set) var accessPointSearch = AccessPointSearch.idle

  @ObservationIgnored private let environment: any NetworkEnvironment
  @ObservationIgnored private let probe: any LatencyProbe
  @ObservationIgnored private let store: any ProfileStore
  @ObservationIgnored private let uptime: @MainActor () -> TimeInterval
  @ObservationIgnored private var inFlight: Task<ProbePair, Never>?
  @ObservationIgnored private var dismissed: Set<String> = []
  @ObservationIgnored private var needsDiscovery = true

  public static let interval: TimeInterval = 2

  public init(
    environment: any NetworkEnvironment, probe: any LatencyProbe, store: any ProfileStore,
    uptime: @escaping @MainActor () -> TimeInterval
  ) {
    self.environment = environment
    self.probe = probe
    self.store = store
    self.uptime = uptime
    healthSince = uptime()
    do {
      if let saved = try store.load() {
        guard saved.allSatisfy(\.isValid), Set(saved.map(\.ssid)).count == saved.count else {
          throw CocoaError(.coderReadCorrupt)
        }
        profiles = saved
      }
    } catch {
      storageError =
        "Saved profiles could not be read. Monitoring is paused until you save a profile."
    }
    refresh()
  }

  public var isPermitted: Bool { environment.isPermitted }
  public var wifiState: WiFiState { environment.wifiState }

  public var accessPointLatency: Double? {
    guard session.window.samples.last?.accessPoint.latency != nil else { return nil }
    return session.window.accessPointMedian
  }

  public var routerLatency: Double? {
    guard session.window.samples.last?.router.latency != nil else { return nil }
    return session.window.routerMedian
  }

  public var displayState: DisplayState {
    guard session.profile != nil, !session.window.samples.isEmpty else { return .idle }
    switch session.window.health {
    case .healthy: return .healthy
    case .routerSlower: return .routerSlower
    case .bothSlow: return .bothSlow
    case .unreachable: return .unreachable
    }
  }

  /// Saves a valid profile, replacing any profile with the same ID or SSID.
  @discardableResult
  public func save(_ profile: NetworkProfile) -> Bool {
    guard profile.isValid else { return false }
    var updated = profiles.filter { $0.id != profile.id && $0.ssid != profile.ssid }
    updated.append(profile)
    return persist(updated)
  }

  public func remove(_ profile: NetworkProfile) {
    persist(profiles.filter { $0.id != profile.id })
  }

  public func setSleeping(_ sleeping: Bool) {
    self.sleeping = sleeping
    networkChanged()
  }

  /// Discards in-flight and recorded measurements after a network change.
  public func networkChanged() {
    invalidate()
    needsDiscovery = true
    refresh()
  }

  /// Saves the suggested profile when it has both a router and a separate AP.
  @discardableResult
  public func acceptSuggestion() -> Bool {
    switch suggestion {
    case .monitor(let discovery):
      guard let profile = discovery.proposedProfile else { return false }
      return save(profile)
    case .update(_, let proposed):
      return save(proposed)
    case nil:
      return false
    }
  }

  /// Pings every host in the Wi-Fi subnet once so the ARP cache can reveal the access point.
  ///
  /// Runs only when the user asks, refuses public or larger than /22 subnets, and never
  /// starts monitoring by itself.
  public func searchForAccessPoint() async {
    if case .searching = accessPointSearch { return }
    guard let network, !sleeping else {
      accessPointSearch = .finished("Connect to Wi-Fi before searching for the AP.")
      return
    }
    guard let interfaceAddress = environment.interfaceAddress(network.interface) else {
      accessPointSearch = .finished(SubnetSweep.Refusal.invalidAddress.description)
      return
    }
    let hosts: [String]
    do {
      hosts = try SubnetSweep.hosts(
        address: interfaceAddress.address, netmask: interfaceAddress.netmask)
    } catch {
      accessPointSearch = .finished(error.description)
      return
    }
    accessPointSearch = .searching(hosts: hosts.count)
    await Self.ping(hosts, over: network.interface, with: probe)
    networkChanged()
    accessPointSearch = .finished(searchSummary(hosts: hosts.count))
  }

  private static func ping(_ hosts: [String], over interface: String, with probe: any LatencyProbe)
    async
  {
    await withTaskGroup(of: Void.self) { group in
      var pending = hosts.makeIterator()
      for _ in 0..<32 {
        guard let host = pending.next() else { break }
        group.addTask { _ = await probe.measure(address: host, interface: interface) }
      }
      while await group.next() != nil {
        guard let host = pending.next() else { continue }
        group.addTask { _ = await probe.measure(address: host, interface: interface) }
      }
    }
  }

  private func searchSummary(hosts: Int) -> String {
    let addresses = hosts == 1 ? "1 address" : "\(hosts) addresses"
    return switch discovery?.accessPoint {
    case .found(let address): "Found the AP at \(address) after pinging \(addresses)."
    case .router: "The associated AP is the router itself, so there is no separate AP to compare."
    case .unknown, nil:
      "No device among \(addresses) matches the AP. Enter its address in Settings."
    }
  }

  /// Hides the current suggestion until the discovered addresses change.
  public func dismissSuggestion() {
    if let discovery { dismissed.insert(Self.key(discovery)) }
    suggestion = nil
  }

  public func refresh() {
    network = environment.currentNetwork()
    discover()
    if session.select(
      network: network, profiles: profiles, permitted: environment.isPermitted,
      paused: paused || sleeping)
    {
      inFlight?.cancel()
      healthSince = uptime()
    }
    reason = currentReason()
  }

  /// Runs one paired measurement and returns the delay before the next cycle.
  public func cycle() async -> TimeInterval {
    let started = uptime()
    refresh()
    if let profile = session.profile, let network = session.network {
      let generation = session.generation
      let probe = probe
      let uptime = uptime
      let task = Task {
        async let accessPoint = probe.measure(
          address: profile.accessPoint, interface: network.interface)
        async let router = probe.measure(address: profile.router, interface: network.interface)
        let outcomes = await (accessPoint, router)
        return ProbePair(elapsed: uptime(), accessPoint: outcomes.0, router: outcomes.1)
      }
      inFlight = task
      let pair = await task.value
      inFlight = nil
      refresh()
      let previous = session.window.health
      session.accept(pair, generation: generation)
      if previous != session.window.health { healthSince = uptime() }
      reason = currentReason()
    }
    return max(0.05, Self.interval - (uptime() - started))
  }

  private func discover() {
    guard let network, !sleeping else {
      discovery = nil
      suggestion = nil
      return
    }
    if needsDiscovery || discovery?.network != network {
      needsDiscovery = false
      discovery = NetworkDiscovery(
        network: network, router: environment.defaultRouter(for: network.interface),
        neighbors: environment.neighbors())
    }
    suggestion = currentSuggestion()
  }

  private func currentSuggestion() -> NetworkSuggestion? {
    guard let discovery, !dismissed.contains(Self.key(discovery)) else { return nil }
    let matches = profiles.filter { $0.ssid == discovery.network.ssid }
    guard let profile = matches.first else { return .monitor(discovery) }
    let updated = discovery.updating(profile)
    guard matches.count == 1, updated != profile, updated.isValid else { return nil }
    return .update(current: profile, proposed: updated)
  }

  private static func key(_ discovery: NetworkDiscovery) -> String {
    "\(discovery.network.ssid)|\(discovery.router ?? "")|\(discovery.accessPoint)"
  }

  @discardableResult
  private func persist(_ updated: [NetworkProfile]) -> Bool {
    do {
      try store.save(updated)
    } catch {
      storageError = "Profiles could not be saved. Previous settings remain in use."
      return false
    }
    profiles = updated
    storageError = nil
    networkChanged()
    return true
  }

  private func invalidate() {
    inFlight?.cancel()
    session.reset()
    healthSince = uptime()
  }

  private func currentReason() -> String {
    if sleeping { return "Paused while Mac sleeps" }
    if paused { return "Paused manually" }
    if !environment.isPermitted {
      return "Location permission is needed to identify approved Wi-Fi networks"
    }
    if network == nil { return "Wi-Fi is disconnected or its identity is unavailable" }
    if session.profile == nil { return "This Wi-Fi network is not selected for monitoring" }
    if session.window.samples.isEmpty { return "Waiting for paired measurements" }
    switch session.window.health {
    case .healthy: return "No sustained degradation detected"
    case .routerSlower: return "Router responses are persistently slower than the configured AP"
    case .bothSlow: return "Both targets are slow; local Wi-Fi or laptop delay is possible"
    case .unreachable(let accessPoint, let router):
      return "No reply from "
        + (accessPoint && router ? "both targets" : accessPoint ? "AP" : "router")
    }
  }
}
