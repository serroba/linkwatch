import AppKit
import Charts
import Combine
import Foundation
import LinkWatchCore
import SwiftUI

struct LinkWatchApp: App {
  @StateObject private var monitor = Monitor.forInterface()

  var body: some Scene {
    MenuBarExtra {
      DetailView(monitor: monitor.controller)
    } label: {
      let controller = monitor.controller
      // A menu bar label renders only one image and one text, so the values share a Text.
      Label {
        Text(
          "AP \(latencyText(controller.accessPointLatency)) · R \(latencyText(controller.routerLatency)) ms"
        )
        .monospacedDigit()
      } icon: {
        Image(systemName: controller.displayState.symbol)
          .foregroundStyle(controller.displayState.color)
      }
      .labelStyle(.titleAndIcon)
      .accessibilityLabel("LinkWatch: \(controller.reason)")
    }
    .menuBarExtraStyle(.window)
    Window("LinkWatch Settings", id: "settings") {
      ProfileSettings(monitor: monitor.controller, environment: monitor.environment)
    }
    .defaultSize(width: 480, height: 620)
  }
}

private func latencyText(_ value: Double?) -> String {
  value.map { String(format: "%.0f", $0) } ?? "—"
}

extension DisplayState {
  fileprivate var color: Color {
    switch self {
    case .idle: .gray
    case .healthy: .green
    case .routerSlower: .red
    case .bothSlow: .orange
    case .unreachable: .purple
    }
  }

  fileprivate var symbol: String {
    switch self {
    case .idle: "pause.circle.fill"
    case .healthy: "checkmark.circle.fill"
    case .routerSlower, .bothSlow: "exclamationmark.triangle.fill"
    case .unreachable: "xmark.octagon.fill"
    }
  }
}

/// The span shown by the panel's history chart.
private enum ChartRange: String, CaseIterable, Identifiable {
  case hour = "1 h"
  case day = "24 h"
  case week = "7 d"

  var id: Self { self }
  var seconds: TimeInterval { self == .day ? 86_400 : 604_800 }
}

@MainActor
private final class DetailOptions: ObservableObject {
  @Published var range = ChartRange.hour
}

private struct DetailView: View {
  @Bindable var monitor: MonitorController
  @StateObject private var options = DetailOptions()
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Image(systemName: monitor.displayState.symbol)
          .foregroundStyle(monitor.displayState.color)
        Text("LinkWatch").font(.headline)
        Spacer()
        Text("Every 2 seconds").font(.caption).foregroundStyle(.secondary)
      }
      if monitor.session.profile != nil, !monitor.session.window.samples.isEmpty {
        let advice = monitor.advice
        Text(advice.headline).font(.headline).fixedSize(horizontal: false, vertical: true)
        if let action = advice.action {
          Text(action).fixedSize(horizontal: false, vertical: true)
        }
      }
      Text(monitor.reason).font(.caption).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      if let suggestion = monitor.suggestion {
        SuggestionCard(suggestion: suggestion, monitor: monitor) {
          openWindow(id: "settings")
          NSApp.activate(ignoringOtherApps: true)
        }
      }
      HStack {
        metric("Configured AP", value: monitor.accessPointLatency)
        Spacer()
        metric("Router", value: monitor.routerLatency)
        if monitor.session.profile?.internetReferences == true {
          Spacer()
          metric("Internet", value: monitor.session.window.internetMedian)
        }
      }
      if let accessPoint = monitor.accessPointLatency, let router = monitor.routerLatency {
        Text(String(format: "Router − AP: %+.1f ms", router - accessPoint)).monospacedDigit()
      }
      if let profile = monitor.session.profile {
        Text(profile.ssid).font(.headline)
        Text("AP \(profile.accessPoint) · Router \(profile.router)").font(.caption)
        Text("Associated BSSID: \(monitor.network?.bssid ?? "Unavailable")").font(.caption)
        Text("The configured AP may differ from the currently associated device.")
          .font(.caption).foregroundStyle(.secondary)
        Text(
          String(
            format: "Packet loss, last 2 min — AP %.0f%% · Router %.0f%%",
            monitor.session.window.accessPointLoss * 100,
            monitor.session.window.routerLoss * 100))
        Picker("History", selection: $options.range) {
          ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        if options.range == .hour {
          HistoryChart(history: monitor.session.window.history)
        } else {
          let cutoff = Date().addingTimeInterval(-options.range.seconds)
          WeekChart(minutes: monitor.week.minutes.filter { $0.start >= cutoff })
        }
        if monitor.session.window.health != .healthy {
          TimelineView(.periodic(from: .now, by: 1)) { _ in
            let seconds = Int(ProcessInfo.processInfo.systemUptime - monitor.healthSince)
            Text("Current alert for \(seconds) seconds").font(.caption)
          }
        } else if let since = monitor.session.window.pendingSince,
          let latest = monitor.session.window.samples.last
        {
          Text("Evaluating degradation: \(Int(latest.elapsed - since)) seconds").font(.caption)
        }
      }
      Divider()
      Toggle("Pause monitoring", isOn: $monitor.paused)
      HStack {
        Button("Settings…") {
          openWindow(id: "settings")
          NSApp.activate(ignoringOtherApps: true)
        }
        Spacer()
        Button("Quit") { NSApp.terminate(nil) }
      }
    }
    .padding(18)
    .frame(width: 360)
  }

  private func metric(_ title: String, value: Double?) -> some View {
    VStack(alignment: .leading) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      Text("\(latencyText(value)) ms").font(.title2).monospacedDigit()
    }
  }
}

private struct SuggestionCard: View {
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
        if discovery.proposedProfile == nil {
          Text("Enter the missing address in Settings to monitor this network.")
            .font(.caption).foregroundStyle(.secondary)
        }
        if discovery.accessPoint == .unknown { search }
        actions(accept: "Monitor this network", canAccept: discovery.proposedProfile != nil)
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

@MainActor
private final class ProfileEditor: ObservableObject {
  @Published var draft = NetworkProfile(ssid: "", accessPoint: "", router: "")
  @Published var message = ""
  @Published var confirmingClear = false
}

private struct ProfileSettings: View {
  let monitor: MonitorController
  let environment: SystemEnvironment
  @StateObject private var editor = ProfileEditor()

  var body: some View {
    Form {
      Section("Wi-Fi identity") {
        Text(
          "macOS requires Location permission to reveal the Wi-Fi name. LinkWatch never requests location coordinates."
        )
        Button("Allow Wi-Fi identification") { environment.requestPermission() }
        Text(monitor.network?.ssid ?? "Wi-Fi identity unavailable").foregroundStyle(.secondary)
      }
      Section("Selected networks") {
        if monitor.profiles.isEmpty { Text("No networks selected. No probes will be sent.") }
        ForEach(monitor.profiles) { profile in
          HStack {
            Button(profile.ssid) { editor.draft = profile }
            Spacer()
            Button("Remove", role: .destructive) { monitor.remove(profile) }
          }
        }
        Button("New profile") {
          editor.draft = NetworkProfile(ssid: "", accessPoint: "", router: "")
        }
      }
      Section("Profile") {
        TextField("Exact Wi-Fi name (SSID)", text: $editor.draft.ssid)
        Button("Use current Wi-Fi") {
          if let network = monitor.network { editor.draft.ssid = network.ssid }
          if let router = monitor.discovery?.router { editor.draft.router = router }
          if case .found(let accessPoint) = monitor.discovery?.accessPoint {
            editor.draft.accessPoint = accessPoint
          }
        }
        .disabled(monitor.network == nil)
        TextField("Configured AP IPv4 address", text: $editor.draft.accessPoint)
        TextField("Router IPv4 address", text: $editor.draft.router)
        Text(
          "Use current Wi-Fi fills the router assigned to the Wi-Fi service, and the AP when the Mac's existing ARP cache identifies it. Find AP in the menu bar panel can search the subnet once on request."
        )
        .font(.caption)
      }
      Section("Between the access point and the router") {
        TextField(
          "Device name, e.g. TP-Link powerline adapters (optional)",
          text: Binding(
            get: { editor.draft.bridgeName ?? "" },
            set: { editor.draft.bridgeName = $0.isEmpty ? nil : $0 }))
        Text("Used in advice such as “Restart the TP-Link powerline adapters”.")
          .font(.caption).foregroundStyle(.secondary)
      }
      Section("Internet reference points") {
        Toggle(
          "Also ping Cloudflare (1.1.1.1) and Google (8.8.8.8)",
          isOn: $editor.draft.internetReferences)
        Text(
          "Separates home problems from internet provider ones. These pings leave your network and show your public address to Cloudflare and Google."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Section("Alert thresholds") {
        TextField("Difference (ms)", value: $editor.draft.thresholds.difference, format: .number)
        TextField(
          "Recovery difference (ms)", value: $editor.draft.thresholds.recoveryDifference,
          format: .number)
        TextField("Both slow (ms)", value: $editor.draft.thresholds.slow, format: .number)
        TextField(
          "Recovery latency (ms)", value: $editor.draft.thresholds.recoverySlow, format: .number)
        TextField(
          "Sustained delay (seconds)", value: $editor.draft.thresholds.sustainedSeconds,
          format: .number)
        TextField(
          "Recovery duration (seconds)", value: $editor.draft.thresholds.recoverySeconds,
          format: .number)
        Text(
          "Recovery thresholds must be lower than alert thresholds. All values must be positive."
        )
        .font(.caption)
      }
      Button("Save and allow monitoring on this network") {
        editor.message =
          monitor.save(editor.draft)
          ? "Profile saved locally."
          : "Check the Wi-Fi name, distinct IPv4 addresses and thresholds."
      }
      .disabled(!editor.draft.isValid)
      if !editor.message.isEmpty { Text(editor.message) }
      if let error = monitor.storageError { Text(error).foregroundStyle(.red) }
      Section("History") {
        Text(
          "\(monitor.week.minutes.count) minute summaries are stored on this Mac for up to 7 days."
        )
        if let error = monitor.historyError { Text(error).foregroundStyle(.red) }
        Button("Clear history…", role: .destructive) { editor.confirmingClear = true }
          .confirmationDialog(
            "Delete the stored week of history?", isPresented: $editor.confirmingClear
          ) {
            Button("Clear history", role: .destructive) { monitor.clearHistory() }
          }
      }
      Text(
        "No telemetry or desktop notifications. Settings stay on this Mac. ICMP differences do not identify a faulty component."
      )
      .font(.caption).foregroundStyle(.secondary)
    }
    .formStyle(.grouped)
    .frame(minWidth: 460, minHeight: 580)
  }
}
