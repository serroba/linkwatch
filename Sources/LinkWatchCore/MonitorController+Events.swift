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

  /// The device a restart most likely concerns: the named bridge, the phone on a hotspot,
  /// or the router.
  public var defaultRestartDevice: String {
    let profile = session.profile ?? profiles.first { $0.ssid == network?.ssid }
    if let bridge = profile?.bridgeName { return bridge }
    return profile?.hotspot == true ? "phone" : "router"
  }

  /// Records that a device was restarted now, so its effect can be shown a few minutes later.
  @discardableResult
  public func restarted(_ text: String? = nil) -> String {
    let device = text.flatMap(AppEvent.markLabel) ?? defaultRestartDevice
    let event = AppEvent(time: now(), kind: .restarted, detail: device)
    try? events.append(event)
    lastRestart = event
    return device
  }

  /// The effect of the latest restart, shown for an hour after it.
  public var restartEffect: RestartEffect? {
    guard let lastRestart, now().timeIntervalSince(lastRestart.time) < 3600 else { return nil }
    return RestartEffect(
      time: lastRestart.time, device: lastRestart.detail ?? defaultRestartDevice,
      minutes: week.minutes)
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
