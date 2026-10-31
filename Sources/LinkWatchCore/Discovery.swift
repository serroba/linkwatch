import Foundation

/// An IPv4 neighbour from the system's existing ARP cache.
public struct NeighborEntry: Equatable, Sendable {
  public let address: String
  public let hardwareAddress: String
  public let interface: String

  public init(address: String, hardwareAddress: String, interface: String) {
    self.address = address
    self.hardwareAddress = hardwareAddress
    self.interface = interface
  }
}

/// What passive inspection learned about the associated access point.
public enum AccessPointDiscovery: Equatable, Sendable {
  /// A single neighbour other than the router matches the BSSID.
  case found(String)
  /// The BSSID belongs to the router, so there is no separate AP to compare.
  case router
  /// No unambiguous neighbour matches the BSSID.
  case unknown
}

/// Router and access point addresses inferred for the current Wi-Fi network without probing.
public struct NetworkDiscovery: Equatable, Sendable {
  public let network: NetworkIdentity
  public let router: String?
  public let accessPoint: AccessPointDiscovery

  public init(network: NetworkIdentity, router: String?, neighbors: [NeighborEntry]) {
    self.network = network
    self.router = router.flatMap { NetworkProfile.validAddress($0) ? $0 : nil }
    let candidates = Set(
      neighbors
        .filter {
          $0.interface == network.interface
            && HardwareAddress.isRadio(network.bssid, of: $0.hardwareAddress)
            && NetworkProfile.validAddress($0.address)
        }
        .map(\.address))
    if candidates.count == 1, let address = candidates.first {
      accessPoint = address == self.router ? .router : .found(address)
    } else {
      accessPoint = .unknown
    }
  }

  /// A complete profile when the router is known and the access point is either a separate
  /// device or the router itself; hotspots are flagged so advice talks about the phone.
  public func proposedProfile(hotspot: Bool = false) -> NetworkProfile? {
    guard let router else { return nil }
    let accessPoint: String
    switch self.accessPoint {
    case .found(let address): accessPoint = address
    case .router: accessPoint = router
    case .unknown:
      guard hotspot else { return nil }
      accessPoint = router
    }
    let profile = NetworkProfile(
      ssid: network.ssid, accessPoint: accessPoint, router: router, hotspot: hotspot)
    return profile.isValid ? profile : nil
  }

  /// iPhone personal hotspots hand out addresses from 172.20.10.0/28.
  public var looksLikeIPhoneHotspot: Bool {
    guard let router, let octets = NetworkProfile.octets(router) else { return false }
    return octets[0] == 172 && octets[1] == 20 && octets[2] == 10 && octets[3] < 16
  }

  /// Applies discovered addresses to an existing profile, keeping its identity and thresholds.
  public func updating(_ profile: NetworkProfile) -> NetworkProfile {
    var updated = profile
    if let router { updated.router = router }
    if case .found(let accessPoint) = accessPoint { updated.accessPoint = accessPoint }
    return updated
  }
}

enum HardwareAddress {
  static func parse(_ text: String) -> [UInt8]? {
    let parts = text.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 6 else { return nil }
    let bytes = parts.compactMap { part in
      (1...2).contains(part.count) ? UInt8(part, radix: 16) : nil
    }
    return bytes.count == 6 ? bytes : nil
  }

  /// Whether a BSSID is plausibly a radio of the device with the given wired address.
  ///
  /// Vendors usually derive radio addresses by setting the locally administered bit or by
  /// adding a small offset to the last byte of the base address.
  static func isRadio(_ bssid: String, of hardwareAddress: String) -> Bool {
    guard let radio = parse(bssid), let device = parse(hardwareAddress),
      radio != [0, 0, 0, 0, 0, 0]
    else { return false }
    if radio == device { return true }
    return radio[0] | 0x02 == device[0] | 0x02 && radio[1..<5] == device[1..<5]
      && abs(Int(radio[5]) - Int(device[5])) <= 7
  }
}
