import AppKit
import LinkWatchCore
import SwiftUI

/// A small translucent panel showing the verdict and latencies.
///
/// It sits on the desktop behind windows or floats above them, and stays off until the
/// person turns it on.
@MainActor
final class DesktopWidget {
  static let shownKey = "widgetShown"
  static let placementKey = "widgetPlacement"
  /// Posted in this process when another process (the command line) changed the widget.
  static let changed = Notification.Name("io.github.serroba.LinkWatch.widgetChanged")
  private static let frameName = "LinkWatchWidget"

  /// Fixed, so showing the panel never has to measure SwiftUI layout.
  static let size = CGSize(width: 250, height: 150)

  private let controller: MonitorController
  private var panel: NSPanel?
  private var observers: [any NSObjectProtocol] = []
  /// The preference last applied; other defaults changes (such as the panel saving its own
  /// position) are ignored.
  private var applied: (shown: Bool, placement: WidgetPlacement)?

  static var isShown: Bool {
    get { UserDefaults.standard.bool(forKey: shownKey) }
    set { UserDefaults.standard.set(newValue, forKey: shownKey) }
  }

  static var placement: WidgetPlacement {
    get {
      UserDefaults.standard.string(forKey: placementKey).flatMap(WidgetPlacement.init)
        ?? .behindWindows
    }
    set { UserDefaults.standard.set(newValue.rawValue, forKey: placementKey) }
  }

  init(controller: MonitorController) {
    self.controller = controller
    for name in [UserDefaults.didChangeNotification, Self.changed] {
      observers.append(
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
          [weak self] _ in
          // Defaults change notifications can arrive in the middle of a window or SwiftUI
          // update, so apply on the next turn of the run loop rather than re-entering it.
          Task { @MainActor in self?.apply() }
        })
    }
    apply()
  }

  /// Shows, hides or moves the panel to match the saved preference.
  func apply() {
    let wanted = (shown: Self.isShown, placement: Self.placement)
    if let applied, applied == wanted { return }
    applied = wanted
    guard wanted.shown else {
      panel?.orderOut(nil)
      return
    }
    let panel = self.panel ?? makePanel()
    self.panel = panel
    panel.level =
      wanted.placement == .onTop
      ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    panel.orderFrontRegardless()
  }

  private func makePanel() -> NSPanel {
    let host = NSHostingView(rootView: WidgetView(monitor: controller))
    let panel = NSPanel(
      contentRect: NSRect(origin: .zero, size: Self.size),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.contentView = host
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.isMovableByWindowBackground = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    if !panel.setFrameUsingName(Self.frameName), let screen = NSScreen.main {
      let visible = screen.visibleFrame
      panel.setFrameTopLeftPoint(
        NSPoint(x: visible.maxX - panel.frame.width - 24, y: visible.maxY - 24))
    }
    panel.setFrameAutosaveName(Self.frameName)
    return panel
  }
}

/// The widget's content: colour and verdict, latency per link and the last few minutes.
struct WidgetView: View {
  let monitor: MonitorController

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 6) {
        Image(nsImage: monitor.light.menuBarImage)
        Text(headline).font(.callout.weight(.semibold)).lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      HStack(spacing: 14) {
        if monitor.session.profile?.isSingleDevice == false {
          reading("AP", monitor.accessPointLatency)
        }
        reading("Router", monitor.routerLatency)
        if monitor.session.profile?.internetReferences == true {
          reading("Internet", monitor.session.window.internetMedian)
        }
      }
      WidgetChart(history: Array(monitor.session.window.history.suffix(150)))
    }
    .padding(12)
    .frame(
      width: DesktopWidget.size.width, height: DesktopWidget.size.height, alignment: .topLeading
    )
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    .contextMenu {
      Button(
        DesktopWidget.placement == .onTop ? "Keep behind windows" : "Keep on top of windows"
      ) {
        DesktopWidget.placement = DesktopWidget.placement == .onTop ? .behindWindows : .onTop
      }
      Button("Hide widget") { DesktopWidget.isShown = false }
    }
  }

  private var headline: String {
    monitor.session.profile != nil && !monitor.session.window.samples.isEmpty
      ? monitor.advice.headline : monitor.reason
  }

  private func reading(_ title: String, _ value: Double?) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title).font(.caption2).foregroundStyle(.secondary)
      Text(value.map { String(format: "%.0f ms", $0) } ?? "—")
        .font(.callout).monospacedDigit()
    }
  }
}
