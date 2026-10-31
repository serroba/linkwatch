public import Foundation

extension MonitorController {
  /// Starts a guided test of a device, such as an electric desk; returns false when the
  /// network is not being monitored or a test is already running.
  @discardableResult
  public func startDeviceTest(_ text: String) -> Bool {
    if case .running = deviceTest { return false }
    guard let device = AppEvent.markLabel(text) else { return false }
    guard session.profile != nil, !session.window.samples.isEmpty else {
      deviceTest = .cancelled("Start monitoring a network before testing a device.")
      return false
    }
    deviceTestBounds = [:]
    deviceTest = .running(device: device, phase: .baseline, phaseStart: uptime())
    record(.deviceTest, detail: "\(device): started")
    return true
  }

  /// Clears a finished or cancelled test from view.
  public func dismissDeviceTest() {
    if case .running = deviceTest { return }
    deviceTest = .idle
  }

  /// Seconds left in the current phase, for countdowns.
  public func deviceTestSecondsLeft(now: TimeInterval) -> Int? {
    guard case .running(_, _, let start) = deviceTest else { return nil }
    return max(0, Int((start + DeviceTestState.phaseSeconds - now).rounded(.up)))
  }

  func advanceDeviceTest(at elapsed: TimeInterval) {
    guard case .running(let device, let phase, let start) = deviceTest,
      elapsed - start >= DeviceTestState.phaseSeconds
    else { return }
    deviceTestBounds[phase] = start...elapsed
    let phases = DeviceTestPhase.allCases
    if let index = phases.firstIndex(of: phase), index + 1 < phases.count {
      let next = phases[index + 1]
      deviceTest = .running(device: device, phase: next, phaseStart: elapsed)
      record(.deviceTest, detail: "\(device): \(next.rawValue)")
      return
    }
    finishDeviceTest(device)
  }

  private func finishDeviceTest(_ device: String) {
    let results = DeviceTestPhase.allCases.map { phase in
      let bounds = deviceTestBounds[phase] ?? 0...0
      let pairs = session.window.history.filter {
        $0.elapsed > bounds.lowerBound && $0.elapsed <= bounds.upperBound
      }
      return DeviceTestPhaseResult(phase, pairs: pairs)
    }
    guard results.allSatisfy({ $0.samples >= DeviceTestState.minimumSamples }) else {
      deviceTest = .cancelled("Too few measurements for a reliable comparison; try again.")
      record(.deviceTest, detail: "\(device): too few measurements")
      return
    }
    let result = DeviceTestResult(device: device, phases: results)
    deviceTest = .finished(result)
    record(.deviceTest, detail: "\(device): \(result.conclusion)")
  }

  func cancelDeviceTest(_ reason: String) {
    guard case .running(let device, _, _) = deviceTest else { return }
    deviceTest = .cancelled(reason)
    record(.deviceTest, detail: "\(device): cancelled")
  }
}
