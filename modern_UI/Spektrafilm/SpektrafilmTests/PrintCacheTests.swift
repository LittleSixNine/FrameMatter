import XCTest

@MainActor
final class PrintCacheTests: XCTestCase {
    private func smokeFrame() throws -> URL {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "tests/Test_image/_smoke_1mp.tif")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: source.path),
                          "the 1 MP smoke frame is not in this checkout")
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "spk-print-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return url
    }

    private func diagnostics() throws -> Diagnostics {
        let name = "spk-print-defaults-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        return Diagnostics(defaults: defaults)
    }

    private func waitUntil(_ what: String, timeout: Double = 10,
                           _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("timed out waiting for \(what)")
    }

    func testStoredPrintRestoresExactBytesWithoutDecoding() async throws {
        let url = try smokeFrame()
        let diagnostics = try diagnostics()
        let store = try DiskCacheStore(
            root: FileManager.default.temporaryDirectory
                .appending(path: "spk-print-store-\(UUID().uuidString)")
        )
        let session = Session(diagnostics: diagnostics, diskCache: store)
        // Every disk-cache key carries the engine version, and warm-up
        // publishes it from a detached task. Wait for the real one rather than
        // planting a stub and racing it: a stub only survived while the lookup
        // beat warm-up, so this test passed on a cold process and failed once
        // enough earlier tests had warmed the engine. See `Session.awaitBoot`.
        try await waitUntil("warm-up to publish the engine version") {
            diagnostics.engineVersion != nil
        }
        let engineVersion = try XCTUnwrap(diagnostics.engineVersion)
        let pixels = Data([
            0x00, 0x00, 0x80, 0xff, 0x00, 0x00, 0xff, 0xff,
            0x00, 0x00, 0xff, 0x00, 0x00, 0x00, 0x80, 0x80,
        ])
        let key = Session.printCacheKey(
            url: url,
            params: FilmParams.default,
            tier: .live,
            previewLongEdge: session.previewLongEdge,
            engineVersion: engineVersion
        )
        try await store.store(
            key: key,
            data: pixels,
            width: 2,
            height: 1,
            sourceWidth: 5_504,
            sourceHeight: 8_256,
            format: "rgba16Unorm",
            costMs: 1_188
        )

        session.open(urls: [url])
        try await waitUntil("the print cache to land") {
            session.renderer.store.print(for: url) != nil
        }

        let texture = try XCTUnwrap(session.renderer.store.print(for: url))
        XCTAssertEqual(texture.rgba16Bytes(), pixels)
        XCTAssertFalse(session.previewSoft, "a restored print was marked as a soft decode")
        XCTAssertEqual(session.sourceLongEdge, 8_256)
        XCTAssertNil(session.decoded,
                     "the print cache synthesized scene-linear data")
        XCTAssertEqual(session.decodeCount, 0,
                       "restoring a print decoded the RAW again")
    }

    /// A print restored from disk comes with an original.
    ///
    /// The regression: on a relaunch the print cache ends the open before any
    /// decode, so `renderer.original` was nil and Original kept drawing the
    /// print. The display cache's decode preview fills it in without decoding.
    ///
    /// The frame is an empty `.tif`: this path never reads it (both caches
    /// answer first), and the camera fixtures are not in this checkout.
    func testARestoredPrintAlsoRestoresTheOriginal() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "spk-print-original-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "frame.tif")
        try Data().write(to: url)
        let diagnostics = try diagnostics()
        let store = try DiskCacheStore(
            root: FileManager.default.temporaryDirectory
                .appending(path: "spk-print-original-store-\(UUID().uuidString)")
        )
        let session = Session(diagnostics: diagnostics, diskCache: store)
        try await waitUntil("warm-up to publish the engine version") {
            diagnostics.engineVersion != nil
        }
        let engineVersion = try XCTUnwrap(diagnostics.engineVersion)
        let printPixels = Data(repeating: 0x22, count: 16)
        try await store.store(
            key: Session.printCacheKey(
                url: url, params: FilmParams.default, tier: .live,
                previewLongEdge: session.previewLongEdge, engineVersion: engineVersion
            ),
            data: printPixels, width: 2, height: 1,
            sourceWidth: 5_504, sourceHeight: 8_256, format: "rgba16Unorm", costMs: 1
        )
        let originalPixels = Data(repeating: 0x11, count: 16)
        try await store.store(
            key: Session.displayCacheKey(
                url: url, settings: DecodeSettings(),
                previewLongEdge: session.previewLongEdge, engineVersion: engineVersion
            ),
            data: originalPixels, width: 2, height: 1,
            sourceWidth: 5_504, sourceHeight: 8_256, format: "rgba16Unorm", costMs: 1
        )

        session.open(urls: [url])
        try await waitUntil("the print cache to land") {
            session.renderer.store.print(for: url) != nil
        }
        try await waitUntil("the original to land") {
            session.renderer.original != nil
        }

        XCTAssertEqual(try XCTUnwrap(session.renderer.original).rgba16Bytes(), originalPixels,
                       "the restored original is not the display cache's decode")
        XCTAssertEqual(session.decodeCount, 0,
                       "restoring the original decoded the RAW again")
    }

    func testEngineVersionPerturbationMissesThePrint() async throws {
        let url = try smokeFrame()
        let diagnostics = try diagnostics()
        diagnostics.noteCapabilities(json: nil, version: "new-engine")
        let store = try DiskCacheStore(
            root: FileManager.default.temporaryDirectory
                .appending(path: "spk-print-version-store-\(UUID().uuidString)")
        )
        let session = Session(diagnostics: diagnostics, diskCache: store)
        let key = Session.printCacheKey(
            url: url,
            params: FilmParams.default,
            tier: .live,
            previewLongEdge: session.previewLongEdge,
            engineVersion: "old-engine"
        )
        try await store.store(
            key: key,
            data: Data(repeating: 0x7f, count: 16),
            width: 2,
            height: 1,
            sourceWidth: 5_504,
            sourceHeight: 8_256,
            format: "rgba16Unorm",
            costMs: 1_188
        )

        session.open(urls: [url])
        try await waitUntil("the engine-version miss to decode") {
            session.decodeCount == 1
        }
        XCTAssertNil(session.renderer.store.print(for: url),
                     "a print made by a different engine version was restored")
    }
    func testPrintIdentityTracksDecodeButIgnoresAsShotReadouts() {
        let url = URL(fileURLWithPath: "/tmp/print-identity")
        func key(_ settings: DecodeSettings) -> CacheKey {
            Session.printCacheKey(url: url, params: .default, settings: settings,
                                  tier: .live, previewLongEdge: 2560, engineVersion: "test")
        }
        let original = DecodeSettings()
        var changed = original
        changed.temperature = 7800
        changed.tint = 17
        XCTAssertEqual(key(original), key(changed), "as-shot UI readouts changed actual input identity")
        changed.whiteBalance = .custom
        XCTAssertNotEqual(key(original), key(changed))
        let custom = key(changed)
        changed.lensCorrection.toggle()
        XCTAssertNotEqual(custom, key(changed))
        let old = CacheKey(kind: .printLive, sourceIdentity: key(original).sourceIdentity,
                           configuration: Session.printStamp(.default), tier: .live,
                           previewLongEdge: 2560, engineVersion: "test")
        XCTAssertNotEqual(old, key(original), "ambiguous legacy namespace is still readable")
    }

    func testDecodeEditDuringDiskLookupRejectsTheCompletedOldRead() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "print-read-race-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "frame.tif")
        try Data().write(to: url)
        let session = Session(diagnostics: try diagnostics(),
                              diskCache: try DiskCacheStore(root: root.appending(path: "cache")))
        try await waitUntil("engine version") { session.diagnostics.engineVersion != nil }
        let store = try DiskCacheStore(root: root.appending(path: "cache"))
        let key = Session.printCacheKey(url: url, params: .default, tier: .live,
                                       previewLongEdge: session.previewLongEdge,
                                       engineVersion: try XCTUnwrap(session.diagnostics.engineVersion))
        try await store.store(key: key, data: Data(repeating: 0x22, count: 16),
                              width: 2, height: 1, sourceWidth: 5504, sourceHeight: 8256,
                              format: "rgba16Unorm", costMs: 1)
        var lookedUp = false
        session.afterPrintLookupForTesting = {
            lookedUp = true
            var decode = session.decode
            decode.whiteBalance = .custom
            decode.temperature = 3200
            session.decode = decode
        }
        session.open(urls: [url])
        try await waitUntil("the in-flight lookup") { lookedUp }
        XCTAssertNil(session.renderer.store.print(for: url), "the completed A read was relabelled as B")
        session.afterPrintLookupForTesting = nil
    }

    func testRAMPrintRejectsChangedDecodeAndReplacedSource() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "print-ram-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for replaceSource in [false, true] {
            let url = root.appending(path: "frame-\(replaceSource).tif")
            try Data([1]).write(to: url)
            let session = Session(diagnostics: try diagnostics(),
                                  diskCache: try DiskCacheStore(root: root.appending(path: "cache-\(replaceSource)")))
            try await waitUntil("engine version") { session.diagnostics.engineVersion != nil }
            let key = Session.printCacheKey(url: url, params: .default, tier: .live,
                                           previewLongEdge: session.previewLongEdge,
                                           engineVersion: try XCTUnwrap(session.diagnostics.engineVersion))
            let texture = try XCTUnwrap(session.renderer.store.uploadRGBA16(
                data: Data(repeating: 0x22, count: 16), width: 2, height: 1))
            session.renderer.store.setPrint(texture, stamp: Session.printStamp(.default),
                                            for: url, cacheKey: key)
            if replaceSource {
                try Data([2, 3]).write(to: url, options: .atomic)
            } else {
                var edit = Sidecar()
                edit.decode.whiteBalance = .custom
                edit.decode.temperature = 3200
                try edit.save(for: url)
            }
            session.open(urls: [url])
            XCTAssertNil(session.renderer.store.print(for: url), "URL-only RAM hit survived changed input")
            session.open(urls: [])
        }
    }

    func testPreviewEdgeChangeRejectsAnAlreadyIssuedLiveResult() async throws {
        let url = try smokeFrame()
        let session = Session(diagnostics: try diagnostics(), diskCache: try DiskCacheStore(
            root: FileManager.default.temporaryDirectory.appending(path: "print-edge-\(UUID())")))
        session.open(urls: [url])
        try await waitUntil("decode") { session.decoded != nil }
        _ = await session.ensureDeveloped()
        let priorEdge = session.previewLongEdge
        defer { session.setPreviewLongEdge(priorEdge) }
        let keyForRender = session.scheduler.cacheKeyForRender
        let receive = session.scheduler.onResult
        var changed = false
        var rejected = false
        session.scheduler.cacheKeyForRender = { params in
            let key = keyForRender?(params)
            if !changed {
                changed = true
                session.setPreviewLongEdge(priorEdge == 1080 ? 3840 : 1080)
            }
            return key
        }
        session.scheduler.onResult = { result, generation, key in
            if let key, key.previewLongEdge != session.previewLongEdge {
                let before = session.renderer.store.print(for: url)
                receive?(result, generation, key)
                XCTAssertTrue(session.renderer.store.print(for: url) === before,
                              "an old live request was relabelled with the new preview edge")
                rejected = true
            } else { receive?(result, generation, key) }
        }
        defer {
            session.scheduler.cacheKeyForRender = keyForRender
            session.scheduler.onResult = receive
        }
        var params = session.params
        params.exposureCompensationEV += 0.5
        session.params = params
        try await waitUntil("the stale live result", timeout: 30) { rejected }
    }

}
