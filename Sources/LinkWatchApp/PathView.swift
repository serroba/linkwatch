import LinkWatchCore
import SwiftUI

/// Which device this Mac is connected through, with a button to search the network for the
/// access point again.
struct PathView: View {
  let monitor: MonitorController

  var body: some View {
    if let profile = monitor.session.profile, !profile.hotspot,
      monitor.behindUnknownAccessPoint || !profile.isSingleDevice
    {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text(description)
          if let searchStatus { Text(searchStatus) }
        }
        .font(.caption).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        Spacer()
        Button(buttonTitle) {
          Task { await monitor.searchForAccessPoint() }
        }
        .font(.caption)
        .disabled(isSearching)
        .help(
          "Pings each address on this private network once so the Mac learns the access point's address, then checks again which device this Mac is connected through."
        )
      }
    }
  }

  private var isSearching: Bool {
    if case .searching = monitor.accessPointSearch { return true }
    return false
  }

  private var buttonTitle: String {
    switch monitor.accessPointSearch {
    case .searching: "Searching…"
    case .finished: "Search again"
    case .idle: monitor.behindUnknownAccessPoint ? "Find it" : "Search again"
    }
  }

  private var searchStatus: String? {
    switch monitor.accessPointSearch {
    case .searching(let hosts): "Searching \(hosts) addresses for the access point…"
    case .finished(let message): message
    case .idle: nil
    }
  }

  private var description: String {
    if monitor.behindUnknownAccessPoint {
      return "Connected through an access point LinkWatch does not know yet."
    }
    return switch monitor.connectionPath {
    case .accessPoint: "Connected through the access point."
    case .router:
      "Connected to the router's own Wi-Fi; the access point is reached across the bridge."
    case nil: "Working out whether this Mac is connected through the access point or the router."
    }
  }
}
