// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Metal
import XCTest

@MainActor
final class HSLTests: XCTestCase {
    private func pixels(_ colors: [[Float]], _ adjustments: Adjustments, maskCount: Int = 0) throws -> [UInt16] {
        let gpu = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = try XCTUnwrap(Renderer(device: gpu))
        renderer.masks = Array(repeating: MaskUniform(), count: maskCount)
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float,
            width: colors.count, height: 1, mipmapped: false)
        d.storageMode = .shared; d.usage = [.shaderRead, .shaderWrite]
        let input = try XCTUnwrap(gpu.makeTexture(descriptor: d))
        let data: [Float] = colors.flatMap { $0 + [1] }
        data.withUnsafeBytes { input.replace(region: MTLRegionMake2D(0, 0, colors.count, 1), mipmapLevel: 0,
            withBytes: $0.baseAddress!, bytesPerRow: colors.count * 16) }
        let output = try XCTUnwrap(renderer.applyAdjustments(adjustments, to: input))
        var result = [UInt16](repeating: 0, count: colors.count * 4)
        output.getBytes(&result, bytesPerRow: colors.count * 8,
            from: MTLRegionMake2D(0, 0, colors.count, 1), mipmapLevel: 0)
        return result
    }

    func testOldSidecarAndNewRoundtrip() throws {
        var a = Adjustments(); a.exposure = 0.7
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(a)) as? [String: Any])
        json.removeValue(forKey: "hsl")
        let old = try JSONDecoder().decode(Adjustments.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old, a)
        a.hsl.orange.hue = 15; a.hsl.blue.saturation = -40; a.hsl.red.lightness = 12
        XCTAssertEqual(try JSONDecoder().decode(Adjustments.self, from: JSONEncoder().encode(a)), a)
        var sidecar = Sidecar(); sidecar.adjustments = a
        XCTAssertEqual(try JSONDecoder().decode(Sidecar.self, from: JSONEncoder().encode(sidecar)).adjustments, a)
    }

    func testSchemaReadbackAndWholePatchRefusal() throws {
        let before = AgentDocument(Sidecar())
        let after = try before.merged(with: ["adjustments": ["hsl": ["orange": ["hue": 15, "lightness": -20]]]])
        XCTAssertEqual(after.adjustments.hsl.orange.hue, 15)
        XCTAssertEqual(try after.json["adjustments"]?["hsl"]?["orange"]?["hue"], .number(15))
        XCTAssertThrowsError(try AgentDocument.validate( ["adjustments": ["exposure": 1, "hsl": ["red": ["hue": 31]]]]))
        XCTAssertThrowsError(try AgentDocument.validate( ["adjustments": ["hsl": ["red": ["lightness": .null]]]]))
        XCTAssertEqual(before.adjustments, Adjustments())
    }

    func testPostDevCopyIsExplicitAndDoesNotCopyGeometry() {
        var source = Sidecar(); source.adjustments.hsl.green.saturation = -70
        source.adjustments.exposure = 1; source.geometry.angle = 5
        let target = Sidecar()
        XCTAssertEqual(SettingsClip(groups: [.filmAndPaper], settings: source, sourceName: "source").applied(to: target).adjustments, target.adjustments)
        let pasted = SettingsClip(groups: [.postDev], settings: source, sourceName: "source").applied(to: target)
        XCTAssertEqual(pasted.adjustments, source.adjustments)
        XCTAssertEqual(pasted.geometry, target.geometry)
    }

    func testNeutralAndDisabledAreExactAndGreyIsUntouched() throws {
        let colors: [[Float]] = [[0,0,0],[0.18,0.18,0.18],[0.7,0.7,0.7],[1,1,1],[0.7,0.45,0.3],[1,0,0],[0,0,1]]
        let baseline = try pixels(colors, Adjustments())
        var a = Adjustments(); XCTAssertEqual(a.hsl.uniforms.active, 0)
        XCTAssertEqual(try pixels(colors, a), baseline)
        a.hsl.red.hue = 30; a.hsl.red.lightness = 30
        let changed = try pixels(colors, a)
        XCTAssertEqual(Array(changed.prefix(16)), Array(baseline.prefix(16)))
        a.enabled = false
        XCTAssertEqual(try pixels(colors, a), baseline)
    }

    func testTargetSkinSaturatedColorsAndCircularSeam() throws {
        let colors: [[Float]] = [[0.7,0.45,0.3],[0,0,1],[1,0.001,0],[1,0,0.001]]
        let baseline = try pixels(colors, Adjustments())
        var a = Adjustments(); a.hsl.orange.saturation = 50; a.hsl.red.hue = 20
        let result = try pixels(colors, a)
        XCTAssertNotEqual(Array(result.prefix(3)), Array(baseline.prefix(3)))
        XCTAssertEqual(Array(result[4..<7]), Array(baseline[4..<7]), "non-target blue moved")
        for channel in 0..<3 { XCTAssertLessThan(abs(Int(result[8+channel])-Int(result[12+channel])), 250) }
        XCTAssertGreaterThan(result[8], 65000); XCTAssertGreaterThan(result[9], 18000)
    }
    func testFourAndEightMasksKeepTheirGPUBufferValid() throws {
        let colors: [[Float]] = [[0.8,0.2,0.1],[0.2,0.4,0.9]]
        var a = Adjustments(); a.hsl.red.hue = 10
        let baseline = try pixels(colors, a)
        XCTAssertEqual(baseline[3], 65535)
        for count in [4,8] { XCTAssertEqual(try pixels(colors, a, maskCount: count), baseline) }
        XCTAssertEqual(MemoryLayout<Layer2Uniforms>.stride, 224)
        XCTAssertEqual(MemoryLayout<HSLUniforms>.stride, 144)
    }

    func testTinyHSLDoesNotClipExposureBeforeTheVignette() throws {
        let colors = Array(repeating: [Float(0.7),0.3,0.1], count:64)
        var a = Adjustments(); a.exposure = 1; a.vignette.amount = -100; a.vignette.midpoint = 0
        let before = try pixels(colors, a)
        a.hsl.red.hue = 0.0001
        let after = try pixels(colors, a)
        for (x,y) in zip(before, after) { XCTAssertLessThan(abs(Int(x)-Int(y)), 5) }
    }

}
