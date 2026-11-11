// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import XCTest

@MainActor
final class FactoryLetteringTests: XCTestCase {
    func testMissingAndNewDefaultsAreOffAndRoundTripIsExplicit() throws {
        XCTAssertFalse(try JSONDecoder().decode(FilmEdgeSettings.self, from: Data("{}".utf8)).independentLetteringHalation)
        XCTAssertFalse(Sidecar.newPhoto.params.filmEdge.independentLetteringHalation)
        var edge = FilmEdgeSettings()
        edge.independentLetteringHalation = true
        XCTAssertEqual(try JSONDecoder().decode(FilmEdgeSettings.self, from: JSONEncoder().encode(edge)), edge)
    }

    func testShootDeltaResetsAndOffKeepsLegacyStamp() {
        var p = FilmParams.default
        p.filmEdge.active = true
        let legacyWire = p.wire.filter { $0.name != "overscan_factory_separate_halation" && $0.name != "scene_curve" }
        let legacy = legacyWire.map { "\($0.name)=\($0.value)" }.joined(separator: ";") + ";overscan_framing="
        XCTAssertEqual(Session.printStamp(p), legacy)
        var on = p
        on.filmEdge.independentLetteringHalation = true
        XCTAssertNotEqual(Session.printStamp(on), legacy)
        XCTAssertEqual(on.delta(from: p).delta["overscan_factory_separate_halation"], .bool(true))
        XCTAssertEqual(p.delta(from: on).delta["overscan_factory_separate_halation"], .bool(false))
        XCTAssertEqual(on.delta(from: p).layers, [.shoot])
        p.filmEdge.active = false
        var dormant = p
        dormant.filmEdge.independentLetteringHalation = true
        XCTAssertEqual(Session.printStamp(p), Session.printStamp(dormant))
    }

    func testFilmEffectsCopiesOnlyTheNewLeafAndAgentAcceptsBoolean() throws {
        var source = Sidecar()
        source.params.filmEdge.independentLetteringHalation = true
        source.params.filmEdge.active = true
        source.params.filmEdge.cameraSeed = 42
        source.params.filmEdge.format = .f6x7
        let target = Sidecar()
        let out = SettingsClip(groups: [.filmEffects], settings: source, sourceName: "source").applied(to: target)
        var expected = target.params.filmEdge
        expected.independentLetteringHalation = true
        XCTAssertEqual(out.params.filmEdge, expected)
        XCTAssertEqual(SettingsClip(groups: [.exposure], settings: source, sourceName: "source").applied(to: target).params.filmEdge, target.params.filmEdge)
        let patch: JSONValue = ["params": ["filmEdge": ["independentLetteringHalation": true]]]
        XCTAssertEqual(try AgentDocument.validate(patch), ["params.filmEdge.independentLetteringHalation"])
        XCTAssertThrowsError(try AgentDocument.validate(["params": ["filmEdge": ["independentLetteringHalation": 1]]]))
    }

    func testSessionAgentUndoSaveReopenUsesTheSameSetting() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "factory-lettering-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "private-synthetic.png")
        let image = CIImage(color: CIColor(red: 0.22, green: 0.3, blue: 0.18)).cropped(to: CGRect(x: 0, y: 0, width: 360, height: 240))
        let cg = try XCTUnwrap(ImageDecoder.context.createCGImage(image, from: image.extent))
        let dst = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dst, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dst))
        var saved = Sidecar()
        saved.params.filmEdge.active = true
        saved.params.filmEdge.seeded = true
        saved.params.grainActive = false
        saved.params.glareActive = false
        try saved.save(for: url)
        let s = Session()
        s.open(urls: [url])
        try await wait("initial decode: \(s.status)") { s.decoded != nil }
        let initial = await s.ensureDeveloped()
        _ = try XCTUnwrap(initial, s.status)
        _ = try s.applyAgentEdit(["params": ["filmEdge": ["independentLetteringHalation": true]]])
        XCTAssertTrue(s.params.filmEdge.independentLetteringHalation)
        s.undo()
        XCTAssertFalse(s.params.filmEdge.independentLetteringHalation)
        s.redo()
        XCTAssertTrue(s.params.filmEdge.independentLetteringHalation)
        let edited = await s.ensureDeveloped()
        _ = try XCTUnwrap(edited, s.status)
        try await wait("edit: status=\(s.status), sent=\(s.scheduler.sent.filmEdge.independentLetteringHalation), wanted=\(s.params.filmEdge.independentLetteringHalation), busy=\(s.busy), pending=\(s.scheduler.pending)") { !s.busy && !s.scheduler.pending && s.scheduler.sent.filmEdge.independentLetteringHalation }
        XCTAssertNotNil(s.renderer.live)
        s.flushSave()
        XCTAssertTrue(try XCTUnwrap(Sidecar.load(for: url)).params.filmEdge.independentLetteringHalation)
        s.remove(url)
        await s.client.stop()
        let reopened = Session()
        reopened.open(urls: [url])
        XCTAssertTrue(reopened.params.filmEdge.independentLetteringHalation)
        let restored = await reopened.ensureDeveloped()
        _ = try XCTUnwrap(restored, reopened.status)
        await reopened.client.stop()
    }

    private func wait(_ reason: @autoclosure () -> String, _ condition: @MainActor () -> Bool) async throws {
        let end = Date().addingTimeInterval(45)
        while !condition() {
            if Date() > end { throw NSError(domain: "FactoryLetteringTests timeout: " + reason(), code: 1) }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
