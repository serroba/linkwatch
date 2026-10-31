import Foundation
import LinkWatchCore
import SwiftUI

/// The panel's guided device test: as usual, device on, device off, then the conclusion.
struct DeviceTestView: View {
  let monitor: MonitorController
  @Binding var device: String

  var body: some View {
    switch monitor.deviceTest {
    case .idle:
      HStack {
        TextField("Device to test, e.g. desk", text: $device)
          .textFieldStyle(.roundedBorder).font(.caption)
        Button("Test") { monitor.startDeviceTest(device) }
          .disabled(AppEvent.markLabel(device) == nil)
          .help(
            "A 90-second test: 30 s as usual, 30 s with the device on, 30 s off. LinkWatch then says which link, if any, it disturbs."
          )
      }
    case .running(let name, let phase, _):
      TimelineView(.periodic(from: .now, by: 1)) { _ in
        let left = monitor.deviceTestSecondsLeft(now: ProcessInfo.processInfo.systemUptime) ?? 0
        VStack(alignment: .leading, spacing: 2) {
          Text("Testing the \(name): \(phase.rawValue), \(left) s left").font(.caption)
            .foregroundStyle(.secondary)
          Text(phase.instruction(device: name)).font(.headline)
        }
      }
    case .finished(let result):
      outcome(result.conclusion)
    case .cancelled(let reason):
      outcome(reason)
    }
  }

  private func outcome(_ message: String) -> some View {
    HStack(alignment: .top) {
      Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
      Spacer()
      Button("Done") { monitor.dismissDeviceTest() }
    }
  }
}
