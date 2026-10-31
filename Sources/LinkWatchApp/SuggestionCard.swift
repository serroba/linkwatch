import LinkWatchCore
import SwiftUI

/// Offers to monitor a newly joined network, or to update a profile whose addresses changed.
struct SuggestionCard: View {
  let suggestion: NetworkSuggestion
  let monitor: MonitorController
  let openSettings: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      switch suggestion {
      case .monitor(let discovery):
        Text("New Wi-Fi network: \(discovery.network.ssid)").font(.headline)
        Text("Router: \(discovery.router ?? "not detected")").font(.caption)
        Text(accessPointText(discovery.accessPoint)).font(.caption)
        let proposed = monitor.proposedProfile(for: discovery)
        if monitor.isHotspot {
          Text("Phone hotspot detected").font(.caption).foregroundStyle(.secondary)
        }
        if proposed == nil {
          Text("Enter the missing address in Settings to monitor this network.")
            .font(.caption).foregroundStyle(.secondary)
        }
        if discovery.accessPoint == .unknown { search }
        actions(accept: "Monitor this network", canAccept: proposed != nil)
      case .update(let current, let proposed):
        Text("\(current.ssid) addresses changed").font(.headline)
        if current.router != proposed.router {
          Text("Router: \(current.router) → \(proposed.router)").font(.caption)
        }
        if current.accessPoint != proposed.accessPoint {
          Text("AP: \(current.accessPoint) → \(proposed.accessPoint)").font(.caption)
        }
        actions(accept: "Update profile", canAccept: true)
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
  }

  @ViewBuilder private var search: some View {
    switch monitor.accessPointSearch {
    case .searching(let hosts):
      HStack {
        ProgressView().controlSize(.small)
        Text("Pinging \(hosts) addresses once…").font(.caption)
      }
    case .idle, .finished:
      if case .finished(let message) = monitor.accessPointSearch {
        Text(message).font(.caption)
      }
      Button("Find AP (pings this subnet once)") {
        Task { await monitor.searchForAccessPoint() }
      }
      .help(
        "Pings each address in this private Wi-Fi subnet once so macOS learns the AP's hardware address. Nothing is probed again until you start monitoring."
      )
    }
  }

  private func actions(accept: String, canAccept: Bool) -> some View {
    HStack {
      if canAccept {
        Button(accept) { monitor.acceptSuggestion() }.keyboardShortcut(.defaultAction)
      } else {
        Button("Open Settings…", action: openSettings)
      }
      Button("Not now") { monitor.dismissSuggestion() }
    }
  }

  private func accessPointText(_ discovery: AccessPointDiscovery) -> String {
    switch discovery {
    case .found(let address): "AP: \(address)"
    case .router: "AP: the router itself; there is no separate AP to compare"
    case .unknown: "AP: not in the Mac's ARP cache"
    }
  }
}
