import Testing

@testable import LinkWatchCore

private func pair(_ elapsed: Double, accessPoint: Double = 1, router: Double = 2) -> ProbePair {
  ProbePair(
    elapsed: elapsed, accessPoint: .success(milliseconds: accessPoint),
    router: .success(milliseconds: router)
  )
}

@Test func sustainedDifferenceAndRecovery() {
  var window = MonitoringWindow()
  for elapsed in stride(from: 0.0, through: 8, by: 2) {
    window.append(pair(elapsed, router: 50))
    #expect(window.health == .healthy)
  }
  window.append(pair(10, router: 50))
  #expect(window.health == .routerSlower)
  for elapsed in stride(from: 12.0, through: 20, by: 2) {
    window.append(pair(elapsed))
    #expect(window.health == .routerSlower)
  }
  window.append(pair(22))
  #expect(window.health == .healthy)
}

@Test func spikeAndSamplingGapDoNotTriggerAlert() {
  var window = MonitoringWindow()
  window.append(pair(0))
  window.append(pair(2, router: 100))
  window.append(pair(4))
  #expect(window.health == .healthy)
  var gap = MonitoringWindow()
  gap.append(pair(0, router: 50))
  gap.append(pair(20, router: 50))
  #expect(gap.health == .healthy)
  #expect(gap.pendingSince == 20)
}

@Test func failuresAndCancellationAreExplicit() {
  var window = MonitoringWindow()
  window.append(pair(0))
  window.append(ProbePair(elapsed: 2, accessPoint: .timeout, router: .failure))
  #expect(window.health == .unreachable(accessPoint: true, router: true))
  #expect(window.accessPointLoss == 0.5)
  window.append(ProbePair(elapsed: 4, accessPoint: .cancelled, router: .timeout))
  #expect(window.samples.count == 2)
  window.append(pair(1))
  #expect(window.samples.count == 2)
}

@Test func boundedHistoryAndMedian() {
  var window = MonitoringWindow(capacity: 5)
  for index in 0..<20 { window.append(pair(Double(index), router: Double(index))) }
  #expect(window.samples.count == 5)
  #expect(window.routerMedian == 17)
  #expect(ProbeOutcome.success(milliseconds: .nan).latency == nil)
  #expect(ProbeOutcome.success(milliseconds: -1).latency == nil)
}

@Test func bothSlowAndInvalidThresholds() {
  var thresholds = Thresholds()
  thresholds.recoveryDifference = 25
  #expect(!thresholds.isValid)
  var window = MonitoringWindow(thresholds: thresholds)
  #expect(window.thresholds == Thresholds())
  for elapsed in stride(from: 0.0, through: 10, by: 2) {
    window.append(pair(elapsed, accessPoint: 50, router: 60))
  }
  #expect(window.health == .bothSlow)
}

@Test func unreachableClearsWhenBothTargetsReplyAgain() {
  var window = MonitoringWindow()
  for elapsed in stride(from: 0.0, through: 8, by: 2) {
    window.append(pair(elapsed, accessPoint: 5, router: 20))
  }
  window.append(ProbePair(elapsed: 10, accessPoint: .success(milliseconds: 5), router: .timeout))
  #expect(window.health == .unreachable(accessPoint: false, router: true))
  window.append(pair(12, accessPoint: 5, router: 20))
  #expect(window.health == .healthy)
}

@Test func singleFailureDoesNotDiscardActiveAlert() {
  var window = MonitoringWindow()
  for elapsed in stride(from: 0.0, through: 10, by: 2) {
    window.append(pair(elapsed, router: 50))
  }
  #expect(window.health == .routerSlower)
  window.append(ProbePair(elapsed: 12, accessPoint: .timeout, router: .success(milliseconds: 50)))
  #expect(window.health == .unreachable(accessPoint: true, router: false))
  window.append(pair(14, router: 50))
  #expect(window.health == .routerSlower)
}

@Test func displayHistoryOutlivesStatisticsWindow() {
  var window = MonitoringWindow(capacity: 5, historyCapacity: 8)
  for index in 0..<20 { window.append(pair(Double(index))) }
  #expect(window.samples.count == 5)
  #expect(window.history.count == 8)
  #expect(window.history.first?.elapsed == 12)
  window.append(ProbePair(elapsed: 21, accessPoint: .cancelled, router: .timeout))
  #expect(window.history.count == 8)
  #expect(MonitoringWindow(capacity: 60, historyCapacity: 10).historyCapacity == 60)
}
