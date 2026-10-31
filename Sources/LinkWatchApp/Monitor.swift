import AppKit
import Combine
import CoreLocation
import CoreWLAN
import Foundation
import LinkWatchCore
import LinkWatchNetworking
import Network
import SystemConfiguration

/// Owns the controller and connects it to macOS notifications and timers.
///
/// Views observe the controller; conforming here only gives the app `@StateObject` ownership,
/// because the `@State` macro is unavailable with Command Line Tools alone.
@MainActor
final class Monitor: ObservableObject {
  let controller: MonitorController
  let environment: SystemEnvironment
  private let pathMonitor = NWPathMonitor()
  private var observers: [any NSObjectProtocol] = []

  init() {
    environment = SystemEnvironment()
    controller = MonitorController(
      environment: environment, probe: ICMPLatencyProbe(), store: UserDefaultsProfileStore(),
      uptime: { ProcessInfo.processInfo.systemUptime })
    environment.onAuthorizationChange = { [weak controller] in controller?.refresh() }
    observeLifecycle()
  }

  /// Starts the refresh and probe loops that drive the menu bar interface.
  static func forInterface() -> Monitor {
    let monitor = Monitor()
    monitor.startLoops()
    return monitor
  }

  private func startLoops() {
    Task { [weak controller] in
      while let controller {
        controller.refresh()
        try? await Task.sleep(for: .milliseconds(500))
      }
    }
    Task { [weak controller] in
      while let controller {
        let delay = await controller.cycle()
        try? await Task.sleep(for: .seconds(delay))
      }
    }
  }

  private func observeLifecycle() {
    let center = NSWorkspace.shared.notificationCenter
    for (name, sleeping) in [
      (NSWorkspace.willSleepNotification, true), (NSWorkspace.didWakeNotification, false),
    ] {
      observers.append(
        center.addObserver(forName: name, object: nil, queue: .main) { [weak controller] _ in
          Task { @MainActor in controller?.setSleeping(sleeping) }
        })
    }
    pathMonitor.pathUpdateHandler = { [weak controller] _ in
      Task { @MainActor in controller?.networkChanged() }
    }
    pathMonitor.start(queue: DispatchQueue(label: "LinkWatch.network"))
  }
}

/// Reads Wi-Fi identity through CoreWLAN, gated by Location permission.
@MainActor
final class SystemEnvironment: NSObject, NetworkEnvironment, CLLocationManagerDelegate {
  var onAuthorizationChange: (@MainActor () -> Void)?
  private let location = CLLocationManager()
  private let wifi = CWWiFiClient.shared()

  override init() {
    super.init()
    location.delegate = self
  }

  var isPermitted: Bool {
    location.authorizationStatus == .authorizedAlways
  }

  var wifiState: WiFiState {
    let interface = wifi.interface()
    return WiFiState(
      authorization: authorizationDescription, interface: interface?.interfaceName,
      poweredOn: interface?.powerOn() ?? false, ssidVisible: !(interface?.ssid() ?? "").isEmpty,
      bssidVisible: !(interface?.bssid() ?? "").isEmpty)
  }

  /// The Wi-Fi interface name, which macOS reveals without Location permission.
  var wifiInterfaceName: String? {
    wifi.interface()?.interfaceName
  }

  var authorizationDescription: String {
    switch location.authorizationStatus {
    case .notDetermined: "not determined"
    case .restricted: "restricted"
    case .denied: "denied"
    case .authorizedAlways: "authorized"
    default: "unknown (\(location.authorizationStatus.rawValue))"
    }
  }

  var isDenied: Bool {
    [.denied, .restricted].contains(location.authorizationStatus)
  }

  func requestPermission() {
    NSApp.activate(ignoringOtherApps: true)
    requestAuthorization()
  }

  /// Requests Location permission without touching `NSApp`, which headless runs lack.
  func requestAuthorization() {
    location.requestWhenInUseAuthorization()
  }

  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    Task { @MainActor in self.onAuthorizationChange?() }
  }

  func currentNetwork() -> NetworkIdentity? {
    guard isPermitted, let interface = wifi.interface(), interface.powerOn(),
      let ssid = interface.ssid(), let bssid = interface.bssid(), !ssid.isEmpty, !bssid.isEmpty,
      let name = interface.interfaceName
    else { return nil }
    return NetworkIdentity(ssid: ssid, bssid: bssid, interface: name)
  }

  func neighbors() -> [NeighborEntry] {
    NeighborTable.entries()
  }

  func defaultRouter(for interface: String) -> String? {
    guard let store = SCDynamicStoreCreate(nil, "LinkWatch" as CFString, nil, nil),
      let values = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString)
        as? [String: Any],
      values["PrimaryInterface"] as? String == interface
    else { return nil }
    return values["Router"] as? String
  }
}

/// Stores profiles as JSON in the app's user defaults.
struct UserDefaultsProfileStore: ProfileStore {
  private let key = "networkProfiles.v1"

  func load() throws -> [NetworkProfile]? {
    guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
    return try JSONDecoder().decode([NetworkProfile].self, from: data)
  }

  func save(_ profiles: [NetworkProfile]) throws {
    UserDefaults.standard.set(try JSONEncoder().encode(profiles), forKey: key)
  }
}
