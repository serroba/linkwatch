public import Foundation

/// Decides when a problem has lasted long enough to notify someone, and when to say it is
/// over, so notifications mean "do something now" rather than reporting every blip.
public struct ProblemAlerts: Sendable {
  public struct Notice: Equatable, Sendable {
    public var title: String
    public var body: String
  }

  /// How long a problem must last before notifying.
  public static let problemSeconds: TimeInterval = 180
  /// How long the connection must be clear before "back to normal".
  public static let recoverySeconds: TimeInterval = 60

  private var problemSince: TimeInterval?
  private var notified = false
  private var clearSince: TimeInterval?

  public init() {}

  /// Outages and slow links that need someone to act or wait; spikes, a busy Mac and a
  /// router that only ignores pings stay in the panel.
  static func notifies(_ verdict: Verdict) -> Bool {
    switch verdict {
    case .accessPoint, .bridge, .routerUnreachable, .internet, .weakSignal: true
    default: false
    }
  }

  /// Feeds the live verdict; returns a notice when one is due. `advice` is the verdict's
  /// headline and action, so notices match the panel.
  public mutating func update(
    verdict: Verdict, monitoring: Bool, advice: (headline: String, action: String?),
    now: TimeInterval
  ) -> Notice? {
    guard monitoring else {
      self = ProblemAlerts()
      return nil
    }
    if Self.notifies(verdict) {
      clearSince = nil
      let since = problemSince ?? now
      problemSince = since
      guard !notified, now - since >= Self.problemSeconds else { return nil }
      notified = true
      return Notice(title: advice.headline, body: advice.action ?? "")
    }
    problemSince = nil
    guard notified, verdict == .allClear else {
      clearSince = nil
      return nil
    }
    let since = clearSince ?? now
    clearSince = since
    guard now - since >= Self.recoverySeconds else { return nil }
    self = ProblemAlerts()
    return Notice(title: "Back to normal", body: "The connection is working normally again.")
  }
}
