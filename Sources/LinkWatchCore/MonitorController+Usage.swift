import Foundation

/// A cumulative counter reading tied to the session it was taken in.
struct TrafficReading {
  let counters: TrafficCounters
  let elapsed: TimeInterval
  let generation: UUID
}

extension MonitorController {
  /// Bytes moved since the previous reading in this session, updating the live rate.
  ///
  /// A counter that went backwards (interface reset) or a new session yields nil rather
  /// than a spike.
  func trafficDelta(on interface: String, at elapsed: TimeInterval) -> TrafficCounters? {
    guard let current = environment.traffic(on: interface) else {
      usage = nil
      lastTraffic = nil
      return nil
    }
    defer {
      lastTraffic = TrafficReading(
        counters: current, elapsed: elapsed, generation: session.generation)
    }
    guard let previous = lastTraffic, previous.generation == session.generation,
      elapsed > previous.elapsed, current.received >= previous.counters.received,
      current.sent >= previous.counters.sent
    else {
      usage = nil
      return nil
    }
    let delta = TrafficCounters(
      received: current.received - previous.counters.received,
      sent: current.sent - previous.counters.sent)
    let seconds = elapsed - previous.elapsed
    let rates = Usage(
      downloadBitsPerSecond: Double(delta.received) * 8 / seconds,
      uploadBitsPerSecond: Double(delta.sent) * 8 / seconds)
    usage = rates
    let rate = max(rates.downloadBitsPerSecond, rates.uploadBitsPerSecond)
    recentRates = Array((recentRates + [rate]).suffix(5))
    sessionPeakRate = max(sessionPeakRate, rate)
    return delta
  }

  /// Whether recent traffic is heavy enough to explain slow responses on this network.
  var isBusy: Bool {
    guard let ssid = session.profile?.ssid, let recent = recentRates.max() else { return false }
    let storedPeak =
      week.minutes.filter { $0.ssid == ssid }.compactMap(\.bitsPerSecond).max() ?? 0
    return Load.isBusy(recent, peak: max(storedPeak, sessionPeakRate))
  }
}
