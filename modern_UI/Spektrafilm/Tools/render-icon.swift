//  render-icon.swift — the app's icon as macOS draws it, to a PNG.
//
//      swiftc -O Tools/render-icon.swift -o /tmp/render-icon
//      /tmp/render-icon "$PWD/build/DerivedData/Build/Products/Debug/FrameMatter.app" \
//                       /tmp/app-icon.png 1024
//
//  Read the built bundle, rather than the source PNG, to prove that the
//  asset catalogue reached the app and that Finder resolves the new icon.
//  NSWorkspace uses the same icon lookup as Finder and the Dock.

import AppKit

let args = CommandLine.arguments
guard args.count == 4, let px = Int(args[3]), px > 0 else {
    FileHandle.standardError.write(Data("usage: render-icon <app> <out.png> <px>\n".utf8))
    exit(2)
}
// A path that does not exist is the failure this tool is most likely to have,
// and it fails *quietly*: `icon(forFile:)` answers a missing file with the
// generic blank-document icon, which is a 1024 px PNG of nothing that looks
// like a successful run. A relative path resolved against the wrong working
// directory is the way it happens. So: absolute, and it must be there.
let app = URL(fileURLWithPath: args[1]).standardizedFileURL
guard FileManager.default.fileExists(atPath: app.path) else {
    FileHandle.standardError.write(Data("no such bundle: \(app.path)\n".utf8))
    exit(1)
}
let icon = NSWorkspace.shared.icon(forFile: app.path)
let largest = icon.representations.map(\.pixelsWide).max() ?? 0
FileHandle.standardError.write(Data("largest rendition: \(largest) px\n".utf8))
if px > largest {
    FileHandle.standardError.write(Data("warning: \(px) px is an upscale of \(largest)\n".utf8))
}
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
rep.size = NSSize(width: px, height: px)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
icon.draw(in: NSRect(x: 0, y: 0, width: px, height: px),
          from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: args[2]))
