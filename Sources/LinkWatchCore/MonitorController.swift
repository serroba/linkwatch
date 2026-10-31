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

/// Bytes an interface has received and sent, as cumulative counters or as a delta.
public struct TrafficCounters: Equatable, Sendable {
  public var received: UInt64
  public var sent: UInt64

  public init(received: UInt64, sent: UInt64) {
    self.received = received
    self.sent = sent
  }
}

/// The Mac's current download and upload rate on the monitored interface.
public struct Usage: Equatable, Sendable {
  public var downloadBitsPerSecond: Double
  public var uploadBitsPerSecond: Double
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
  /// Cumulative byte counters for the interface, read without sending traffic.
  func traffic(on interface: String) -> TrafficCounters?
  /// The radio's signal readings, or nil when unavailable.
  func signal() -> WiFiSignal?
  /// Whether macOS marks the current path as expensive, as it does for phone hotspots.
  var isExpensivePath: Bool { get }
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
  public internal(set) var accessPointSearch = AccessPointSearch.idle
  public internal(set) var week = WeekHistory()
  /// The sustained verdict: a change must hold for the profile's alert or recovery time.
  public internal(set) var verdict = Verdict.allClear
  @ObservationIgnored var pendingVerdict: (verdict: Verdict, since: TimeInterval)?
  /// The latest download and upload rate, or nil before two readings on one network.
  public internal(set) var usage: Usage?
  /// The latest Wi-Fi radio readings while monitoring.
  public internal(set) var signal: WiFiSignal?
  @ObservationIgnored var lastTraffic: TrafficReading?
  /// Counts probe cycles, to space out internet references on metered connections.
  @ObservationIgnored var cycles = 0
  /// When discovery last ran, so the connected device is rechecked every minute.
  @ObservationIgnored var discoveredAt: TimeInterval = -.infinity
  /// Rates from the last five cycles and the highest seen in this session.
  @ObservationIgnored var recentRates: [Double] = []
  @ObservationIgnored var sessionPeakRate: Double = 0
  /// The guided device test, if one is running or has a result to show.
  public internal(set) var deviceTest = DeviceTestState.idle
  @ObservationIgnored var deviceTestBounds: [DeviceTestPhase: ClosedRange<TimeInterval>] = [:]
  public internal(set) var historyError: String?
  /// The latest restart recorded in this run, compared with the links once minutes follow.
  public internal(set) var lastRestart: AppEvent?

  @ObservationIgnored let environment: any NetworkEnvironment
  @ObservationIgnored let probe: any LatencyProbe
  @ObservationIgnored private let store: any ProfileStore
  @ObservationIgnored let uptime: @MainActor () -> TimeInterval
  @ObservationIgnored let historyStore: any HistoryStore
  @ObservationIgnored let events: any EventStore
  @ObservationIgnored var observed = ObservedState()
  @ObservationIgnored let now: @MainActor () -> Date
  @ObservationIgnored private var inFlight: Task<ProbePair, Never>?
  @ObservationIgnored private var dismissed: Set<String> = []
  @ObservationIgnored var needsDiscovery = true

  public static let interval: TimeInterval = 2

  public init(
    environment: any NetworkEnvironment, probe: any LatencyProbe, store: any ProfileStore,
    history: any HistoryStore, events: any EventStore,
    uptime: @escaping @MainActor () -> TimeInterval, now: @escaping @MainActor () -> Date
  ) {
    self.environment = environment
    self.probe = probe
    self.store = store
    self.historyStore = history
    self.events = events
    self.uptime = uptime
    self.now = now
    healthSince = uptime()
    loadProfiles()
    loadHistory()
    refresh()
  }

  /// Rereads saved profiles, for changes made by another process such as the command line.
  public func reloadProfiles() {
    loadProfiles()
    networkChanged()
  }

  private func loadProfiles() {
    do {
      let saved = try store.load() ?? []
      guard saved.allSatisfy(\.isValid), Set(saved.map(\.ssid)).count == saved.count else {
        throw CocoaError(.coderReadCorrupt)
      }
      profiles = saved
      storageError = nil
    } catch {
      profiles = []
      storageError =
        "Saved profiles could not be read. Monitoring is paused until you save a profile."
    }
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
    guard persist(updated) else { return false }
    record(.profileSaved, detail: profile.ssid)
    return true
  }

  public func remove(_ profile: NetworkProfile) {
    if persist(profiles.filter { $0.id != profile.id }) {
      record(.profileRemoved, detail: profile.ssid)
    }
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
      resetDerivedState()
    }
    // Hotspots first: a phone's network never gains a separate access point.
    rememberHotspot()
    rememberAccessPoint()
    reason = currentReason()
    recordTransitions()
  }

  /// Runs one paired measurement and returns the delay before the next cycle.
  public func cycle() async -> TimeInterval {
    let started = uptime()
    refresh()
    if let profile = session.profile, let network = session.network {
      let generation = session.generation
      let probe = probe
      let uptime = uptime
      cycles += 1
      let references = referencesToProbe(for: profile)
      // The access point is pinged from anywhere on the network: on the router's own Wi-Fi
      // the reply crosses the bridge, which is informative rather than a problem.
      let addresses =
        profile.isSingleDevice ? [profile.router] : [profile.accessPoint, profile.router]
      let task = Task {
        async let local = Self.measure(addresses, over: network.interface, with: probe)
        async let internet = Self.measure(references, over: network.interface, with: probe)
        let outcomes = await (local, internet)
        // A single device answers for both the access point and the router.
        return ProbePair(
          elapsed: uptime(), accessPoint: outcomes.0[0], router: outcomes.0[outcomes.0.count - 1],
          internet: outcomes.1)
      }
      inFlight = task
      let pair = await task.value
      inFlight = nil
      refresh()
      let previous = session.window.health
      session.accept(pair, generation: generation)
      if generation == session.generation, session.window.samples.last == pair {
        signal = environment.signal()
        record(pair, traffic: trafficDelta(on: network.interface, at: pair.elapsed))
        updateVerdict(at: pair.elapsed)
        advanceDeviceTest(at: pair.elapsed)
      }
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
    if needsDiscovery || discovery?.network != network || uptime() - discoveredAt >= 60 {
      needsDiscovery = false
      discoveredAt = uptime()
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

  /// Clears everything computed from the previous session's samples, so a pause or network
  /// change never shows stale advice or rates.
  private func resetDerivedState() {
    flushHistory()
    verdict = .allClear
    pendingVerdict = nil
    usage = nil
    signal = nil
    lastTraffic = nil
    recentRates = []
    sessionPeakRate = 0
    cancelDeviceTest("Monitoring stopped or the network changed, so the test was cancelled.")
  }

  private func invalidate() {
    inFlight?.cancel()
    resetDerivedState()
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
