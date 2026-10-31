import LinkWatchCore
import SwiftUI

/// Which device this Mac is connected through, with a button to check again.
struct PathView: View {
  let monitor: MonitorController

  var body: some View {
    if let profile = monitor.session.profile, !profile.isSingleDevice {
      HStack(alignment: .firstTextBaseline) {
        Text(description).font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Spacer()
        Button("Detect again") { monitor.detectPath() }
          .font(.caption)
          .help("Checks again which device this Mac is connected through. Sends no traffic.")
      }
    }
  }

  private var description: String {
    switch monitor.connectionPath {
    case .accessPoint: "Connected through the access point."
    case .router:
      "Connected to the router's own Wi-Fi; the access point is reached across the bridge."
    case nil: "Working out whether this Mac is connected through the access point or the router."
    }
  }
}
