import AppKit
import LinkWatchCore

extension StatusLight {
  private var color: NSColor {
    switch self {
    case .idle: .systemGray
    case .good: .systemGreen
    case .busy: .systemYellow
    case .internet: .systemOrange
    case .actionNeeded: .systemRed
    case .routerQuiet: .systemPurple
    }
  }

  /// Distinct shapes as well as colours, so the state never depends on colour alone.
  private var symbol: String {
    switch self {
    case .idle: "pause.circle.fill"
    case .good: "checkmark.circle.fill"
    case .busy: "arrow.up.arrow.down.circle.fill"
    case .internet: "globe"
    case .actionNeeded: "exclamationmark.triangle.fill"
    case .routerQuiet: "xmark.octagon.fill"
    }
  }

  /// Menu bar images are monochrome templates by default, which drops the colour; a
  /// palette-coloured non-template image keeps it visible without opening the panel.
  var menuBarImage: NSImage {
    let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
      .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    let image =
      NSImage(systemSymbolName: symbol, accessibilityDescription: rawValue)?
      .withSymbolConfiguration(configuration) ?? NSImage()
    image.isTemplate = false
    return image
  }
}
