import LinkWatchCore
import SwiftUI

/// Next to "Use current Wi-Fi": says whether the Mac is behind an access point and offers to
/// find its address when the ARP cache does not know it yet.
struct FindAccessPointRow: View {
  let monitor: MonitorController
  @Binding var accessPoint: String

  var body: some View {
    if let discovery = monitor.discovery, monitor.network != nil {
      switch discovery.accessPoint {
      case .found(let address) where accessPoint != address:
        HStack {
          Text("This Mac is connected through the access point \(address).").font(.caption)
          Spacer()
          Button("Use it") { accessPoint = address }
        }
      case .router:
        searchRow(
          "This Mac is on the router's own Wi-Fi here, so there is no access point to find.")
      case .unknown:
        searchRow(
          discovery.behindAccessPoint
            ? "This Mac is connected through an access point whose address is not known yet."
            : "LinkWatch cannot tell yet whether this Mac is connected through an access point.")
      case .found:
        searchRow("This Mac is connected through the access point in this profile.")
      }
    }
  }

  private func searchRow(_ prompt: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(searchMessage ?? prompt).font(.caption).fixedSize(horizontal: false, vertical: true)
      Spacer()
      Button(isSearching ? "Searching…" : "Find access point") { find() }
        .disabled(isSearching)
        .help(
          "Pings each address on this private network once so the Mac learns the access point's address."
        )
    }
  }

  private var searchMessage: String? {
    if case .finished(let message) = monitor.accessPointSearch { return message }
    return nil
  }

  private var isSearching: Bool {
    if case .searching = monitor.accessPointSearch { return true }
    return false
  }

  private func find() {
    Task {
      await monitor.searchForAccessPoint()
      if case .found(let address) = monitor.discovery?.accessPoint { accessPoint = address }
    }
  }
}
