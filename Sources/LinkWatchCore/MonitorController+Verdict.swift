import Foundation

extension MonitorController {
  /// Moves the verdict only after a new one holds for the alert time (or recovery time when
  /// clearing), so a single slow sample never changes the advice.
  func updateVerdict(at elapsed: TimeInterval) {
    guard let profile = session.profile else { return }
    let thresholds = profile.thresholds
    var evidence = session.window.evidence
    evidence.busy = isBusy
    evidence.weakSignal = signal?.isWeak ?? false
    let observed = Verdict(evidence, thresholds: thresholds)
    guard observed != verdict else {
      pendingVerdict = nil
      return
    }
    if pendingVerdict?.verdict != observed { pendingVerdict = (observed, elapsed) }
    let required =
      observed == .allClear ? thresholds.recoverySeconds : thresholds.sustainedSeconds
    if let pendingVerdict, elapsed - pendingVerdict.since >= required {
      verdict = observed
      self.pendingVerdict = nil
      recordTransitions()
    }
  }

  /// The verdict's sentence and action, named after the current profile's bridge.
  public var advice: (headline: String, action: String?) {
    let bridge = session.profile?.bridgeName
    let hotspot = session.profile?.hotspot ?? false
    return (
      verdict.headline(bridge: bridge, hotspot: hotspot),
      verdict.action(bridge: bridge, hotspot: hotspot)
    )
  }
}

/// The menu bar colour: what the current verdict means for the person looking at it.
public enum StatusLight: String, Codable, Equatable, Sendable {
  /// Not monitoring: paused, unknown network, no permission or no samples yet.
  case idle
  case good
  /// The Mac's own transfer is slowing things; nothing is broken.
  case busy
  case internet
  /// A home link needs action, such as restarting powerline adapters.
  case actionNeeded
  /// The router is not answering LinkWatch; often a permission rather than a fault.
  case routerQuiet
  /// Typical latency is fine but a home link has frequent lag spikes.
  case unstable
}

extension MonitorController {
  public var light: StatusLight {
    guard displayState != .idle else { return .idle }
    switch verdict {
    case .allClear: return .good
    case .busy: return .busy
    case .internet, .internetSpikes: return .internet
    case .accessPointSpikes, .bridgeSpikes: return .unstable
    case .bridge, .accessPoint, .weakSignal: return .actionNeeded
    case .routerSilent, .routerUnreachable: return .routerQuiet
    }
  }
}
