extension MonitorController {
  /// The access point the Mac reaches the router through right now.
  ///
  /// Nil when the Mac is on the router's own radio. The same network can be both as someone moves around the
  /// house, so this follows the associated radio rather than the profile alone.
  public func servingAccessPoint(for profile: NetworkProfile) -> String? {
    let current = discovery?.network == network ? discovery?.accessPoint : nil
    switch current {
    case .router: return nil
    case .found(let address) where address != profile.router: return address
    default: return profile.isSingleDevice ? nil : profile.accessPoint
    }
  }

  /// Whether the Mac is on the router's own radio for the monitored profile.
  public var onRouterRadio: Bool {
    session.profile.map { servingAccessPoint(for: $0) == nil } ?? false
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
}
