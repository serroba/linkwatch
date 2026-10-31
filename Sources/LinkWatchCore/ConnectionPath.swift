/// The device the Mac's Wi-Fi is connected through on a network with an access point.
public enum ConnectionPath: String, Codable, Sendable {
  /// Mac → access point → (bridge) → router.
  case accessPoint
  /// Mac → router's own Wi-Fi; the access point sits on the far side of the bridge.
  case router

  /// Latencies closer than this are not trusted to tell the paths apart.
  static let latencyMargin = 2.0

  /// Prefers the hardware address match from discovery; otherwise the nearer device answers
  /// faster, since reaching the other one crosses the bridge.
  init?(profile: NetworkProfile, discovered: AccessPointDiscovery?, evidence: LinkEvidence) {
    if profile.isSingleDevice {
      self = .router
      return
    }
    switch discovered {
    case .router: self = .router
    case .found: self = .accessPoint
    case .unknown, nil:
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
