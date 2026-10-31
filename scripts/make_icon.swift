// Draws the LinkWatch app icon into an .iconset folder for `iconutil`.
//
// Usage: swift scripts/make_icon.swift OUTPUT.iconset
//
// The icon is drawn in code so the repository holds no binary artwork: a dark rounded
// square with a pulse line between two links, the Mac and the internet.
import AppKit

let palette = (
  top: NSColor(srgbRed: 0.09, green: 0.15, blue: 0.29, alpha: 1),
  bottom: NSColor(srgbRed: 0.04, green: 0.07, blue: 0.15, alpha: 1),
  pulse: NSColor(srgbRed: 0.20, green: 0.84, blue: 0.42, alpha: 1),
  node: NSColor.white
)

/// Draws on a 1024-point canvas scaled to `pixels`.
func render(pixels: Int) -> Data? {
  guard
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0),
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
  else { return nil }
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  let scale = CGFloat(pixels) / 1024
  context.cgContext.scaleBy(x: scale, y: scale)

  // The macOS icon grid: an 824-point rounded square centred on the canvas.
  let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
  let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
  NSGradient(starting: palette.top, ending: palette.bottom)?.draw(in: shape, angle: -90)

  // A pulse line: flat through the Mac, a spike between the access point and the router,
  // flat again to the internet.
  let pulse = NSBezierPath()
  pulse.move(to: NSPoint(x: 210, y: 500))
  for point in [(400, 500), (450, 640), (520, 330), (580, 560), (620, 500), (814, 500)] {
    pulse.line(to: NSPoint(x: point.0, y: point.1))
  }
  pulse.lineWidth = 46
  pulse.lineCapStyle = .round
  pulse.lineJoinStyle = .round
  palette.pulse.setStroke()
  pulse.stroke()

  palette.node.setFill()
  for centre in [NSPoint(x: 230, y: 500), NSPoint(x: 794, y: 500)] {
    NSBezierPath(ovalIn: NSRect(x: centre.x - 56, y: centre.y - 56, width: 112, height: 112))
      .fill()
  }
  NSGraphicsContext.restoreGraphicsState()
  return bitmap.representation(using: .png, properties: [:])
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
  FileHandle.standardError.write(Data("Usage: swift make_icon.swift OUTPUT.iconset\n".utf8))
  exit(64)
}
let folder = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
  for factor in [1, 2] {
    let name = "icon_\(points)x\(points)" + (factor == 2 ? "@2x" : "") + ".png"
    guard let png = render(pixels: points * factor) else { exit(1) }
    try png.write(to: folder.appendingPathComponent(name))
  }
}
