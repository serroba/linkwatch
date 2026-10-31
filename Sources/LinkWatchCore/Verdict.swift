import Foundation

/// Recent latency and loss for one target.
public struct TargetEvidence: Equatable, Sendable {
  public var median: Double?
  public var loss: Double

  public init(median: Double?, loss: Double) {
    self.median = median
    self.loss = loss
  }

  /// Half or more of the probes failing, or no successful probe at all, counts as lost.
  var isLost: Bool { loss >= 0.5 || median == nil }
}

/// What the measurements say about each link, live or for one stored minute.
public struct LinkEvidence: Equatable, Sendable {
  public var accessPoint: TargetEvidence
  public var router: TargetEvidence
  /// Nil when the profile does not probe internet reference points.
  public var internet: TargetEvidence?

  public init(accessPoint: TargetEvidence, router: TargetEvidence, internet: TargetEvidence?) {
    self.accessPoint = accessPoint
    self.router = router
    self.internet = internet
  }

  public init(_ minute: MinuteSummary) {
    accessPoint = TargetEvidence(median: minute.accessPoint.median, loss: minute.accessPoint.loss)
    router = TargetEvidence(median: minute.router.median, loss: minute.router.loss)
    internet = minute.internet.map { TargetEvidence(median: $0.median, loss: $0.loss) }
  }
}

/// The most likely failing link, in words anyone in the household can act on.
public enum Verdict: String, Codable, Equatable, Sendable {
  case allClear
  /// The access point is slow or lossy: weak Wi-Fi signal or an overloaded access point.
  case accessPoint
  /// The link between the access point and the router, such as powerline adapters.
  case bridge
  /// The router does not answer while the internet still works, so traffic is flowing.
  case routerSilent
  /// The router does not answer and nothing beyond it is probed, so the cause is unclear.
  case routerUnreachable
  /// Home links are fine; the internet beyond the router is slow or lost.
  case internet

  /// Internet references must be slower than the router by this much to blame the provider.
  public static let internetMargin: Double = 100

  /// Classifies evidence with the profile's thresholds; the first failing link wins.
  public init(_ evidence: LinkEvidence, thresholds: Thresholds) {
    let accessPoint = evidence.accessPoint
    let router = evidence.router
    if accessPoint.isLost || (accessPoint.median ?? 0) > thresholds.slow {
      self = .accessPoint
    } else if router.isLost {
      // A silent router with a working internet is not a failing link: traffic still flows.
      switch evidence.internet?.isLost {
      case nil: self = .routerUnreachable
      case true?: self = .bridge
      case false?: self = .routerSilent
      }
    } else if let accessPointMedian = accessPoint.median, let routerMedian = router.median,
      routerMedian - accessPointMedian > thresholds.difference
    {
      self = .bridge
    } else if let internet = evidence.internet,
      internet.isLost
        || (internet.median ?? 0) - (router.median ?? 0) > Self.internetMargin
    {
      self = .internet
    } else {
      self = .allClear
    }
  }

  /// One plain sentence, naming the bridge when the profile does.
  public func headline(bridge: String?) -> String {
    switch self {
    case .allClear: "Everything is working normally."
    case .accessPoint: "The Wi-Fi connection to the access point is poor."
    case .bridge:
      "The connection between the access point and the router"
        + (bridge.map { " (\($0))" } ?? "") + " is struggling."
    case .routerSilent: "The router is not answering LinkWatch, but the internet works."
    case .routerUnreachable: "The router is not answering LinkWatch."
    case .internet: "Your internet provider is having trouble."
    }
  }

  /// At most one action; nil when there is nothing to do.
  public func action(bridge: String?) -> String? {
    switch self {
    case .allClear: nil
    case .accessPoint:
      "Move closer to the access point. If it stays slow nearby, restart the access point."
    case .bridge:
      "Restart "
        + (bridge.map { "the \($0)." }
          ?? "the device linking the access point to the router, such as powerline adapters.")
    case .routerSilent:
      "Nothing to fix for the connection. If LinkWatch was just installed, allow it in System Settings › Privacy & Security › Local Network."
    case .routerUnreachable:
      "If the internet is not working either, restart "
        + (bridge.map { "the \($0)." } ?? "the device linking the access point to the router.")
        + " Turning on internet reference points lets LinkWatch tell the difference."
    case .internet: "Nothing to fix at home; wait, or contact the provider if it lasts."
    }
  }

  public var isProblem: Bool { self != .allClear }
}
