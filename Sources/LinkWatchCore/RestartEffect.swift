public import Foundation

/// Typical latency and loss per link over a few stored minutes.
public struct LinkLevels: Codable, Equatable, Sendable {
  public var minutes: Int
  /// Medians of the minutes' medians.
  public var accessPoint: Double?
  public var router: Double?
  public var internet: Double?
  /// Mean loss over the minutes.
  public var routerLoss: Double
  public var internetLoss: Double?

  init(_ minutes: [MinuteSummary]) {
    self.minutes = minutes.count
    accessPoint = Self.median(minutes.compactMap(\.accessPoint.median))
    router = Self.median(minutes.compactMap(\.router.median))
    let internetMinutes = minutes.compactMap(\.internet)
    internet = Self.median(internetMinutes.compactMap(\.median))
    routerLoss = Self.mean(minutes.map(\.router.loss)) ?? 0
    internetLoss = Self.mean(internetMinutes.map(\.loss))
  }

  private static func median(_ values: [Double]) -> Double? {
    let sorted = values.sorted()
    return sorted.isEmpty ? nil : sorted[sorted.count / 2]
  }

  private static func mean(_ values: [Double]) -> Double? {
    values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(minutes, forKey: .minutes)
    try container.encode(accessPoint, forKey: .accessPoint)
    try container.encode(router, forKey: .router)
    try container.encode(internet, forKey: .internet)
    try container.encode(routerLoss, forKey: .routerLoss)
    try container.encode(internetLoss, forKey: .internetLoss)
  }
}

/// How the links compare before and after a person restarted a device.
public struct RestartEffect: Codable, Equatable, Sendable {
  public enum Outcome: String, Codable, Sendable {
    /// Not enough minutes after the restart yet.
    case measuring
    /// Nothing was recorded before the restart to compare with.
    case noBaseline
    case helped
    case worse
    case noChange
  }

  /// Minutes compared on each side of the restart.
  public static let window: TimeInterval = 600
  /// Minutes skipped after the restart while the device boots.
  public static let settle: TimeInterval = 120
  /// Minutes after the restart needed before judging it.
  public static let minimumMinutes = 3

  public var time: Date
  public var device: String
  public var before: LinkLevels
  public var after: LinkLevels
  public var outcome: Outcome
  /// One plain sentence naming the links that changed.
  public var sentence: String

  /// Compares the minutes wholly before the restart with those after it has settled.
  public init(time: Date, device: String, minutes: [MinuteSummary]) {
    self.time = time
    self.device = device
    before = LinkLevels(
      minutes.filter {
        $0.start >= time.addingTimeInterval(-Self.window) && $0.start.addingTimeInterval(60) <= time
      })
    let afterStart = time.addingTimeInterval(Self.settle)
    after = LinkLevels(
      minutes.filter {
        $0.start >= afterStart && $0.start < afterStart.addingTimeInterval(Self.window)
      })
    let changes = Self.changes(before: before, after: after)
    outcome =
      if before.minutes == 0 {
        .noBaseline
      } else if after.minutes < Self.minimumMinutes {
        .measuring
      } else if changes.contains(where: \.improved) && !changes.contains(where: \.worsened) {
        .helped
      } else if changes.contains(where: \.worsened) {
        .worse
      } else {
        .noChange
      }
    sentence = Self.sentence(outcome, device: device, changes: changes)
  }

  /// One effect per restart event, oldest first.
  public static func effects(events: [AppEvent], minutes: [MinuteSummary]) -> [RestartEffect] {
    events.filter { $0.kind == .restarted }.map {
      RestartEffect(time: $0.time, device: $0.detail ?? "device", minutes: minutes)
    }
  }

  /// One link's typical value before and after.
  struct Change {
    var link: String
    var before: Double
    var after: Double
    var unit: String
    /// The smallest change worth naming, in the unit.
    var margin: Double

    /// At least the margin better and, for latency, at least halved.
    var improved: Bool {
      before - after >= margin && (unit == "%" || after <= before / 2)
    }
    var worsened: Bool {
      after - before >= margin && (unit == "%" || after >= before * 2)
    }

    var text: String {
      unit == "%"
        ? String(format: "%@ loss %.0f%% → %.0f%%", link, before * 100, after * 100)
        : String(format: "%@ %.0f → %.0f ms", link, before, after)
    }
  }

  static func changes(before: LinkLevels, after: LinkLevels) -> [Change] {
    func latency(_ link: String, _ first: Double?, _ second: Double?) -> Change? {
      guard let first, let second else { return nil }
      return Change(link: link, before: first, after: second, unit: "ms", margin: 10)
    }
    func loss(_ link: String, _ first: Double?, _ second: Double?) -> Change? {
      guard let first, let second else { return nil }
      return Change(link: link, before: first, after: second, unit: "%", margin: 0.1)
    }
    return [
      latency("AP", before.accessPoint, after.accessPoint),
      latency("router", before.router, after.router),
      loss("router", before.routerLoss, after.routerLoss),
      latency("internet", before.internet, after.internet),
      loss("internet", before.internetLoss, after.internetLoss),
    ].compactMap { $0 }
  }

  private static func sentence(_ outcome: Outcome, device: String, changes: [Change]) -> String {
    let notable = changes.filter { $0.improved || $0.worsened }
    let evidence = (notable.isEmpty ? changes.filter { $0.unit == "ms" } : notable)
      .map(\.text).joined(separator: ", ")
    return switch outcome {
    case .measuring:
      "Measuring the effect of restarting the \(device); check again in a few minutes."
    case .noBaseline: "Nothing was measured before restarting the \(device) to compare with."
    case .helped: "Restarting the \(device) helped: \(evidence)."
    case .worse: "The connection got worse after restarting the \(device): \(evidence)."
    case .noChange:
      "Restarting the \(device) made no clear difference (\(evidence)); if there was a problem, it lies elsewhere."
    }
  }
}
