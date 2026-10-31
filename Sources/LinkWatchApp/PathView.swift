import LinkWatchCore
import SwiftUI

/// Which device this Mac is connected through, with a button to check again, or to find an
/// access point the network's profile does not know yet.
struct PathView: View {
  let monitor: MonitorController

  var body: some View {
    if monitor.behindUnknownAccessPoint {
      HStack(alignment: .firstTextBaseline) {
        Text(searchMessage ?? "Connected through an access point LinkWatch does not know yet.")
          .font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Spacer()
        Button(isSearching ? "Searching…" : "Find it") {
          Task { await monitor.searchForAccessPoint() }
        }
        .font(.caption)
        .disabled(isSearching)
        .help(
          "Pings each address on this private network once so the Mac learns the access point's address, then saves it with this network."
        )
      }
    } else if let profile = monitor.session.profile, !profile.isSingleDevice {
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

  private var isSearching: Bool {
    if case .searching = monitor.accessPointSearch { return true }
    return false
  }

  private var searchMessage: String? {
    if case .finished(let message) = monitor.accessPointSearch { return message }
    return nil
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
