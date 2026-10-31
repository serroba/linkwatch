import Foundation

/// Recent latency and loss for one target.
public struct TargetEvidence: Equatable, Sendable {
  public var median: Double?
  public var loss: Double
  /// The 95th percentile over about a minute, which reveals lag spikes the median hides.
  public var p95: Double?

  public init(median: Double?, loss: Double, p95: Double? = nil) {
    self.median = median
    self.loss = loss
    self.p95 = p95
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
  /// Whether the Mac was moving enough data to slow the connection by itself.
  public var busy: Bool
  /// Whether the Mac's Wi-Fi signal was weak, which explains a slow access point.
  public var weakSignal = false

  public init(
    accessPoint: TargetEvidence, router: TargetEvidence, internet: TargetEvidence?,
    busy: Bool = false
  ) {
    self.accessPoint = accessPoint
    self.router = router
    self.internet = internet
    self.busy = busy
  }

  /// Evidence for a stored minute; `peakBitsPerSecond` is the busiest minute on that network.
  public init(_ minute: MinuteSummary, peakBitsPerSecond: Double = 0) {
    accessPoint = TargetEvidence(
      median: minute.accessPoint.median, loss: minute.accessPoint.loss, p95: minute.accessPoint.p95)
    router = TargetEvidence(
      median: minute.router.median, loss: minute.router.loss, p95: minute.router.p95)
    internet = minute.internet.map { TargetEvidence(median: $0.median, loss: $0.loss, p95: $0.p95) }
    busy = minute.bitsPerSecond.map { Load.isBusy($0, peak: peakBitsPerSecond) } ?? false
    if let rssi = minute.rssi, let noise = minute.noise {
      weakSignal =
        WiFiSignal(rssi: rssi, noise: noise, transmitRate: 0, channel: nil, band: nil).isWeak
    }
  }
}

/// Decides whether the Mac's own traffic explains slow responses.
enum Load {
  /// Below this rate traffic is too light to slow a home connection.
  static let minimumBusyBitsPerSecond: Double = 1_000_000

  /// Busy means at least 1 Mbit/s and at least half the busiest rate seen on the network,
  /// which adapts to each connection's capacity without a speed test.
  static func isBusy(_ bitsPerSecond: Double, peak: Double) -> Bool {
    bitsPerSecond >= minimumBusyBitsPerSecond && bitsPerSecond >= peak / 2
  }
}

extension MinuteSummary {
  /// The faster direction's average rate over the minute, or nil without traffic data.
  public var bitsPerSecond: Double? {
    guard let received, let sent else { return nil }
    return Double(max(received, sent)) * 8 / 60
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
  /// A link is slow while the Mac itself is moving a lot of data, so nothing is broken.
  case busy
  /// Typical latency is fine but the Wi-Fi link to the access point has frequent spikes.
  case accessPointSpikes
  /// The access point is slow, lossy or spiky while the Mac's Wi-Fi signal is weak.
  case weakSignal
  /// Typical latency is fine but spikes start between the access point and the router.
  case bridgeSpikes
  /// Typical latency is fine but spikes start beyond the router.
  case internetSpikes

  /// Internet references must be slower than the router by this much to blame the provider.
  public static let internetMargin: Double = 100
  /// A link's 95th percentile must exceed the previous link's by this much to count as spiky:
  /// at least one probe in twenty that slow is felt as stutter in calls and games.
  public static let spikeMargin: Double = 100

  /// Classifies evidence with the profile's thresholds; the first failing link wins.
  public init(_ evidence: LinkEvidence, thresholds: Thresholds) {
    let accessPoint = evidence.accessPoint
    let router = evidence.router
    if accessPoint.isLost {
      self = evidence.weakSignal ? .weakSignal : .accessPoint
    } else if (accessPoint.median ?? 0) > thresholds.slow {
      self = evidence.busy ? .busy : evidence.weakSignal ? .weakSignal : .accessPoint
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
      self = evidence.busy ? .busy : .bridge
    } else if let internet = evidence.internet, internet.isLost {
      self = .internet
    } else if let internet = evidence.internet,
      (internet.median ?? 0) - (router.median ?? 0) > Self.internetMargin
    {
      self = evidence.busy ? .busy : .internet
    } else if let spikes = Self.spikes(evidence) {
      self =
        evidence.busy
        ? .busy : spikes == .accessPointSpikes && evidence.weakSignal ? .weakSignal : spikes
    } else {
      self = .allClear
    }
  }

  /// The first link whose worst probes are much slower than the link before it.
  private static func spikes(_ evidence: LinkEvidence) -> Verdict? {
    let accessPoint = evidence.accessPoint.p95 ?? 0
    let router = evidence.router.p95 ?? accessPoint
    if accessPoint > spikeMargin { return .accessPointSpikes }
    if router - accessPoint > spikeMargin { return .bridgeSpikes }
    if let internet = evidence.internet?.p95, internet - router > spikeMargin {
      return .internetSpikes
    }
    return nil
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
    case .busy:
      "The connection is busy with a large download or upload, which slows everything else."
    case .accessPointSpikes: "The Wi-Fi connection has frequent lag spikes."
    case .weakSignal: "The Wi-Fi signal is weak here."
    case .bridgeSpikes:
      "The connection between the access point and the router"
        + (bridge.map { " (\($0))" } ?? "") + " has frequent lag spikes."
    case .internetSpikes: "The internet connection has frequent lag spikes."
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
    case .busy: "Nothing is broken. Wait for the transfer to finish, or pause it."
    case .accessPointSpikes:
      "If calls or video stutter, move closer to the access point; if it continues nearby, restart the access point."
    case .weakSignal:
      "Move closer to the access point or away from walls and metal. Restarting the access point or "
        + (bridge.map { "the \($0)" } ?? "other equipment") + " will not help."
    case .bridgeSpikes:
      "If calls or video stutter, restart "
        + (bridge.map { "the \($0)." } ?? "the device linking the access point to the router.")
        + " Heavy use by other devices at home can cause this too."
    case .internetSpikes: "Nothing to fix at home; if calls stutter for long, contact the provider."
    }
  }

  public var isProblem: Bool { self != .allClear }
}
