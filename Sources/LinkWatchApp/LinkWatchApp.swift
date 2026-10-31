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
        Image(nsImage: controller.light.menuBarImage)
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

private struct DetailView: View {
  @Bindable var monitor: MonitorController
  @StateObject private var options = DetailOptions()
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Image(nsImage: monitor.light.menuBarImage)
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
      if let signal = monitor.signal {
        Text("Wi-Fi signal: \(signal.summary)").monospacedDigit().font(.caption)
      }
      if let usage = monitor.usage {
        Text(
          "Usage: ↓ \(StatusReport.rate(usage.downloadBitsPerSecond)) · ↑ \(StatusReport.rate(usage.uploadBitsPerSecond))"
        )
        .monospacedDigit().font(.caption)
      }
      if monitor.session.profile != nil {
        let totals = monitor.usageTotals
        Text("Today \(totals.today.summary)   ·   7 days \(totals.week.summary)")
          .monospacedDigit().font(.caption)
          .help("Data this Mac moved on monitored networks while LinkWatch was running.")
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
          let hourAgo = Date().addingTimeInterval(-3600)
          HistoryChart(
            history: monitor.session.window.history,
            stored: monitor.week.minutes.filter {
              $0.start >= hourAgo && $0.ssid == monitor.session.profile?.ssid
            })
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
      RecentProblems(monitor: monitor)
      HStack {
        TextField("What just happened? e.g. desk moved", text: $options.markText)
          .textFieldStyle(.roundedBorder).font(.caption)
          .onSubmit(markMoment)
        Button("Mark", action: markMoment).disabled(AppEvent.markLabel(options.markText) == nil)
      }
      .help("Notes what you are doing now, so problems can be matched with it later.")
      if let message = options.markMessage {
        Text(message).font(.caption2).foregroundStyle(.secondary)
      }
      DeviceTestView(monitor: monitor, device: $options.testDevice)
      Divider()
      Toggle("Pause monitoring", isOn: $monitor.paused)
      HStack {
        Button("Settings…") {
          openWindow(id: "settings")
          NSApp.activate(ignoringOtherApps: true)
        }
        Button("Export report…") {
          do {
            _ = try Reports.exportFromPanel(monitor)
            options.exportMessage =
              "Report saved and shown in Finder. Send the folder by AirDrop or Messages."
          } catch {
            options.exportMessage = "The report could not be saved: \(error.localizedDescription)"
          }
        }
        .help(
          "Saves the last week's diagnosis and measurements, including your network name and local addresses, and shows it in Finder."
        )
        Spacer()
        Button("Quit") { NSApp.terminate(nil) }
      }
      if let message = options.exportMessage {
        Text(message).font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(18)
    .frame(width: 360)
  }

  private func markMoment() {
    guard monitor.mark(options.markText) else { return }
    options.markMessage = "Marked “\(AppEvent.markLabel(options.markText) ?? "")”."
    options.markText = ""
  }

  private func metric(_ title: String, value: Double?) -> some View {
    VStack(alignment: .leading) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      Text("\(latencyText(value)) ms").font(.title2).monospacedDigit()
    }
  }
}

@MainActor
private final class ProfileEditor: ObservableObject {
  @Published var draft = NetworkProfile(ssid: "", accessPoint: "", router: "")
  @Published var message = ""
  @Published var confirmingClear = false
  @Published var opensAtLogin = LoginItem.isEnabled
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
      Section("Phone hotspot") {
        Toggle("This network is a phone's personal hotspot", isOn: $editor.draft.hotspot)
        Text(
          "Advice then names the phone, and internet pings run every 10 seconds instead of every 2 to save mobile data. The AP and router can be the same address."
        )
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
      Section("Start") {
        Toggle("Open LinkWatch at login", isOn: $editor.opensAtLogin)
          .onChange(of: editor.opensAtLogin) { _, enabled in
            try? LoginItem.set(enabled)
            editor.opensAtLogin = LoginItem.isEnabled
          }
        Text(
          "Keeps monitoring after a restart. Without it, nothing is recorded until LinkWatch is opened again."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
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
