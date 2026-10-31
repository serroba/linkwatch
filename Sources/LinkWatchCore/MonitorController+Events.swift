import Foundation

extension MonitorController {
  /// Records an event now; recording never interrupts monitoring.
  public func record(_ kind: AppEvent.Kind, detail: String? = nil) {
    try? events.append(AppEvent(time: now(), kind: kind, detail: detail))
  }

  /// Notes what the person was doing, for example "desk moved"; returns false for empty text.
  @discardableResult
  public func mark(_ text: String) -> Bool {
    guard let label = AppEvent.markLabel(text) else { return false }
    record(.marked, detail: label)
    return true
  }

  /// Records what changed since the last observation, so the event log stays a list of
  /// transitions rather than repeated state.
  func recordTransitions() {
    let current = ObservedState(
      permitted: environment.isPermitted, ssid: network?.ssid, bssid: network?.bssid,
      monitoring: session.profile?.ssid, paused: paused, sleeping: sleeping, verdict: verdict)
    guard current != observed else { return }
    for (kind, detail) in current.events(since: observed, reason: reason) {
      record(kind, detail: detail)
    }
    observed = current
  }
}
