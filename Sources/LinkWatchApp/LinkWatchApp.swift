import Charts
import LinkWatchCore
import SwiftUI

@main
struct LinkWatchApp: App {
  @StateObject private var monitor = Monitor()

  var body: some Scene {
    MenuBarExtra {
      DetailView(monitor: monitor)
    } label: {
      HStack(spacing: 4) {
        Image(systemName: "circle.fill").foregroundStyle(monitor.color)
        Text("AP \(monitor.latencyText(monitor.accessPointLatency))")
          .monospacedDigit().frame(width: 52, alignment: .trailing)
        Text("·")
        Text("R \(monitor.latencyText(monitor.routerLatency)) ms")
          .monospacedDigit().frame(width: 70, alignment: .leading)
      }
      .accessibilityLabel("LinkWatch: \(monitor.reason)")
    }
    .menuBarExtraStyle(.window)
    Window("LinkWatch Settings", id: "settings") {
      ProfileSettings(monitor: monitor)
    }
    .defaultSize(width: 480, height: 620)
  }
}

private struct DetailView: View {
  @ObservedObject var monitor: Monitor
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Image(systemName: "circle.fill").foregroundStyle(monitor.color)
        Text("LinkWatch").font(.headline)
        Spacer()
        Text("Every 2 seconds").font(.caption).foregroundStyle(.secondary)
      }
      Text(monitor.reason).fixedSize(horizontal: false, vertical: true)
      HStack {
        metric("Configured AP", value: monitor.accessPointLatency)
        Spacer()
        metric("Router", value: monitor.routerLatency)
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
            format: "Packet loss — AP %.0f%% · Router %.0f%%",
            monitor.session.window.accessPointLoss * 100,
            monitor.session.window.routerLoss * 100))
        Chart {
          ForEach(Array(monitor.session.window.samples.enumerated()), id: \.offset) { _, pair in
            if let latency = pair.accessPoint.latency {
              LineMark(x: .value("Time", pair.elapsed), y: .value("ms", latency))
                .foregroundStyle(by: .value("Target", "AP"))
            }
            if let latency = pair.router.latency {
              LineMark(x: .value("Time", pair.elapsed), y: .value("ms", latency))
                .foregroundStyle(by: .value("Target", "Router"))
            }
          }
        }
        .chartXAxis(.hidden)
        .frame(height: 100)
        .accessibilityLabel("Recent latency history in milliseconds")
        if monitor.session.window.health != .healthy {
          Text(
            "Current alert for \(Int(ProcessInfo.processInfo.systemUptime - monitor.healthSince)) seconds"
          ).font(.caption)
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
      Text("\(monitor.latencyText(value)) ms").font(.title2).monospacedDigit()
    }
  }
}

@MainActor
private final class ProfileEditor: ObservableObject {
  @Published var draft = NetworkProfile(ssid: "", accessPoint: "", router: "")
  @Published var message = ""
}

private struct ProfileSettings: View {
  @ObservedObject var monitor: Monitor
  @StateObject private var editor = ProfileEditor()

  var body: some View {
    Form {
      Section("Wi-Fi identity") {
        Text(
          "macOS requires Location permission to reveal the Wi-Fi name. LinkWatch never requests location coordinates."
        )
        Button("Allow Wi-Fi identification") { monitor.requestPermission() }
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
          if let router = monitor.suggestedRouter() { editor.draft.router = router }
        }
        .disabled(monitor.network == nil)
        TextField("Configured AP IPv4 address", text: $editor.draft.accessPoint)
        TextField("Router IPv4 address", text: $editor.draft.router)
        Text("Use current Wi-Fi also fills the router when Wi-Fi owns the default route.")
          .font(.caption)
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
      Text(
        "No telemetry or desktop notifications. Settings stay on this Mac. ICMP differences do not identify a faulty component."
      )
      .font(.caption).foregroundStyle(.secondary)
    }
    .formStyle(.grouped)
    .frame(minWidth: 460, minHeight: 580)
  }
}
