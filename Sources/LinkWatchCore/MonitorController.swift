public import Foundation
public import Observation

/// Sends one latency probe to an address over a named interface.
public protocol LatencyProbe: Sendable {
  func measure(address: String, interface: String) async -> ProbeOutcome
}

/// Reports permission and the identity of the current Wi-Fi network.
@MainActor
public protocol NetworkEnvironment: AnyObject {
  var isPermitted: Bool { get }
  func currentNetwork() -> NetworkIdentity?
}

/// Persists approved network profiles on this Mac.
public protocol ProfileStore {
  /// Returns nil when nothing has been saved yet.
  func load() throws -> [NetworkProfile]?
  func save(_ profiles: [NetworkProfile]) throws
}

/// The overall state shown in the menu bar.
public enum DisplayState: Equatable, Sendable {
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

  @ObservationIgnored private let environment: any NetworkEnvironment
  @ObservationIgnored private let probe: any LatencyProbe
  @ObservationIgnored private let store: any ProfileStore
  @ObservationIgnored private let uptime: @MainActor () -> TimeInterval
  @ObservationIgnored private var inFlight: Task<ProbePair, Never>?

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
    refresh()
  }

  public func refresh() {
    network = environment.currentNetwork()
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
