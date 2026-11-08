// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later

// swift Tools/render-boot-title.swift /path/to/licensed/SigmaSerif-Headline.woff
// Only the generated artwork is bundled; the font stays local.
import AppKit
import CoreText

guard CommandLine.arguments.count == 2 else {
    fatalError("Pass the path to your licensed Sigma Serif Headline font")
}
let fontURL = URL(fileURLWithPath: CommandLine.arguments[1])
var fontError: Unmanaged<CFError>?
guard CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &fontError),
      let font = NSFont(name: "SigmaSerif-Headline", size: 26) else {
    fatalError("Could not load Sigma Serif Headline: \(String(describing: fontError))")
}
let label = NSMutableAttributedString(string: "FrameMatter", attributes: [
    .font: font,
    .foregroundColor: NSColor(srgbRed: 249/255, green: 247/255, blue: 243/255, alpha: 1),
])
label.addAttribute(.kern, value: 1.5, range: NSRange(location: 0, length: label.length - 1))
let line = CTLineCreateWithAttributedString(label)
let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
assert(font.fontName == "SigmaSerif-Headline" && bounds.width < 180 && bounds.height < 32)
let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("../Spektrafilm/Assets.xcassets/BootTitle.imageset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 180 * scale,
        pixelsHigh: 32 * scale, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: 180, height: 32)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    context.clear(CGRect(x: 0, y: 0, width: 180, height: 32))
    context.textPosition = CGPoint(x: (180 - bounds.width) / 2 - bounds.minX,
                                   y: (32 - bounds.height) / 2 - bounds.minY)
    CTLineDraw(line, context)
    NSGraphicsContext.restoreGraphicsState()
    assert(bitmap.colorAt(x: 0, y: 0)!.alphaComponent == 0)
    let name = scale == 1 ? "BootTitle.png" : "BootTitle@2x.png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
    print("\(font.fontName): \(name), \(bitmap.pixelsWide)×\(bitmap.pixelsHigh)")
}
