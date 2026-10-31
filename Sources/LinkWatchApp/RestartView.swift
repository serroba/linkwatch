import LinkWatchCore
import SwiftUI

/// "I restarted…": records a restart and, a few minutes later, says whether it helped.
struct RestartView: View {
  let monitor: MonitorController

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Menu("I restarted…") {
        ForEach(devices, id: \.self) { device in
          Button("the \(device)") { monitor.restarted(device) }
        }
      }
      .fixedSize()
      .help("Notes the restart so LinkWatch can show whether it helped a few minutes later.")
      if let effect = monitor.restartEffect {
        Text(effect.sentence).font(.caption)
          .foregroundStyle(effect.outcome == .helped ? Color.green : Color.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  /// The most likely device first, then the usual ones.
  private var devices: [String] {
    var list = [monitor.defaultRestartDevice]
    for device in ["router", "access point"] where !list.contains(device) { list.append(device) }
    return list
  }
}
