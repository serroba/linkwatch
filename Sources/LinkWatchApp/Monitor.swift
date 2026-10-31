import AppKit
import CoreLocation
import CoreWLAN
import LinkWatchCore
import LinkWatchNetworking
import Network
import SwiftUI
import SystemConfiguration

@MainActor
final class Monitor: NSObject, ObservableObject, CLLocationManagerDelegate {
  @Published private(set) var session = MonitoringSession()
  @Published private(set) var profiles: [NetworkProfile] = []
  @Published private(set) var network: NetworkIdentity?
  @Published private(set) var reason = "Choose a Wi-Fi network in Settings"
  @Published private(set) var storageError: String?
  @Published private(set) var healthSince = ProcessInfo.processInfo.systemUptime
  @Published var paused = false {
    didSet { refresh() }
  }
  private let location = CLLocationManager()
  private let wifi = CWWiFiClient.shared()
  private let pathMonitor = NWPathMonitor()
  private var sleeping = false
  private var inFlight: Task<ProbePair, Never>?
  private var observers: [NSObjectProtocol] = []
  private let storageKey = "networkProfiles.v1"

  override init() {
    super.init()
    location.delegate = self
    if let data = UserDefaults.standard.data(forKey: storageKey) {
      if let decoded = try? JSONDecoder().decode([NetworkProfile].self, from: data),
        decoded.allSatisfy(\.isValid), Set(decoded.map(\.ssid)).count == decoded.count
      {
        profiles = decoded
      } else {
        storageError =
          "Saved profiles could not be read. Monitoring is paused until you save a profile."
      }
    }
    let center = NSWorkspace.shared.notificationCenter
    observers.append(
      center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
        [weak self] _ in
        Task { @MainActor in
          self?.sleeping = true
          self?.invalidate()
          self?.refresh()
        }
      })
    observers.append(
      center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
        [weak self] _ in
        Task { @MainActor in
          self?.sleeping = false
          self?.invalidate()
          self?.refresh()
        }
      })
    pathMonitor.pathUpdateHandler = { [weak self] _ in
      Task { @MainActor in
        self?.invalidate()
        self?.refresh()
      }
    }
    pathMonitor.start(queue: DispatchQueue(label: "LinkWatch.network"))
    Task { [weak self] in
      while let self {
        self.refresh()
        try? await Task.sleep(for: .milliseconds(500))
      }
    }
    Task { [weak self] in
      while let self {
        await self.cycle()
      }
    }
  }

  var permitted: Bool {
    location.authorizationStatus == .authorizedAlways
  }

  func requestPermission() {
    NSApp.activate(ignoringOtherApps: true)
    location.requestWhenInUseAuthorization()
  }

  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    Task { @MainActor in self.refresh() }
  }

  func save(_ profile: NetworkProfile) -> Bool {
    guard profile.isValid else { return false }
    var updated = profiles.filter { $0.id != profile.id && $0.ssid != profile.ssid }
    updated.append(profile)
    persist(updated)
    return true
  }

  func remove(_ profile: NetworkProfile) {
    persist(profiles.filter { $0.id != profile.id })
  }

  private func persist(_ updated: [NetworkProfile]) {
    guard let data = try? JSONEncoder().encode(updated) else { return }
    UserDefaults.standard.set(data, forKey: storageKey)
    profiles = updated
    storageError = nil
    invalidate()
    refresh()
  }

  func suggestedRouter() -> String? {
    guard let store = SCDynamicStoreCreate(nil, "LinkWatch" as CFString, nil, nil),
      let values = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString)
        as? [String: Any],
      let interface = network?.interface, values["PrimaryInterface"] as? String == interface
    else { return nil }
    return values["Router"] as? String
  }

  private func invalidate() {
    inFlight?.cancel()
    session.reset()
    healthSince = ProcessInfo.processInfo.systemUptime
  }

  private func refresh() {
    let interface = wifi.interface()
    if permitted, let interface, interface.powerOn(), let ssid = interface.ssid(),
      let bssid = interface.bssid(), !ssid.isEmpty, !bssid.isEmpty,
      let name = interface.interfaceName
    {
      network = NetworkIdentity(ssid: ssid, bssid: bssid, interface: name)
    } else {
      network = nil
    }
    if session.select(
      network: network, profiles: profiles, permitted: permitted, paused: paused || sleeping)
    {
      inFlight?.cancel()
      healthSince = ProcessInfo.processInfo.systemUptime
    }
    if sleeping {
      reason = "Paused while Mac sleeps"
    } else if paused {
      reason = "Paused manually"
    } else if !permitted {
      reason = "Location permission is needed to identify approved Wi-Fi networks"
    } else if network == nil {
      reason = "Wi-Fi is disconnected or its identity is unavailable"
    } else if session.profile == nil {
      reason = "This Wi-Fi network is not selected for monitoring"
    } else if session.window.samples.isEmpty {
      reason = "Waiting for paired measurements"
    } else {
      switch session.window.health {
      case .healthy: reason = "No sustained degradation detected"
      case .routerSlower: reason = "Router responses are persistently slower than the configured AP"
      case .bothSlow: reason = "Both targets are slow; local Wi-Fi or laptop delay is possible"
      case .unreachable(let accessPoint, let router):
        reason =
          "No reply from "
          + (accessPoint && router ? "both targets" : accessPoint ? "AP" : "router")
      }
    }
  }

  private func cycle() async {
    let started = ProcessInfo.processInfo.systemUptime
    refresh()
    if let profile = session.profile, let network = session.network {
      let generation = session.generation
      let task = Task {
        async let accessPoint = ICMPProbe.measure(
          address: profile.accessPoint, interface: network.interface)
        async let router = ICMPProbe.measure(address: profile.router, interface: network.interface)
        return await ProbePair(
          elapsed: ProcessInfo.processInfo.systemUptime, accessPoint: accessPoint, router: router)
      }
      inFlight = task
      let pair = await task.value
      refresh()
      let previous = session.window.health
      session.accept(pair, generation: generation)
      if previous != session.window.health { healthSince = ProcessInfo.processInfo.systemUptime }
      inFlight = nil
      refresh()
    }
    let remaining = max(0.05, 2 - (ProcessInfo.processInfo.systemUptime - started))
    try? await Task.sleep(for: .seconds(remaining))
  }

  var accessPointLatency: Double? {
    guard session.window.samples.last?.accessPoint.latency != nil else { return nil }
    return session.window.accessPointMedian
  }

  var routerLatency: Double? {
    guard session.window.samples.last?.router.latency != nil else { return nil }
    return session.window.routerMedian
  }

  var color: Color {
    guard session.profile != nil, !session.window.samples.isEmpty else { return .gray }
    switch session.window.health {
    case .healthy: return .green
    case .bothSlow: return .orange
    case .routerSlower: return .red
    case .unreachable: return .purple
    }
  }

  var symbol: String {
    guard session.profile != nil, !session.window.samples.isEmpty else {
      return "pause.circle.fill"
    }
    switch session.window.health {
    case .healthy: return "checkmark.circle.fill"
    case .bothSlow, .routerSlower: return "exclamationmark.triangle.fill"
    case .unreachable: return "xmark.octagon.fill"
    }
  }

  func latencyText(_ value: Double?) -> String {
    value.map { String(format: "%.0f", $0) } ?? "—"
  }
}
