/// The device the Mac's Wi-Fi is connected through on a network with an access point.
public enum ConnectionPath: String, Codable, Sendable {
  /// Mac → access point → (bridge) → router.
  case accessPoint
  /// Mac → router's own Wi-Fi; the access point sits on the far side of the bridge.
  case router

  /// Latencies closer than this are not trusted to tell the paths apart.
  static let latencyMargin = 2.0

  /// Prefers the hardware address match from discovery; otherwise a BSSID that is not one of
  /// the router's radios means an access point; otherwise the nearer device answers faster,
  /// since reaching the other one crosses the bridge.
  init?(profile: NetworkProfile, discovery: NetworkDiscovery?, evidence: LinkEvidence) {
    // A phone's hotspot radio need not resemble its LAN address, so it is always the router.
    if profile.hotspot {
      self = .router
      return
    }
    switch discovery?.accessPoint {
    case .router: self = .router
    case .found: self = .accessPoint
    case .unknown where discovery?.behindAccessPoint == true: self = .accessPoint
    case .unknown, nil:
      // Without a separate AP to compare, assume the router unless shown otherwise.
      if profile.isSingleDevice {
        self = .router
        return
      }
      guard let accessPoint = evidence.accessPoint.median, let router = evidence.router.median
      else { return nil }
      if accessPoint + Self.latencyMargin < router {
        self = .accessPoint
      } else if router + Self.latencyMargin < accessPoint {
        self = .router
      } else {
        return nil
      }
    }
  }
}
