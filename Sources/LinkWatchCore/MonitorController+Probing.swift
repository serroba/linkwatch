extension MonitorController {
  /// Probes each address concurrently, keeping the results in the given order.
  nonisolated static func measure(
    _ addresses: [String], over interface: String, with probe: any LatencyProbe
  ) async -> [ProbeOutcome] {
    await withTaskGroup(of: (Int, ProbeOutcome).self) { group in
      for (index, address) in addresses.enumerated() {
        group.addTask { (index, await probe.measure(address: address, interface: interface)) }
      }
      var outcomes = [ProbeOutcome](repeating: .cancelled, count: addresses.count)
      for await (index, outcome) in group { outcomes[index] = outcome }
      return outcomes
    }
  }
}
