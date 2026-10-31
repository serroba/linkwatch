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

  /// Only the menu bar app records history; command-line runs read it, so they can never
  /// race the app's appends with a rewrite.
  init(recordsHistory: Bool = false) {
    environment = SystemEnvironment()
    let history: any HistoryStore =
      recordsHistory
      ? FileHistoryStore(directory: Self.supportDirectory)
      : ReadOnlyHistoryStore(directory: Self.supportDirectory)
    let events: any EventStore =
      recordsHistory
      ? FileEventStore(directory: Self.supportDirectory)
      : ReadOnlyEventStore(directory: Self.supportDirectory)
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    try? events.append(AppEvent(time: Date(), kind: .launched, detail: version))
    controller = MonitorController(
      environment: environment, probe: ICMPLatencyProbe(), store: UserDefaultsProfileStore(),
      history: history, events: events,
      uptime: { ProcessInfo.processInfo.systemUptime }, now: { Date() })
    environment.onAuthorizationChange = { [weak controller] in controller?.refresh() }
    observeLifecycle()
  }

  /// Starts the refresh and probe loops that drive the menu bar interface.
  static func forInterface() -> Monitor {
    let monitor = Monitor(recordsHistory: true)
    monitor.startLoops()
    LoginItem.applyPreference()
    return monitor
  }

  /// Private per-user storage for the week of minute summaries.
  static var supportDirectory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("io.github.serroba.LinkWatch", isDirectory: true)
  }

  private func startLoops() {
    observers += AppControl.listen(controller: controller, environment: environment)
    observers.append(
      NotificationCenter.default.addObserver(
        forName: NSApplication.willTerminateNotification, object: nil, queue: .main
      ) { [weak controller] _ in
        MainActor.assumeIsolated {
          controller?.flushHistory()
          controller?.record(.quit)
        }
      })
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

  /// The interface that owns the IPv4 default route, such as a VPN tunnel.
  var primaryInterface: String? {
    guard let store = SCDynamicStoreCreate(nil, "LinkWatch" as CFString, nil, nil),
      let values = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString)
        as? [String: Any]
    else { return nil }
    return values["PrimaryInterface"] as? String
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

  func interfaceAddress(_ interface: String) -> InterfaceAddress? {
    InterfaceAddresses.ipv4(on: interface)
  }

  func traffic(on interface: String) -> TrafficCounters? {
    InterfaceCounters.traffic(on: interface)
  }

  /// Returns the IPv4 router assigned to the network service on this interface.
  ///
  /// This works while another interface, such as a VPN, owns the default route; probes stay
  /// bound to Wi-Fi.
  func defaultRouter(for interface: String) -> String? {
    guard let store = SCDynamicStoreCreate(nil, "LinkWatch" as CFString, nil, nil),
      let keys = SCDynamicStoreCopyKeyList(store, "State:/Network/Service/[^/]+/IPv4" as CFString)
        as? [String]
    else { return nil }
    let routers = keys.compactMap { key -> String? in
      guard let values = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
        values["InterfaceName"] as? String == interface
      else { return nil }
      return values["Router"] as? String
    }
    return Set(routers).count == 1 ? routers.first : nil
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
