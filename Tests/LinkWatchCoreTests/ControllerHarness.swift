import Foundation

@testable import LinkWatchCore

let homeNetwork = NetworkIdentity(ssid: "Home", bssid: "00:00:5e:00:53:01", interface: "en0")
/// Internet references are off so local tests count only AP and router probes.
let homeProfile = NetworkProfile(
  ssid: "Home", accessPoint: "192.0.2.2", router: "192.0.2.1", internetReferences: false)

@MainActor
final class FakeEnvironment: NetworkEnvironment {
  var isPermitted = true
  var network: NetworkIdentity? = homeNetwork
  var wifiState: WiFiState {
    WiFiState(
      authorization: isPermitted ? "authorized" : "not determined", interface: "en0",
      poweredOn: true, ssidVisible: network != nil, bssidVisible: network != nil)
  }
  var router: String?
  var neighborEntries: [NeighborEntry] = []
  var neighborReads = 0
  var address: InterfaceAddress? = InterfaceAddress(
    address: "192.168.7.20", netmask: "255.255.255.0")

  func currentNetwork() -> NetworkIdentity? { isPermitted ? network : nil }

  func defaultRouter(for interface: String) -> String? { interface == "en0" ? router : nil }

  func neighbors() -> [NeighborEntry] {
    neighborReads += 1
    return neighborEntries
  }

  func interfaceAddress(_ interface: String) -> InterfaceAddress? { address }

  var counters: TrafficCounters?
  func traffic(on interface: String) -> TrafficCounters? { counters }
}

struct StoreFailure: Error {}

final class FakeStore: ProfileStore {
  var saved: [NetworkProfile]?
  var failsToLoad = false
  var failsToSave = false

  init(_ saved: [NetworkProfile]? = nil) { self.saved = saved }

  func load() throws -> [NetworkProfile]? {
    if failsToLoad { throw StoreFailure() }
    return saved
  }

  func save(_ profiles: [NetworkProfile]) throws {
    if failsToSave { throw StoreFailure() }
    saved = profiles
  }
}

/// Records probes and runs an optional hook on the main actor before replying.
@MainActor
final class ProbeScript {
  var requests: [String] = []
  var outcomes: [String: ProbeOutcome] = [:]
  var beforeReply: (() -> Void)?

  func reply(address: String, interface: String) -> ProbeOutcome {
    requests.append("\(address)@\(interface)")
    beforeReply?()
    return outcomes[address] ?? .success(milliseconds: 5)
  }
}

struct FakeProbe: LatencyProbe {
  let script: ProbeScript

  func measure(address: String, interface: String) async -> ProbeOutcome {
    await script.reply(address: address, interface: interface)
  }
}

@MainActor
final class Clock {
  var now: TimeInterval = 100
  /// Wall-clock time that advances with `now`, starting on a minute boundary.
  var date: Date { Date(timeIntervalSinceReferenceDate: 800_000_040 + now - 100) }
}

class FakeHistoryStore: HistoryStore {
  var saved: [MinuteSummary] = []
  var failsToLoad = false
  var failsToWrite = false
  var prunes: [Date] = []

  func load(since date: Date) throws -> [MinuteSummary] {
    if failsToLoad { throw StoreFailure() }
    return saved.filter { $0.start >= date }
  }

  func append(_ summary: MinuteSummary) throws {
    if failsToWrite { throw StoreFailure() }
    saved.append(summary)
  }

  func prune(before date: Date) throws {
    prunes.append(date)
    saved.removeAll { $0.start < date }
  }

  func clear() throws {
    if failsToWrite { throw StoreFailure() }
    saved = []
  }
}

@MainActor
struct Harness {
  let environment = FakeEnvironment()
  let script = ProbeScript()
  let clock = Clock()
  let store: FakeStore
  let history: FakeHistoryStore
  let controller: MonitorController

  init(
    profiles: [NetworkProfile]? = [homeProfile], store: FakeStore? = nil,
    history: FakeHistoryStore = FakeHistoryStore()
  ) {
    let store = store ?? FakeStore(profiles)
    let clock = clock
    self.store = store
    self.history = history
    controller = MonitorController(
      environment: environment, probe: FakeProbe(script: script), store: store,
      history: history, uptime: { clock.now }, now: { clock.date })
  }

  func cycle(advancing seconds: TimeInterval = 2) async -> TimeInterval {
    let delay = await controller.cycle()
    clock.now += seconds
    return delay
  }
}

let separateAccessPoint = [
  NeighborEntry(address: "192.0.2.1", hardwareAddress: "00:00:5e:00:53:99", interface: "en0"),
  NeighborEntry(address: "192.0.2.2", hardwareAddress: "00:00:5e:00:53:00", interface: "en0"),
]

func target(_ median: Double?, _ p95: Double?, loss: Double) -> TargetSummary {
  var summary = TargetSummary([])
  summary.median = median
  summary.p95 = p95
  summary.loss = loss
  return summary
}
