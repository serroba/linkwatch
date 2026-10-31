extension MonitorController {
  /// The device the Mac is connected through right now, or nil while that is unclear.
  ///
  /// The same network can be reached through the router's own Wi-Fi in one room and an
  /// access point in another, so this follows the associated radio.
  public var connectionPath: ConnectionPath? {
    guard let profile = session.profile else { return nil }
    return ConnectionPath(
      profile: profile, discovered: discovery?.network == network ? discovery?.accessPoint : nil,
      evidence: session.window.evidence)
  }

  /// Rechecks which device the Mac is connected through, from the ARP cache; sends nothing.
  public func detectPath() {
    needsDiscovery = true
    refresh()
  }

  /// Whether the Mac is on the router's own Wi-Fi while the profile also has an access point.
  public var onRouterRadio: Bool {
    connectionPath == .router && session.profile?.isSingleDevice == false
  }

  /// How the access point is doing while this Mac is not using it: informative, not an alert.
  public var accessPointNote: String? {
    guard onRouterRadio, let profile = session.profile else { return nil }
    let evidence = session.window.evidence
    let bridge = profile.bridgeName.map { "the \($0)" } ?? "the link to it"
    if evidence.accessPoint.isLost {
      return
        "The access point is not answering through \(bridge). This Mac is on the router's Wi-Fi, so only devices using the access point are affected."
    }
    guard let accessPoint = evidence.accessPoint.median, let router = evidence.router.median,
      accessPoint - router > profile.thresholds.difference
    else { return nil }
    return
      "The access point is slow to reach through \(bridge). This Mac is on the router's Wi-Fi, so only devices using the access point are affected."
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
