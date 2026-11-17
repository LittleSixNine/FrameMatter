import XCTest

@MainActor
final class SessionPrintWritebackTests: XCTestCase {
    private func frames() throws -> (URL, URL) {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "tests/Test_image/_smoke_1mp.tif")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: source.path),
                          "the 1 MP smoke frame is not in this checkout")
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "spk-print-writeback-session-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let first = dir.appending(path: "first.tif")
        let second = dir.appending(path: "second.tif")
        try FileManager.default.copyItem(at: source, to: first)
        try FileManager.default.copyItem(at: source, to: second)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return (first, second)
    }

    private func diagnostics() throws -> Diagnostics {
        let name = "spk-print-writeback-defaults-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        let diagnostics = Diagnostics(defaults: defaults)
        // These sessions test cache admission, not the machine's free-memory reserve.
        diagnostics.memoryReserveMegabytes = 0
        return diagnostics
    }

    private func waitUntil(_ what: String, timeout: Double = 90,
                           _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("timed out waiting for \(what)")
    }

    func testFrameSwitchPersistsTheLivePrintForFreshSessionRestore() async throws {
        let (firstURL, secondURL) = try frames()
        let store = try DiskCacheStore(
            root: FileManager.default.temporaryDirectory
                .appending(path: "spk-print-writeback-store-\(UUID().uuidString)")
        )
        let firstDiagnostics = try diagnostics()
        let first = Session(diagnostics: firstDiagnostics, diskCache: store)
        first.open(urls: [firstURL])
        try await waitUntil("the frame to decode") { first.decoded != nil }
        try await waitUntil("the engine to warm up") { first.serviceReady }
        first.solveNow()
        try await waitUntil("the print to land") {
            first.frameStates[firstURL] == .processed && !first.busy
        }

        let original = try XCTUnwrap(first.renderer.store.print(for: firstURL))
        let bytes = original.rgba16Bytes()
        let version = firstDiagnostics.engineVersion ?? "unknown"
        let key = Session.printCacheKey(
            url: firstURL,
            params: first.scheduler.sent,
            settings: first.decode,
            tier: .live,
            previewLongEdge: first.previewLongEdge,
            engineVersion: version
        )

        first.select(secondURL)
        let deadline = Date().addingTimeInterval(15)
        var payload = try await store.load(key)
        while payload == nil && Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
            payload = try await store.load(key)
        }
        let stored = try XCTUnwrap(payload)
        XCTAssertEqual(stored.data, bytes, "the writeback changed the print bytes")

        let secondDiagnostics = try diagnostics()
        secondDiagnostics.noteCapabilities(json: nil, version: version)
        let second = Session(diagnostics: secondDiagnostics, diskCache: store)
        second.open(urls: [firstURL])
        try await waitUntil("the print to restore") {
            second.renderer.store.print(for: firstURL) != nil
        }
        let restored = try XCTUnwrap(second.renderer.store.print(for: firstURL))
        XCTAssertEqual(restored.rgba16Bytes(), bytes)
        XCTAssertEqual(second.decodeCount, 0,
                       "the restored print decoded a frame before it was needed")
    }
    /// Real RAW / independent sessions: A remains on disk while another
    /// session saves B. A fresh open must not claim A is B's finished print.
    func testRAWDecodeChangeDoesNotRestoreOldPrint() async throws {
        let source = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FRAMEMATTER_TEST_RAW"]
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appending(path: "tests/Test_image/A7m3/DSC03710.ARW").path)
        try XCTSkipUnless(FileManager.default.fileExists(atPath: source.path), "RAW fixture missing")
        let root = FileManager.default.temporaryDirectory.appending(path: "print-ab-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let priorStore = Sidecar.storeDirectory
        Sidecar.useStore(at: root.appending(path: "sidecars"))
        defer {
            Sidecar.useStore(at: priorStore)
            try? FileManager.default.removeItem(at: root)
        }
        let url = root.appending(path: "frame.ARW")
        try FileManager.default.copyItem(at: source, to: url)
        let store = try DiskCacheStore(root: root.appending(path: "cache-A"))
        var edit = Sidecar()
        edit.params.grainActive = false
        edit.params.glareActive = false
        edit.decode.whiteBalance = .custom
        edit.decode.temperature = 2800
        edit.decode.tint = -20
        try edit.save(for: url)
        let a = Session(diagnostics: try diagnostics(), diskCache: store)
        a.open(urls: [url])
        try await waitUntil("A decode") { a.decoded != nil }
        _ = await a.ensureDeveloped()
        try await waitUntil("A live") { a.renderer.store.print(for: url) != nil && !a.busy }
        let aPixels = try XCTUnwrap(a.renderer.store.print(for: url)).rgba16Bytes()
        a.flushSave()
        let entry = try XCTUnwrap(a.renderer.store.printEntry(for: url))
        let key = try XCTUnwrap(entry.cacheKey)
        // Exercise the real frame-switch writer and wait for its completed row.
        let other = root.appending(path: "other.tif")
        try Data().write(to: other)
        a.select(other)
        let deadline = Date().addingTimeInterval(20)
        while try await store.load(key) == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let written = try await store.load(key)
        XCTAssertEqual(written?.data, aPixels)

        a.open(urls: [url, other])
        edit = try XCTUnwrap(Sidecar.load(for: url))
        edit.decode.temperature = 8500
        edit.decode.tint = 30
        try edit.save(for: url)
        // Independent B producer, isolated cache; same film params, no solve.
        let b = Session(diagnostics: try diagnostics(),
                        diskCache: try DiskCacheStore(root: root.appending(path: "cache-B")))
        b.open(urls: [url])
        try await waitUntil("B decode") { b.decoded != nil }
        let bSID = await b.ensureDeveloped()
        print("PRINT_AB B_sid=\(String(describing: bSID)) status=\(b.status) error=\(String(describing: b.lastError))")
        try await waitUntil("B live") { b.renderer.store.print(for: url) != nil && !b.busy }
        let bPixels = try XCTUnwrap(b.renderer.store.print(for: url)).rgba16Bytes()
        XCTAssertFalse(aPixels == bPixels, "the WB control did not change actual pixels")
        b.flushSave()
        b.open(urls: [url, other])

        let restored = Session(diagnostics: try diagnostics(), diskCache: store)
        restored.open(urls: [url])
        try await waitUntil("fresh B open") {
            restored.renderer.store.print(for: url) != nil || restored.decoded != nil
        }
        if let cached = restored.renderer.store.print(for: url) {
            print("PRINT_AB wrong_hit_equals_A=\(cached.rgba16Bytes() == aPixels)")
        }
        XCTAssertNil(restored.renderer.store.print(for: url), "A was accepted as B's finished print")
        print("PRINT_AB fresh_open decode=\(restored.decodeCount) cached=\(restored.renderer.store.print(for: url) != nil)")
        let freshSID = await restored.ensureDeveloped()
        print("PRINT_AB fresh_sid=\(String(describing: freshSID)) status=\(restored.status) error=\(String(describing: restored.lastError))")
        try await waitUntil("fresh B develop", timeout: 5) { restored.renderer.store.print(for: url) != nil && !restored.busy }
        let actual = try XCTUnwrap(restored.renderer.store.print(for: url)).rgba16Bytes()
        XCTAssertTrue(actual == bPixels, "fresh B differs from forced B")
        restored.flushSave()
        let bEntry = try XCTUnwrap(restored.renderer.store.printEntry(for: url))
        let bKey = try XCTUnwrap(bEntry.cacheKey)
        restored.select(other)
        let warmDeadline = Date().addingTimeInterval(20)
        while try await store.load(bKey) == nil, Date() < warmDeadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let warm = Session(diagnostics: try diagnostics(), diskCache: store)
        warm.open(urls: [url])
        try await waitUntil("B warm restore") { warm.renderer.store.print(for: url) != nil }
        XCTAssertTrue(try XCTUnwrap(warm.renderer.store.print(for: url)).rgba16Bytes() == bPixels)
        XCTAssertEqual(warm.decodeCount, 0)
        warm.open(urls: [url, other])
        restored.select(url)
        let priorEdge = restored.previewLongEdge
        defer { restored.setPreviewLongEdge(priorEdge) }
        _ = await restored.ensureDeveloped()
        restored.setPreviewLongEdge(1080)
        restored.setPreviewLongEdge(3840)
        try await waitUntil("the latest directly requested preview edge", timeout: 30) {
            guard let entry = restored.renderer.store.printEntry(for: url) else { return false }
            return entry.cacheKey?.previewLongEdge == 3840 && max(entry.texture.width, entry.texture.height) == 3840
        }
        restored.select(other)
        // Returning to an in-memory print must also use its input identity.
        var undo = try XCTUnwrap(Sidecar.load(for: url))
        undo.decode.temperature = 2800
        undo.decode.tint = -20
        try undo.save(for: url)
        restored.select(url)
        XCTAssertNil(restored.renderer.store.print(for: url), "RAM B was accepted after undo to A")
        restored.open(urls: [url, other])
        print("PRINT_AB source=RAW A_bytes=\(aPixels.count) B_bytes=\(bPixels.count) A_equals_B=\(aPixels == bPixels) restored_equals_B=\(actual == bPixels) root=\(root.path)")
    }



}
