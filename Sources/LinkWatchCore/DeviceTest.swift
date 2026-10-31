public import Foundation

/// One step of a guided device test.
public enum DeviceTestPhase: String, Codable, Equatable, Sendable, CaseIterable {
  case baseline
  case deviceOn = "on"
  case deviceOff = "off"

  /// What the person should do during this phase.
  public func instruction(device: String) -> String {
    switch self {
    case .baseline: "Leave the \(device) off and use the Mac as usual."
    case .deviceOn: "Turn the \(device) on now, or keep it moving."
    case .deviceOff: "Turn the \(device) off now."
    }
  }
}

/// Link quality during one phase, from the raw two-second probes.
public struct DeviceTestPhaseResult: Codable, Equatable, Sendable {
  public var phase: DeviceTestPhase
  public var samples: Int
  public var accessPoint: TargetSummary
  public var router: TargetSummary
  public var internet: TargetSummary?

  init(_ phase: DeviceTestPhase, pairs: [ProbePair]) {
    self.phase = phase
    samples = pairs.count
    accessPoint = TargetSummary(pairs.map(\.accessPoint))
    router = TargetSummary(pairs.map(\.router))
    let internet = pairs.compactMap(\.internetBest)
    self.internet = internet.isEmpty ? nil : TargetSummary(internet)
  }

  var spikes: LinkSpikes {
    LinkSpikes(
      accessPoint: accessPoint.p95, router: router.p95, internet: internet?.p95,
      routerLoss: router.loss)
  }
}

/// The outcome of a guided device test.
public struct DeviceTestResult: Codable, Equatable, Sendable {
  public var device: String
  public var phases: [DeviceTestPhaseResult]
  /// One plain sentence naming the affected link, if any.
  public var conclusion: String

  /// Compares the on phase with the calmer of the phases before and after it.
  init(device: String, phases: [DeviceTestPhaseResult]) {
    self.device = device
    self.phases = phases
    let byPhase = Dictionary(phases.map { ($0.phase, $0) }) { first, _ in first }
    guard let baseline = byPhase[.baseline], let active = byPhase[.deviceOn],
      let off = byPhase[.deviceOff]
    else {
      conclusion = "The test did not complete."
      return
    }
    func calmer(_ first: Double?, _ second: Double?) -> Double? {
      [first, second].compactMap { $0 }.min()
    }
    let reference = LinkSpikes(
      accessPoint: calmer(baseline.accessPoint.p95, off.accessPoint.p95),
      router: calmer(baseline.router.p95, off.router.p95),
      internet: calmer(baseline.internet?.p95, off.internet?.p95),
      routerLoss: min(baseline.router.loss, off.router.loss))
    let affected = AffectedLink(during: active.spikes, reference: reference)
    guard affected != .none else {
      conclusion = "No clear effect while the \(device) was on."
      return
    }
    let recovered = AffectedLink(during: off.spikes, reference: baseline.spikes) == .none
    conclusion =
      "The \(device) most likely disturbs \(affected.linkName)."
      + (recovered
        ? " It recovered once it was off." : " It had not recovered 30 s after turning it off.")
  }
}

/// Progress of a guided device test.
public enum DeviceTestState: Equatable, Sendable {
  case idle
  case running(device: String, phase: DeviceTestPhase, phaseStart: TimeInterval)
  case finished(DeviceTestResult)
  case cancelled(String)

  /// Seconds each phase lasts: fifteen paired probes.
  public static let phaseSeconds: TimeInterval = 30
  /// Probes a phase needs for a meaningful comparison.
  public static let minimumSamples = 10
}

/// The device test as reported by `status`.
public struct DeviceTestReport: Codable, Equatable, Sendable {
  /// `running`, `finished` or `cancelled`.
  public var state: String
  public var device: String?
  public var phase: DeviceTestPhase?
  public var instruction: String?
  public var secondsLeft: Int?
  /// The conclusion when finished, or the reason when cancelled.
  public var message: String?
  public var result: DeviceTestResult?

  @MainActor
  init?(controller: MonitorController, now: TimeInterval) {
    switch controller.deviceTest {
    case .idle:
      return nil
    case .running(let device, let phase, _):
      state = "running"
      self.device = device
      self.phase = phase
      instruction = phase.instruction(device: device)
      secondsLeft = controller.deviceTestSecondsLeft(now: now)
    case .finished(let result):
      state = "finished"
      device = result.device
      message = result.conclusion
      self.result = result
    case .cancelled(let reason):
      state = "cancelled"
      message = reason
    }
  }

  var summary: String {
    if let phase, let device, let instruction {
      return "\(device), \(phase.rawValue) phase, \(secondsLeft ?? 0) s left: \(instruction)"
    }
    return message ?? state
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(state, forKey: .state)
    try container.encode(device, forKey: .device)
    try container.encode(phase, forKey: .phase)
    try container.encode(instruction, forKey: .instruction)
    try container.encode(secondsLeft, forKey: .secondsLeft)
    try container.encode(message, forKey: .message)
    try container.encode(result, forKey: .result)
  }
}
