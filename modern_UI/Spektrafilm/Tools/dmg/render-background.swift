// Run: swift Tools/dmg/render-background.swift Tools/dmg
// Then: tiffutil -cathidpicheck Tools/dmg/background{,@2x}.png -out Tools/dmg/background.tiff
import AppKit
import CoreText

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
// A locally licensed font is used only while regenerating artwork.
guard let fontPath = ProcessInfo.processInfo.environment["DMG_TITLE_FONT_PATH"] else {
    fatalError("Set DMG_TITLE_FONT_PATH to your licensed Sigma Serif Headline font")
}
let fontURL = URL(fileURLWithPath: fontPath)
var fontError: Unmanaged<CFError>?
guard CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &fontError),
      let titleFont = NSFont(name: "SigmaSerif-Headline", size: 28) else {
    fatalError("Could not load Sigma Serif Headline: \(String(describing: fontError))")
}
assert(titleFont.fontName == "SigmaSerif-Headline")
print("Title font: \(titleFont.fontName)")
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
        if y >= 110 && y < 432 { continue }
        NSColor(white: seed & 1 == 0 ? 0 : 1, alpha: y < 108 ? 0.045 : 0.022).setFill()
        NSRect(x: x, y: y, width: 0.5, height: 0.5).fill()
    }

    func text(_ string: String, y: CGFloat, color: NSColor, font: NSFont, tracking: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color]
        let label = NSMutableAttributedString(string: string, attributes: attributes)
        if tracking != 0 {
            label.addAttribute(.kern, value: tracking, range: NSRange(location: 0, length: label.length - 1))
            assert(font.pointSize == 28 && tracking == 1.5)
            print("Title: 28 pt; added tracking: 1.5 pt; width: \(label.size().width) pt; center: 330 pt")
        }
        let bounds = label.size()
        context.saveGState()
        context.translateBy(x: (660 - bounds.width) / 2, y: y + bounds.height)
        context.scaleBy(x: 1, y: -1)
        label.draw(at: .zero)
        context.restoreGState()
    }
    text("FrameMatter", y: 37, color: .init(white: 0.95, alpha: 1), font: titleFont, tracking: 1.5)
    copper.setStroke()
    let arrow = NSBezierPath()
    arrow.lineWidth = 2
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 303, y: 271))
    arrow.line(to: NSPoint(x: 357, y: 271))
    arrow.move(to: NSPoint(x: 348, y: 263))
    arrow.line(to: NSPoint(x: 357, y: 271))
    arrow.line(to: NSPoint(x: 348, y: 279))
    arrow.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let name = scale == 1 ? "background.png" : "background@2x.png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
    assert(bitmap.pixelsWide == width && bitmap.pixelsHigh == height)
}
