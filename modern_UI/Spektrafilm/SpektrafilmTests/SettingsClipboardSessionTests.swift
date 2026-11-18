//  SettingsClipboardSessionTests.swift — RFC-027 through a real `Session` and
//  the engine: what a paste does to the *print*, not to the interface.
//
//  The user's report was "the exposure and the display copied, but choosing
//  the film again shows it did not". The interface was right and the print was
//  wrong, so every check here that matters reads pixels or the sidecar on disk,
//  never a label.
//
//  Every frame is a copy in a fresh temporary directory: a develop writes a
//  sidecar, and the checkout's fixtures are shared with every other suite.

import Metal
import XCTest
import CoreImage
import SwiftUI

@MainActor
final class SettingsClipboardSessionTests: XCTestCase {

    private static func fixture(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "tests/Test_image/\(relativePath)")
    }

    /// Copies of one fixture, each in a directory of its own so each has its
    /// own sidecar.
    private func copies(of relativePath: String, count: Int = 1) throws -> [URL] {
        let source = Self.fixture(relativePath)
        try XCTSkipUnless(FileManager.default.fileExists(atPath: source.path),
                          "\(relativePath) is not in this checkout")
        return try (0..<count).map { i in
            let dir = FileManager.default.temporaryDirectory
                .appending(path: "spk-clipboard-\(i)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appending(path: source.lastPathComponent)
            try FileManager.default.copyItem(at: source, to: url)
            addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
            return url
        }
    }

    func testNamedPresetSurvivesANewSessionAndAppliesOnlyToCurrentPhoto() throws {
        let suite = "FrameMatter.preset-test." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = Session(clipboardDefaults: defaults)
        let urls = try copies(of: "_smoke_1mp.tif", count: 2)
        source.selection = urls[0]
        source.sidecar.adjustments.exposure = 1.25
        source.sidecar.geometry.quarterTurns = 1
        try source.saveDevelopPreset(named: "  Warm  ")
        XCTAssertThrowsError(try source.saveDevelopPreset(named: "warm"))
        XCTAssertNil(source.clipboard)

        let target = Session(clipboardDefaults: defaults)
        target.selection = urls[1]
        target.reloadDevelopPresets()
        let preset = try XCTUnwrap(target.developPresets.first)
        XCTAssertEqual(preset.name, "Warm")
        target.applyDevelopPreset(preset)
        XCTAssertEqual(target.sidecar.adjustments.exposure, 1.25)
        XCTAssertEqual(target.sidecar.geometry, .default)
        XCTAssertNil(target.clipboard)
        target.undo()
        XCTAssertEqual(target.sidecar.adjustments.exposure, 0)
        target.removeDevelopPreset(preset)
        source.reloadDevelopPresets()
        XCTAssertTrue(source.developPresets.isEmpty)
    }

    // MARK: - §5.1 the develop race

    /// An edit made while the engine is being handed the frame reaches the
    /// print.
    ///
    /// The hook runs between building the `open` delta and sending it, which is
    /// the window a paste lands in when it follows a frame switch. The control
    /// is the same frame developed with the edit from the start. The edit is
    /// +2 stops of enlarger brightness: large and global, so a whole-frame
    /// mean sees it far above grain's noise.
    func testAnEditDuringTheOpenReachesThePrint() async throws {
        let urls = try copies(of: "_smoke_1mp.tif", count: 2)

        let racing = Session()
        racing.open(urls: [urls[0]])
        try await waitUntil("the frame to decode") { racing.decoded != nil }
        try await waitUntil("the engine to warm up") { racing.serviceReady }
        racing.afterOpenDeltaForTesting = { [unowned racing] in
            racing.afterOpenDeltaForTesting = nil
            var p = racing.params
            p.printBrightnessStops = 2
            racing.params = p
        }
        racing.requestPrint()
        try await settle(racing)
        XCTAssertEqual(racing.params.printBrightnessStops, 2)

        let control = Session()
        control.open(urls: [urls[1]])
        try await waitUntil("the control to decode") { control.decoded != nil }
        try await waitUntil("the control engine to warm up") { control.serviceReady }
        var p = control.params
        p.printBrightnessStops = 2
        control.params = p
        try await settle(control)

        let got = try meanLuma(racing, urls[0])
        let want = try meanLuma(control, urls[1])
        XCTAssertEqual(got / want, 1, accuracy: 0.03,
                       "the print does not carry the edit made during the open (mean \(got) against \(want))")
    }

    // MARK: - pasting onto frames that are not on the canvas

    /// PRD R2: a pasted frame never shows its old look. Its sidecar is written
    /// at once, its resident print is dropped (`select` would show it first),
    /// and opening it develops it with the pasted film rather than stopping at
    /// the decode.
    func testAPasteOntoPickedFramesWritesThemAndOpeningOneDevelopsIt() async throws {
        let urls = try copies(of: "_smoke_1mp.tif", count: 3)
        let (a, b, c) = (urls[0], urls[1], urls[2])
        let s = Session()
        s.open(urls: urls)
        try await waitUntil("the engine to warm up") { s.serviceReady }

        // b has been printed, so it has a resident print to lose.
        s.click(b)
        try await waitUntil("b to decode") { s.decoded != nil }
        s.requestPrint()
        try await settle(s)
        XCTAssertNotNil(s.renderer.store.print(for: b))

        s.click(a)
        try await waitUntil("a to decode") { s.selection == a && s.decoded != nil }
        s.selectFilmStock("kodak_gold_200")
        // Let a's own develop finish first. A develop still in flight when the
        // canvas moves follows the newest load (`ensureDeveloped`) and would
        // develop b by itself, which is not what this test is about.
        try await settle(s)
        s.clipboardGroups = [.filmAndPaper]
        s.copySettings()
        XCTAssertEqual(s.clipboard?.groups, [.filmAndPaper])
        s.click(b, command: true)
        s.click(c, command: true)
        XCTAssertEqual(Set(s.pasteTargets), Set(urls))
        s.pasteSettings()

        for url in [b, c] {
            let saved = try XCTUnwrap(Sidecar.load(for: url), "\(url.lastPathComponent) has no sidecar")
            XCTAssertEqual(saved.params.filmStock, "kodak_gold_200")
            XCTAssertEqual(saved.state, .stale)
            XCTAssertEqual(s.frameStates[url], .stale)
        }
        XCTAssertNil(s.renderer.store.print(for: b), "b's old print would be shown when it is opened")

        s.click(b)
        try await waitUntil("b to develop on open", timeout: 90) {
            s.selection == b && s.serviceSessionIDForExport != nil && s.frameStates[b] == .processed
        }
        XCTAssertEqual(s.params.filmStock, "kodak_gold_200")
        XCTAssertEqual(s.scheduler.sent.filmStock, "kodak_gold_200")
        s.flushSave()
        XCTAssertEqual(Sidecar.load(for: b)?.state, .processed, "the develop did not clear the stale mark on disk")
    }

    /// PRD R4: one ⌘Z undoes the whole paste on the frame on the canvas.
    func testOneUndoRestoresTheWholePaste() async throws {
        let url = try copies(of: "_smoke_1mp.tif")[0]
        let s = Session()
        s.open(urls: [url])
        try await waitUntil("the frame to decode") { s.decoded != nil }
        let before = s.sidecar

        var p = s.params
        p.filmStock = "kodak_gold_200"
        p.printBrightnessStops = 1
        p.effects.grain = 1.5
        s.clipboardGroups = Set(ClipboardGroup.allCases)
        s.sidecar.params = p        // the source state, without an undo step of its own
        s.copySettings()
        s.sidecar = before

        // Edits within half a second share an undo step; the paste is its own.
        try await Task.sleep(for: .milliseconds(600))
        s.pasteSettings()
        XCTAssertEqual(s.params.filmStock, "kodak_gold_200")
        XCTAssertEqual(s.params.effects.grain, 1.5)
        s.undo()
        XCTAssertEqual(s.sidecar.params, before.params)
        XCTAssertEqual(s.sidecar.decode, before.decode)
    }

    /// PRD R6.
    func testPasteIsRefusedDuringABatchExport() async throws {
        let url = try copies(of: "_smoke_1mp.tif")[0]
        let s = Session()
        s.open(urls: [url])
        try await waitUntil("the frame to decode") { s.decoded != nil }
        s.copySettings()
        var p = s.params
        p.printBrightnessStops = 1
        s.params = p
        s.batchExporting = true
        XCTAssertFalse(s.canPasteSettings)
        s.pasteSettings()
        XCTAssertEqual(s.params.printBrightnessStops, 1, "a paste landed during a batch export")
        s.batchExporting = false
    }

    // MARK: - §5.2 the placement is fitted on the target

    /// A pasted Scene Placement is the target's own Fit at the pasted
    /// pull-back — the same curve a person placing it by hand gets — and not
    /// the source's.
    func testAPastedPlacementIsFittedOnTheTarget() async throws {
        let smoke = try copies(of: "_smoke_1mp.tif")[0]
        let raw = try copies(of: "A7m3/DSC03710.ARW")[0]
        let s = Session()
        s.open(urls: [smoke, raw])
        try await waitUntil("the engine to warm up") { s.serviceReady }

        // A pull-back both frames can take: a stop past the larger of the two
        // minimums the Fit reports.
        func developAndMeasure(_ url: URL) async throws -> Double {
            s.click(url)
            try await waitUntil("\(url.lastPathComponent) to decode", timeout: 60) {
                s.selection == url && s.decoded != nil
            }
            s.requestPrint()
            try await settle(s)
            let m = await s.measureLatitude()
            let reply = try XCTUnwrap(m, "\(url.lastPathComponent) cannot be measured: \(s.latitude.failure ?? "no reason")")
            return reply.fit.highlight.minimumPullBack
        }
        let pullBack = max(try await developAndMeasure(smoke), try await developAndMeasure(raw), 0) + 1

        // The target's own fit, by hand: the control.
        let direct = await s.placeSceneNow(highlight: pullBack, shadow: 0)
        XCTAssertEqual(direct?.fit.valid, true, "the RAW refused \(pullBack) stops: \(String(describing: direct?.fit.issues))")
        let byHand = s.params.sceneLatitude
        XCTAssertTrue(byHand.active)
        s.resetScenePlacement()
        try await settle(s)

        // The source: the smoke frame, placed at the same pull-back.
        s.click(smoke)
        // A frame reopened from the display cache has no `decoded`; the
        // develop decodes it itself (`ensureDeveloped`).
        XCTAssertEqual(s.selection, smoke)
        s.requestPrint()
        try await settle(s)
        let placed = await s.placeSceneNow(highlight: pullBack, shadow: 0)
        XCTAssertEqual(placed?.fit.valid, true, "the smoke frame refused \(pullBack) stops")
        try await settle(s)
        let sourceCurve = s.params.sceneLatitude
        XCTAssertNotEqual(sourceCurve.highlightKnee, byHand.highlightKnee,
                          "the two frames fit the same curve, so this test cannot tell a paste from a fit")
        s.clipboardGroups = [.scenePlacement]
        s.copySettings()

        s.click(raw)
        XCTAssertEqual(s.selection, raw)
        s.pasteSettings()
        XCTAssertTrue(s.sidecar.placementNeedsFit)
        try await waitUntil("the pasted placement to be fitted", timeout: 90) {
            s.serviceSessionIDForExport != nil && !s.sidecar.placementNeedsFit
        }
        let pasted = s.params.sceneLatitude
        XCTAssertTrue(pasted.active)
        XCTAssertEqual(pasted.highlightPullBack, pullBack)
        XCTAssertEqual(pasted.highlightKnee, byHand.highlightKnee, accuracy: 1e-6)
        XCTAssertEqual(pasted.highlightRoom, byHand.highlightRoom, accuracy: 1e-6)
        XCTAssertEqual(pasted.shadowKnee, byHand.shadowKnee, accuracy: 1e-6)
        XCTAssertEqual(pasted.shadowRoom, byHand.shadowRoom, accuracy: 1e-6)
    }

    // MARK: - helpers

    /// Developed, nothing queued, and the last render landed.
    private func settle(_ s: Session) async throws {
        try await waitUntil("the develop", timeout: 90) {
            s.serviceSessionIDForExport != nil && !s.busy && !s.scheduler.pending
        }
        // A render requested by the trailing `request` is still in flight for a
        // moment after `pending` clears; the print lands with it.
        try await Task.sleep(for: .milliseconds(800))
        try await waitUntil("the queue to drain", timeout: 30) { !s.busy && !s.scheduler.pending }
    }

    private func meanLuma(_ s: Session, _ url: URL) throws -> Double {
        let tex = try XCTUnwrap(s.renderer.store.print(for: url), "no print is resident")
        let px = try samples(tex, s.renderer.device)
        var sum = 0.0, n = 0.0
        for i in stride(from: 0, to: px.count - 3, by: 4) {
            sum += 0.2126 * Double(px[i]) + 0.7152 * Double(px[i + 1]) + 0.0722 * Double(px[i + 2])
            n += 1
        }
        return sum / max(n, 1)
    }

    private func samples(_ texture: MTLTexture, _ device: MTLDevice) throws -> [UInt16] {
        XCTAssertEqual(texture.pixelFormat, .rgba16Unorm)
        guard texture.pixelFormat == .rgba16Unorm else { return [] }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: texture.pixelFormat, width: texture.width,
                                                         height: texture.height, mipmapped: false)
        d.storageMode = .shared
        let copy = try XCTUnwrap(device.makeTexture(descriptor: d))
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        let blit = try XCTUnwrap(cb.makeBlitCommandEncoder())
        blit.copy(from: texture, to: copy)
        blit.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        var out = [UInt16](repeating: 0, count: texture.width * texture.height * 4)
        out.withUnsafeMutableBytes {
            copy.getBytes($0.baseAddress!, bytesPerRow: texture.width * 8,
                          from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        }
        return out
    }

    private func waitUntil(_ what: String, timeout: Double = 30,
                           _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("timed out waiting for \(what)")
    }
    func testPresetScopesAndLegacyMigration() throws {
        var target = Sidecar()
        target.params.exposureCompensationEV = 2
        target.params.doubleExposure.path = "/target/photo.tif"
        target.geometry.quarterTurns = 1
        var source = Sidecar()
        source.adjustments.exposure = 0.75
        source.params.exposureCompensationEV = -3
        source.params.doubleExposure.path = "/source/private.tif"
        var preset = DevelopPreset(name: "Grade", source: source)
        preset.includedGroups = [.postDev]
        preset.includesEffects = false
        preset.includesSecondPhoto = false
        let result = preset.applied(to: target)
        XCTAssertEqual(result.adjustments.exposure, 0.75)
        XCTAssertEqual(result.params.exposureCompensationEV, 2)
        XCTAssertEqual(result.params.doubleExposure.path, "/target/photo.tif")
        XCTAssertEqual(result.geometry, target.geometry)
        let old = DevelopPreset(name: "Old", source: source)
        let decoded = try JSONDecoder().decode(DevelopPreset.self, from: JSONEncoder().encode(old))
        XCTAssertEqual(decoded.clip.groups, DevelopPreset.groups)
        XCTAssertEqual(decoded.applied(to: target).adjustments.exposure, 0.75)
    }

    func testPresetUpdateFavoritesAndCategoriesPersist() throws {
        let name = "preset-store-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let session = Session(clipboardDefaults: defaults)
        var preset = DevelopPreset(name: "Warm", source: Sidecar())
        preset.category = "Portrait"
        preset.favorite = true
        try session.storeDevelopPreset(preset)
        preset.settings.adjustments.exposure = 0.5
        try session.storeDevelopPreset(preset)
        XCTAssertEqual(session.developPresets.count, 1)
        XCTAssertEqual(session.developPresets.first?.settings.adjustments.exposure, 0.5)
        let reloaded = Session(clipboardDefaults: defaults)
        reloaded.reloadDevelopPresets()
        XCTAssertEqual(reloaded.developPresets.first?.favorite, true)
        XCTAssertEqual(reloaded.developPresets.first?.category, "Portrait")
        var duplicate = preset
        duplicate.id = UUID()
        XCTAssertThrowsError(try session.storeDevelopPreset(duplicate))
        duplicate.category = "Travel"
        try session.storeDevelopPreset(duplicate)
        XCTAssertEqual(session.developPresets.count, 2)
    }

    func testPresetBatchWritesTheSelectedPhotosOnly() throws {
        let urls = try copies(of: "_smoke_1mp.tif", count: 3)
        let session = Session()
        session.open(urls: urls)
        session.click(urls[0])
        session.togglePick(urls[1])
        var source = Sidecar()
        source.adjustments.exposure = 0.8
        var preset = DevelopPreset(name: "Batch", source: source)
        preset.includedGroups = [.postDev]
        preset.includesSecondPhoto = false
        session.applyDevelopPreset(preset, toSelected: true)
        XCTAssertEqual(session.sidecar.adjustments.exposure, 0.8)
        XCTAssertEqual(Sidecar.load(for: urls[1])?.adjustments.exposure, 0.8)
        XCTAssertNil(Sidecar.load(for: urls[2]))
        session.undo()
        XCTAssertNotEqual(session.sidecar.adjustments.exposure, 0.8)
    }

    func testPresetPreviewUsesAnAcceptedEngineTier() async throws {
        let gpu = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let image = CIImage(color: CIColor(red: 0.2, green: 0.3, blue: 0.4))
            .cropped(to: CGRect(x: 0, y: 0, width: 96, height: 64))
        let frame = try ImageDecoder.engineFrame(from: image, device: gpu)
        let client = EngineClient(device: gpu)
        var delta = FilmParams.default.fullDelta
        delta["preview_long_edge"] = .double(Double(DevelopPreset.previewLongEdge))
        let open = try await client.open(frame, paramsDelta: delta)
        let render = try await client.render(.reprint, RenderRequest(sessionID: open.sessionID))
        let texture = try XCTUnwrap(render.texture)
        let thumbnail = try XCTUnwrap(DevelopPreset.previewImage(texture: texture, adjustments: Adjustments(), device: gpu))
        let bytes = Array(try XCTUnwrap(thumbnail.dataProvider?.data) as Data)
        let center = 90 * thumbnail.bytesPerRow + 120 * 8
        XCTAssertNotEqual(Array(bytes.prefix(8)), Array(bytes[center..<(center + 8)]), "the preview must contain a photograph, not just the canvas surround")
        await client.stop()
    }

    func testAdaptivePresetCardsRenderARealRAWWithAndWithoutAFrameCut() async throws {
        let url = try XCTUnwrap(copies(of: "A7m3/DSC03710.ARW").first)
        let suite = "adaptive-preset-preview-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = Session(clipboardDefaults: defaults)
        session.open(urls: [url])
        try await waitUntil("the RAW to decode") { session.decoded != nil }
        XCTAssertTrue(session.params.needsFaceEvidence)

        let plain = DevelopPreset(name: "Plain", source: session.sidecar)
        var bordered = DevelopPreset(name: "Square film", source: session.sidecar)
        bordered.settings.params.filmEdge.active = true
        bordered.settings.params.filmEdge.format = .f6x6
        bordered.includedGroups = [.filmAndPaper, .filmEffects]
        bordered.includesEffects = true
        try session.storeDevelopPreset(plain)
        try session.storeDevelopPreset(bordered)

        let keys = [plain, bordered].map { preset in
            PresetPreviewCache.key(for: preset, target: session.sidecar, url: url)
        }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 640),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: DevelopPresetsSection(session: session))
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await waitUntil("both adaptive preset card images", timeout: 15) {
            keys.allSatisfy { PresetPreviewCache.shared.image(for: $0) != nil }
        }
        XCTAssertTrue(session.params.needsFaceEvidence)
    }

    func testPresetPreviewResolvesBorderCropAndDateFromTargetPhoto() throws {
        var target = Sidecar()
        target.params.dateBack.active = true
        var source = target
        source.params.filmEdge.active = true
        source.params.filmEdge.format = .f6x6
        var preset = DevelopPreset(name: "Square", source: source)
        preset.settings = source
        preset.includesEffects = true
        var shooting = ShootingData()
        shooting.captureDay = .init(year: 2024, month: 6, day: 9)
        let size = CGSize(width: 1200, height: 800)
        let preview = DevelopPreset.previewSettings(preset.applied(to: target), target: target,
            size: size, shooting: shooting, stock: nil)
        let cut = preview.geometry.outputSize(for: size)
        XCTAssertEqual(cut.width, cut.height, accuracy: 1)
        XCTAssertTrue(preview.params.filmEdge.active)
        XCTAssertTrue(preview.params.dateBack.active)
        XCTAssertEqual(preview.params.dateBack.text, target.params.dateBack.resolvedDateText(shooting: shooting))
        XCTAssertFalse(preview.params.dateBack.text.isEmpty)
        XCTAssertEqual(preview.params.dateBack.camera, .f6x6)
        XCTAssertEqual(preview.params.dateBack.frameScale, 2.0 / 3, accuracy: 0.001)
        var bordered = preview
        bordered.heldCrop = target.geometry
        var withoutBorder = bordered
        withoutBorder.params.filmEdge.active = false
        let restored = DevelopPreset.previewSettings(withoutBorder, target: bordered,
            size: size, shooting: shooting, stock: nil)
        XCTAssertEqual(restored.geometry, target.geometry)
    }

    func testPresetPreviewRendersFilmBorderAndDatePixels() async throws {
        let gpu = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let image = CIImage(color: CIColor(red: 0.2, green: 0.3, blue: 0.4))
            .cropped(to: CGRect(x: 0, y: 0, width: 800, height: 533))
        let frame = try ImageDecoder.engineFrame(from: image, device: gpu)
        let client = EngineClient(device: gpu)
        var source = Sidecar()
        source.params.filmEdge.active = true
        source.params.dateBack.active = true
        source.params.dateBack.customText = "24 06 09"
        let prepared = DevelopPreset.previewSettings(source, target: source,
            size: CGSize(width: 800, height: 533), shooting: ShootingData(), stock: nil)
        var delta = prepared.params.fullDelta
        delta["preview_long_edge"] = .double(Double(DevelopPreset.previewLongEdge))
        delta["grain_active"] = .bool(false)
        delta["glare_active"] = .bool(false)
        let opened = try await client.open(frame, paramsDelta: delta)
        let withDate = try await client.render(.reprint, RenderRequest(sessionID: opened.sessionID))
        let texture = try XCTUnwrap(withDate.texture)
        XCTAssertGreaterThan(texture.width, 800, "film border must extend the picture")
        let thumbnail = try XCTUnwrap(DevelopPreset.previewImage(texture: texture, adjustments: prepared.adjustments, device: gpu))
        _ = try await client.call(.setParams, SetParamsRequest(sessionID: opened.sessionID,
            paramsDelta: ["date_imprint_active": .bool(false)])) as SetParamsResponse
        let withoutDate = try await client.render(.reprint, RenderRequest(sessionID: opened.sessionID))
        let other = try XCTUnwrap(DevelopPreset.previewImage(texture: XCTUnwrap(withoutDate.texture), adjustments: prepared.adjustments, device: gpu))
        XCTAssertNotEqual(thumbnail.dataProvider?.data as Data?, other.dataProvider?.data as Data?, "date must reach thumbnail pixels")
        await client.stop()
    }

    func testPresetPreviewCacheIgnoresLibraryMetadataButTracksEffectsAndPhotoState() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "preset-cache-" + UUID().uuidString)
        try Data([0]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var target = Sidecar()
        var preset = DevelopPreset(name: "Original", source: target)
        preset.settings = target
        preset.includesEffects = true
        let original = PresetPreviewCache.key(for: preset, target: target, url: url)
        preset.name = "Renamed"
        preset.category = "Favorites"
        preset.favorite = true
        XCTAssertEqual(original, PresetPreviewCache.key(for: preset, target: target, url: url))
        target.adjustments.exposure = 1
        XCTAssertEqual(original, PresetPreviewCache.key(for: preset, target: target, url: url),
            "a target edit overwritten by the preset must not invalidate its preview")
        preset.settings.params.filmEdge.active.toggle()
        XCTAssertNotEqual(original, PresetPreviewCache.key(for: preset, target: target, url: url))
        preset.settings.params.filmEdge.active.toggle()
        target.params.dateBack.active = true
        XCTAssertNotEqual(original, PresetPreviewCache.key(for: preset, target: target, url: url))
        target.params.dateBack.active = false
        try Data([0, 1]).write(to: url)
        XCTAssertNotEqual(original, PresetPreviewCache.key(for: preset, target: target, url: url))
    }

    func testPresetPreviewCacheKeepsPreviousImageWhileNewEffectIsMissing() {
        let cache = PresetPreviewCache()
        let image = NSImage(size: CGSize(width: 240, height: 180))
        var preset = DevelopPreset(name: "Preview", source: Sidecar())
        let url = URL(fileURLWithPath: "/tmp/preset-preview-a.tif")
        let previous = PresetPreviewCache.previousKey(for: preset, url: url)
        cache.store(image, for: previous)
        preset.settings.params.dateBack.active = true
        XCTAssertNil(cache.image(for: PresetPreviewCache.key(for: preset, target: Sidecar(), url: url)))
        XCTAssertTrue(cache.image(for: PresetPreviewCache.previousKey(for: preset, url: url)) === image)
        XCTAssertNil(cache.image(for: PresetPreviewCache.previousKey(for: preset,
            url: URL(fileURLWithPath: "/tmp/preset-preview-b.tif"))))
    }

    func testPresetPreviewQueuePrioritisesVisibleCardsAndOnlyPreloadsNextRow() {
        let presets = (0..<20).map { DevelopPreset(name: String($0), source: Sidecar()) }
        XCTAssertEqual(PresetPreviewCache.requested(presets, onScreen: []).map { $0.id },
            presets.prefix(4).map { $0.id })
        let requested = PresetPreviewCache.requested(presets, onScreen: [presets[10].id, presets[11].id])
        XCTAssertEqual(requested.map { $0.id }, Array(presets[10...13]).map { $0.id })
        let last = PresetPreviewCache.requested(presets, onScreen: [presets[19].id])
        XCTAssertEqual(last.map { $0.id }, [presets[19].id])
        XCTAssertTrue(PresetPreviewCache.requested([], onScreen: []).isEmpty)
    }

}
