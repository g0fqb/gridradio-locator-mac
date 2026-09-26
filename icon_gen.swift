import AppKit

func tinted(_ image: NSImage, color: NSColor) -> NSImage {
    let result = NSImage(size: image.size)
    result.lockFocus()
    color.set()
    NSBezierPath(rect: NSRect(origin: .zero, size: image.size)).fill()
    image.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1.0)
    result.unlockFocus()
    return result
}

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let rect = NSRect(x: 0, y: 0, width: size, height: size)
let cornerRadius: CGFloat = CGFloat(size) * 0.22
let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
path.addClip()

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.02, green: 0.30, blue: 0.52, alpha: 1.0),
    NSColor(calibratedRed: 0.0, green: 0.62, blue: 0.58, alpha: 1.0),
])
gradient?.draw(in: rect, angle: -90)

if let symbol = NSImage(systemSymbolName: "antenna.radiowaves.left.and.right", accessibilityDescription: nil) {
    let config = NSImage.SymbolConfiguration(pointSize: CGFloat(size) * 0.46, weight: .semibold)
    let configured = symbol.withSymbolConfiguration(config) ?? symbol
    let white = tinted(configured, color: .white)
    let symbolSize = white.size
    let symbolRect = NSRect(
        x: (CGFloat(size) - symbolSize.width) / 2,
        y: (CGFloat(size) - symbolSize.height) / 2 - CGFloat(size) * 0.02,
        width: symbolSize.width,
        height: symbolSize.height
    )
    white.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    exit(1)
}
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try? png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
