import Foundation

extension MonitorController {
  /// Every fifth cycle, ten seconds, on metered connections such as phone hotspots.
  static let meteredReferenceInterval = 5

  /// Whether the current network looks like a phone's personal hotspot: macOS marks the path
  /// as expensive, or the router uses the iPhone hotspot range.
  public var isHotspot: Bool {
    network != nil && (environment.isExpensivePath || discovery?.looksLikeIPhoneHotspot == true)
  }

  /// The profile a suggestion would save, flagged as a hotspot when one is detected.
  public func proposedProfile(for discovery: NetworkDiscovery) -> NetworkProfile? {
    discovery.proposedProfile(hotspot: isHotspot)
  }

  /// Saves the suggested profile once its router and access point are known; on a hotspot
  /// the phone is both.
  @discardableResult
  public func acceptSuggestion() -> Bool {
    switch suggestion {
    case .monitor(let discovery):
      guard let profile = proposedProfile(for: discovery) else { return false }
      return save(profile)
    case .update(_, let proposed):
      return save(proposed)
    case nil:
      return false
    }
  }

  /// Internet references for this cycle, spaced out on hotspots to save mobile data.
  func referencesToProbe(for profile: NetworkProfile) -> [String] {
    guard profile.internetReferences else { return [] }
    let metered = profile.hotspot || environment.isExpensivePath
    guard !metered || cycles % Self.meteredReferenceInterval == 1 else { return [] }
    return InternetReference.all.map(\.address)
  }
}
