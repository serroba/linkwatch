/// Where LinkWatch's desktop widget sits.
public enum WidgetPlacement: String, CaseIterable, Sendable {
  /// On the desktop, behind every window, like a desktop widget.
  case behindWindows
  /// Floating above other windows.
  case onTop
}
