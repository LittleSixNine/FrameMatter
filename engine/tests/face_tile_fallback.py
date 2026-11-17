#!/usr/bin/env python3
"""Exercise the exact Swift helper injected by the isolated research builder."""
import ast, pathlib, subprocess, tempfile
repo=pathlib.Path(__file__).resolve().parents[2]
node=next(n for n in ast.parse((repo/'engine/tools/build_balanced_highlight_experiment.py').read_text()).body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='TILE_FALLBACK_SWIFT' for t in n.targets))
helper=ast.literal_eval(node.value)
harness=r'''
let context = CGContext(data: nil, width: 1600, height: 1067, bitsPerComponent: 8,
                        bytesPerRow: 1600, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
let image = context.makeImage()!
let box: [String: Any] = ["x": 0.1, "y": 0.2, "width": 0.3, "height": 0.4, "confidence": 0.6]
var calls = 0
func detect(_ image: CGImage) throws -> (Int, [[String: Any]]) {
    calls += 1
    assert(image.width == 960 && image.height == 641)
    return (3, [box,box])
}
let disabled = try researchFaceTileFallback(image, original: [], enabled: false, detect: detect)
assert(!disabled.triggered && calls == 0)
// Any nonempty original array, even ineligible boxes, suppresses fallback.
let original: [[String: Any]] = [["confidence": 0.1, "sentinel": 42]]
let retained = try researchFaceTileFallback(image, original: original, enabled: true, detect: detect)
assert(!retained.triggered && calls == 0 && retained.faces.count == 1)
assert(retained.faces[0]["sentinel"] as! Int == 42)
let result = try researchFaceTileFallback(image, original: [], enabled: true, detect: detect)
assert(result.triggered && calls == 4 && result.faces.count == 8 && result.tiles.count == 4)
for n in 0..<4 {
    let t = result.tiles[n], rect = (t["pixel_rect"] as! [CGFloat]).map(Double.init), roi = (t["bottom_left_roi"] as! [CGFloat]).map(Double.init)
    assert(t["grid_i"] as! Int == n % 2 && t["grid_j"] as! Int == n / 2)
    assert(rect[0] == Double(n % 2) * 640 && rect[1] == (n < 2 ? 426 : 0))
    assert(rect[2] == 960 && rect[3] == 641 && t["request_revision"] as! Int == 3)
    assert(roi == [rect[0]/1600, 1-(rect[1]+rect[3])/1067, rect[2]/1600, rect[3]/1067])
    let f = result.faces[2*n]
    for (key,expected) in [("x",roi[0]+0.1*roi[2]),("y",roi[1]+0.2*roi[3]),("width",0.3*roi[2]),("height",0.4*roi[3])] {
        assert(abs(((f[key] as! NSNumber).doubleValue)-expected) < 1e-12)
    }
}
let failure = NSError(domain: "sentinel", code: 99)
do {
    _ = try researchFaceTileFallback(image, original: [], enabled: true) { _ in throw failure }
    fatalError("detector failure swallowed")
} catch { assert((error as NSError).domain == "sentinel") }
do {
    _ = try researchFaceTileFallback(image, original: [], enabled: true) { _ in (3, [["x": 0.1]]) }
    fatalError("invalid local face accepted")
} catch { assert((error as NSError).code == 6) }
print("PASS exact injected Swift empty-only branch, crop rounding/ROI mapping/order, duplicates, and error propagation")
'''
with tempfile.TemporaryDirectory(prefix='face-tile-test-',dir='/private/tmp') as folder:
    p=pathlib.Path(folder);(p/'check.swift').write_text('import Foundation\nimport CoreGraphics\n'+helper+harness)
    subprocess.run(['swiftc',str(p/'check.swift'),'-o',str(p/'check'),'-module-cache-path',str(p/'modules')],check=True)
    subprocess.run([str(p/'check')],check=True)
