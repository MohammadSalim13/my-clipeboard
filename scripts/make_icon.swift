// Draws the 1024×1024 app icon PNG. Usage: make_icon <output.png>
import AppKit

let outputPath = CommandLine.arguments[1]
let pixels = 1024
let size = CGFloat(pixels)

guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
bitmap.size = NSSize(width: size, height: size)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

// Standard macOS icon grid: 824pt rounded square centred on a 1024 canvas.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
NSColor.black.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.30, green: 0.52, blue: 1.00, alpha: 1),
    NSColor(srgbRed: 0.50, green: 0.32, blue: 0.96, alpha: 1),
])!
gradient.draw(in: shape, angle: -70)

let config = NSImage.SymbolConfiguration(pointSize: 400, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(srgbRed: 0.38, green: 0.42, blue: 0.97, alpha: 1), .white]))
if let symbol = NSImage(systemSymbolName: "list.clipboard.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    var s = symbol.size
    let maxSide: CGFloat = 520
    let scale = min(1, maxSide / max(s.width, s.height))
    s = NSSize(width: s.width * scale, height: s.height * scale)
    symbol.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2 - 4, width: s.width, height: s.height))
}

NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: outputPath))
