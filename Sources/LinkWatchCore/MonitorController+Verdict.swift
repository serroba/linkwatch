import Foundation

extension MonitorController {
  /// Moves the verdict only after a new one holds for the alert time (or recovery time when
  /// clearing), so a single slow sample never changes the advice.
  func updateVerdict(at elapsed: TimeInterval) {
    guard let profile = session.profile else { return }
    let thresholds = profile.thresholds
    var evidence = session.window.evidence
    evidence.busy = isBusy
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
    }
  }

  /// The verdict's sentence and action, named after the current profile's bridge.
  public var advice: (headline: String, action: String?) {
    let bridge = session.profile?.bridgeName
    return (verdict.headline(bridge: bridge), verdict.action(bridge: bridge))
  }
}
