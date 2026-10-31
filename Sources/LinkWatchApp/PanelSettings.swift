import Combine
import LinkWatchCore
import SwiftUI

@MainActor
private final class NotificationChoice: ObservableObject {
  @Published var enabled = ProblemNotifier.isEnabled
  @Published var message: String?
}

/// Settings for a simpler panel and opt-in notifications, for people who only want to know
/// whether to do something.
struct PanelSettings: View {
  @AppStorage("simplePanel") private var simple = false
  @AppStorage("checkForUpdates") private var checkForUpdates = true
  @AppStorage(DesktopWidget.shownKey) private var widgetShown = false
  @AppStorage(DesktopWidget.placementKey) private var widgetPlacement = WidgetPlacement
    .behindWindows.rawValue
  @StateObject private var choice = NotificationChoice()

  var body: some View {
    Section("Panel, notifications and updates") {
      Toggle("Simple panel: only the advice, with details one click away", isOn: $simple)
      Toggle("Notify me when a problem lasts 3 minutes", isOn: $choice.enabled)
        .onChange(of: choice.enabled) { _, wanted in
          guard wanted != ProblemNotifier.isEnabled else { return }
          Task {
            let enabled = await ProblemNotifier.set(wanted)
            choice.enabled = enabled
            choice.message =
              wanted && !enabled
              ? "Notifications are not allowed. Allow LinkWatch in System Settings › Notifications."
              : nil
          }
        }
      Text(
        "One notification says what to do once a problem has lasted three minutes, and another when it is back to normal. Lag spikes, busy downloads and a router that only ignores pings do not notify."
      )
      .font(.caption).foregroundStyle(.secondary)
      Toggle("Show a desktop widget", isOn: $widgetShown)
      Picker("Widget placement", selection: $widgetPlacement) {
        Text("On the desktop, behind windows").tag(WidgetPlacement.behindWindows.rawValue)
        Text("Always on top").tag(WidgetPlacement.onTop.rawValue)
      }
      .disabled(!widgetShown)
      Text(
        "A small translucent panel with the colour, the advice and the latencies, updated every 2 seconds. Drag it anywhere; right-click it to hide it or change its placement."
      )
      .font(.caption).foregroundStyle(.secondary)
      Toggle("Check for updates once a day", isOn: $checkForUpdates)
      Text(
        "Asks GitHub for the latest LinkWatch release, which shows GitHub this Mac's IP address. Updates are only installed when you click Install update."
      )
      .font(.caption).foregroundStyle(.secondary)
      if let message = choice.message { Text(message).font(.caption).foregroundStyle(.red) }
    }
  }
}
