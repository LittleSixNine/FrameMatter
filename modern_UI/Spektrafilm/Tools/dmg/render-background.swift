// Run: swift Tools/dmg/render-background.swift Tools/dmg
// Then: tiffutil -cathidpicheck Tools/dmg/background{,@2x}.png -out Tools/dmg/background.tiff
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let teal = NSColor(srgbRed: 0.035, green: 0.19, blue: 0.20, alpha: 1)
let copper = NSColor(srgbRed: 0.68, green: 0.34, blue: 0.16, alpha: 1)

for scale in [1, 2] {
    let width = 660 * scale, height = 440 * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width,
        pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: 660, height: 440)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    context.translateBy(x: 0, y: 440)
    context.scaleBy(x: 1, y: -1)
    NSColor(srgbRed: 0.92, green: 0.935, blue: 0.91, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 660, height: 440).fill()
    teal.setFill()
    NSRect(x: 0, y: 0, width: 660, height: 108).fill()
    copper.setFill()
    NSRect(x: 0, y: 108, width: 660, height: 2).fill()
    NSRect(x: 0, y: 432, width: 660, height: 8).fill()

    // Seeded, low-opacity grain keeps both generated sizes reproducible.
    var seed: UInt64 = 69
    for _ in 0..<100_000 {
        seed = seed &* 6364136223846793005 &+ 1
        let x = CGFloat((seed >> 32) % 1320) / 2
        seed = seed &* 6364136223846793005 &+ 1
        let y = CGFloat((seed >> 32) % 880) / 2
        NSColor(white: seed & 1 == 0 ? 0 : 1, alpha: y < 108 ? 0.045 : 0.022).setFill()
        NSRect(x: x, y: y, width: 0.5, height: 0.5).fill()
    }

    func text(_ string: String, y: CGFloat, size: CGFloat, color: NSColor, weight: NSFont.Weight) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
        let label = NSAttributedString(string: string, attributes: attributes)
        let bounds = label.size()
        context.saveGState()
        context.translateBy(x: (660 - bounds.width) / 2, y: y + bounds.height)
        context.scaleBy(x: 1, y: -1)
        label.draw(at: .zero)
        context.restoreGState()
    }
    text("FrameMatter", y: 37, size: 28, color: .init(white: 0.95, alpha: 1), weight: .medium)
    text("拖动到 Applications 安装", y: 345, size: 16, color: teal, weight: .regular)
    copper.setStroke()
    let arrow = NSBezierPath()
    arrow.lineWidth = 2
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 303, y: 218))
    arrow.line(to: NSPoint(x: 357, y: 218))
    arrow.move(to: NSPoint(x: 348, y: 210))
    arrow.line(to: NSPoint(x: 357, y: 218))
    arrow.line(to: NSPoint(x: 348, y: 226))
    arrow.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let name = scale == 1 ? "background.png" : "background@2x.png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
    assert(bitmap.pixelsWide == width && bitmap.pixelsHigh == height)
}
