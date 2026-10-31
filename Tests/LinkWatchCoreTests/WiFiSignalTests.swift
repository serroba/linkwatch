import Foundation
import Testing

@testable import LinkWatchCore

private func signal(_ rssi: Int, noise: Int = -94) -> WiFiSignal {
  WiFiSignal(rssi: rssi, noise: noise, transmitRate: 866, channel: 44, band: "5 GHz")
}

@Test func signalQualityBands() {
  #expect(signal(-48).quality == "excellent")
  #expect(signal(-62).quality == "good")
  #expect(signal(-68).quality == "fair")
  #expect(signal(-74).quality == "weak")
  #expect(signal(-60, noise: -75).quality == "weak")
  #expect(signal(-48).snr == 46)
  #expect(
    signal(-48).summary == "-48 dBm (excellent) · SNR 46 dB · 866 Mbit/s · channel 44 (5 GHz)")
}

@Test func aWeakSignalExplainsASlowAccessPoint() {
  var evidence = LinkEvidence(
    accessPoint: TargetEvidence(median: 45, loss: 0), router: TargetEvidence(median: 50, loss: 0),
    internet: TargetEvidence(median: 55, loss: 0))
  #expect(Verdict(evidence, thresholds: Thresholds()) == .accessPoint)
  evidence.weakSignal = true
  #expect(Verdict(evidence, thresholds: Thresholds()) == .weakSignal)
  evidence.accessPoint = TargetEvidence(median: 3, loss: 0, p95: 250)
  evidence.router = TargetEvidence(median: 8, loss: 0, p95: 260)
  #expect(Verdict(evidence, thresholds: Thresholds()) == .weakSignal)
  evidence.busy = true
  #expect(Verdict(evidence, thresholds: Thresholds()) == .busy)
  #expect(
    Verdict.weakSignal.action(bridge: "TP-Link powerline adapters")
      == "Move closer to the access point or away from walls and metal. Restarting the access point or the TP-Link powerline adapters will not help."
  )
  #expect(Verdict.weakSignal.family == Verdict.accessPoint.family)
}

@MainActor
@Test func signalIsStoredPerMinuteAndShapesTheVerdict() async {
  let harness = Harness()
  harness.environment.wifiSignal = signal(-76)
  harness.script.outcomes["192.0.2.2"] = .success(milliseconds: 60)
  harness.script.outcomes["192.0.2.1"] = .success(milliseconds: 65)
  for _ in 0..<31 { _ = await harness.cycle() }
  #expect(harness.controller.signal == signal(-76))
  #expect(harness.controller.verdict == .weakSignal)
  #expect(harness.controller.light == .actionNeeded)
  let minute = harness.history.saved.first
  #expect(minute?.rssi == -76)
  #expect(minute?.noise == -94)
  #expect(minute?.transmitRate == 866)
  if let minute {
    #expect(Verdict(LinkEvidence(minute), thresholds: Thresholds()) == .weakSignal)
  }
  let status = StatusReport(controller: harness.controller, now: harness.clock.now)
  #expect(status.text.contains("Signal:      -76 dBm (weak) · SNR 18 dB"))
  let report = DiagnoseReport(
    status: status, appRunning: true, minutes: harness.history.saved, profiles: [homeProfile],
    hours: 1, now: harness.clock.date, primaryInterface: nil)
  #expect(report.notes.contains { $0.hasPrefix("The Wi-Fi signal is weak (-76 dBm, SNR 18 dB)") })
  #expect(report.hourly.first?.rssi == -76)
  harness.controller.paused = true
  #expect(harness.controller.signal == nil)
}

@Test func signalSummaryAndJSONListEveryField() throws {
  let full = WiFiSignal(rssi: -50, noise: -95, transmitRate: 866.7, channel: 36, band: "5 GHz")
  #expect(full.summary == "-50 dBm (excellent) · SNR 45 dB · 866 Mbit/s · channel 36 (5 GHz)")
  let bare = WiFiSignal(rssi: -50, noise: -95, transmitRate: 144, channel: nil, band: nil)
  #expect(bare.summary == "-50 dBm (excellent) · SNR 45 dB · 144 Mbit/s")
  let json = String(bytes: try JSONEncoder().encode(bare), encoding: .utf8) ?? ""
  #expect(json.contains("\"channel\":null") && json.contains("\"band\":null"))
  #expect(try JSONDecoder().decode(WiFiSignal.self, from: Data(json.utf8)) == bare)
}
