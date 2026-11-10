import CoreImage
import ImageIO
import UniformTypeIdentifiers
import XCTest

@MainActor
final class AdaptiveSessionTests: XCTestCase {
    private func image(gradient: Bool = false, highlight: Bool = false) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "adaptive-session-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "synthetic.png")
        let solid = CIImage(color: CIColor(red: 0.25, green: 0.3, blue: 0.2))
        let content = gradient ? try XCTUnwrap(CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 240, y: 0),
            "inputColor0": CIColor(red: 0.01, green: 0.01, blue: 0.01),
            "inputColor1": CIColor(red: 0.95, green: 0.95, blue: 0.95)])?.outputImage) : solid
        let highContrast = CIImage(color: CIColor(red: 0.9, green: 0.9, blue: 0.9))
            .cropped(to: CGRect(x: 210, y: 0, width: 30, height: 180))
            .composited(over: CIImage(color: CIColor(red: 0.003, green: 0.003, blue: 0.003)))
        let image = (highlight ? highContrast : content).cropped(to: CGRect(x: 0, y: 0, width: 240, height: 180))
        let cg = try XCTUnwrap(ImageDecoder.context.createCGImage(image, from: image.extent))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return url
    }
    private func wait(_ condition: @MainActor () -> Bool) async throws {
        let end = Date().addingTimeInterval(30)
        while !condition() {
            if Date() > end { throw NSError(domain: "AdaptiveSessionTests timeout", code: 1) }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    private func opened(_ url: URL) async throws -> Session {
        let session = Session()
        session.open(urls: [url])
        try await wait { session.decoded != nil && session.serviceReady }
        let developed = await session.ensureDeveloped()
        _ = try XCTUnwrap(developed, session.status)
        return session
    }

    func testNewPhotoSavesReopensAndDecodeUndoRedoIsIndependentOfMeter() async throws {
        let url = try image()
        let session = try await opened(url)
        XCTAssertEqual(session.params.autoExposureMethod, "adaptive")
        XCTAssertEqual(session.decode.rawInterpretation, .shadowNeutralV1)
        session.flushSave()
        let saved = try XCTUnwrap(Sidecar.load(for: url))
        XCTAssertEqual(saved.params.autoExposureMethod, "adaptive")
        XCTAssertEqual(saved.decode.rawInterpretation, .shadowNeutralV1)
        var decode = session.decode
        decode.rawInterpretation = .legacy
        session.decode = decode
        XCTAssertEqual(session.params.autoExposureMethod, "adaptive")
        session.undo()
        XCTAssertEqual(session.decode.rawInterpretation, .shadowNeutralV1)
        session.redo()
        XCTAssertEqual(session.decode.rawInterpretation, .legacy)
        session.flushSave()
        session.remove(url)
        await session.client.stop()
        let reopened = try await opened(url)
        XCTAssertEqual(reopened.decode.rawInterpretation, .legacy)
        XCTAssertEqual(reopened.params.autoExposureMethod, "adaptive")
        reopened.remove(url)
        await reopened.client.stop()
    }

    func testExistingSidecarStaysLegacyAndSwitchingAdaptiveReopensWithEvidence() async throws {
        let url = try image()
        try Sidecar().save(for: url)
        let session = try await opened(url)
        XCTAssertEqual(session.params.autoExposureMethod, "balanced")
        XCTAssertEqual(session.decode.rawInterpretation, .legacy)
        let oldSession = session.serviceSessionIDForExport
        session.aeMethod = .metered(.adaptive)
        try await wait { session.serviceSessionIDForExport != nil && session.serviceSessionIDForExport != oldSession && !session.busy }
        XCTAssertEqual(session.decode.rawInterpretation, .legacy)
        let sid = try XCTUnwrap(session.serviceSessionIDForExport)
        let solved = try await session.client.call(.solve, SolveRequest(sessionID: sid, target: "exposure"), as: SolveResponse.self)
        XCTAssertNotNil(solved.exposureEvByMethod?["adaptive"])
        await session.client.stop()
    }

    func testCustomDormantAdaptiveSolvesPrintWithoutApplyingExposureThenReturnsAdaptive() async throws {
        let url = try image()
        var saved = Sidecar.newPhoto
        saved.params.autoExposure = false
        saved.params.exposureCompensationEV = 0.75
        try saved.save(for: url)
        let session = try await opened(url)
        XCTAssertFalse(session.params.autoExposure)
        let sid = try XCTUnwrap(session.serviceSessionIDForExport)
        let solved = try await session.client.call(.solve, SolveRequest(sessionID: sid, target: "both"), as: SolveResponse.self)
        XCTAssertNil(solved.solvedParams["exposure_compensation_ev"])
        XCTAssertNotNil(solved.exposureEvByMethod?["balanced"])
        XCTAssertNil(solved.exposureEvByMethod?["adaptive"])
        session.solveNow()
        try await wait { !session.busy }
        XCTAssertTrue(session.status.hasPrefix("Solved"), session.status)
        XCTAssertEqual(session.params.exposureCompensationEV, 0.75)
        XCTAssertFalse(session.params.autoExposure)
        session.aeMethod = .metered(.adaptive)
        try await wait { session.serviceSessionIDForExport != nil && session.serviceSessionIDForExport != sid && !session.busy }
        XCTAssertEqual(session.params.exposureCompensationEV, 0.75)
        let active = try XCTUnwrap(session.serviceSessionIDForExport)
        let activeSolved = try await session.client.call(.solve, SolveRequest(sessionID: active, target: "exposure"), as: SolveResponse.self)
        XCTAssertNotNil(activeSolved.exposureEvByMethod?["adaptive"])
        await session.client.stop()
    }
    func testAdaptivePairMetersCanonicalSourceOnceAndInvalidatesOnlySourceEdits() async throws {
        let source = try image()
        let folder = source.deletingLastPathComponent()
        var pair = HalfFramePair(folder: folder.path)
        var hole = Session.hole(for: source)
        hole.meterMethod = "adaptive"
        pair.left = hole
        let url = HalfFramePair.newURL(in: folder)
        try pair.save(to: url)
        var look = Sidecar.newPhoto
        look.params.autoExposure = false
        try look.save(for: url)
        let session = try await opened(url)
        let count = session.pairMeterRuns
        XCTAssertEqual(count, 1)
        let originalEV = try XCTUnwrap(session.pair?.left?.meteredEV)
        let originalKey = try XCTUnwrap(session.pair?.left?.meteredFor)
        let lifetime = try XCTUnwrap(session.decoded?.lifetime)
        session.setPlacement(.left) { $0.scale = 1.5; $0.x = 0.3 }
        try await wait { session.decoded?.lifetime !== lifetime && session.serviceSessionIDForExport != nil && !session.busy }
        XCTAssertEqual(session.pairMeterRuns, count, "placement ran the meter/Vision again")
        XCTAssertEqual(session.pair?.left?.meteredEV, originalEV)
        XCTAssertEqual(session.pair?.left?.meteredFor, originalKey)
        session.pairLayer = .left
        var input = session.decode
        input.rawInterpretation = .legacy
        session.decode = input
        try await wait { session.pairMeterRuns == count + 1 && !session.busy }
        let changedKey = session.pair?.left?.meteredFor
        XCTAssertNotEqual(changedKey, originalKey)
        var saved = try XCTUnwrap(Sidecar.load(for: source))
        saved.geometry.quarterTurns = 1
        try saved.save(for: source)
        session.setHole(.left, to: source)
        try await wait { session.pairMeterRuns == count + 2 && !session.busy }
        XCTAssertNotEqual(session.pair?.left?.meteredFor, changedKey)
        session.remove(url)
        await session.client.stop()
    }

    func testAgentDecodeEditWaitsForReopenBeforeAndAfterCustomDevelop() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let raw = root.appending(path: "pravite/02-研究与实验/相对测光候选v2-20261109/01/C/2026.01.01.213823.ILCE-7CM2.ARW")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: raw.path), "private RAW reproduction fixture unavailable")
        for alreadyDeveloped in [false, true] {
            let folder = FileManager.default.temporaryDirectory.appending(path: "adaptive-agent-edit-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: raw.lastPathComponent)
            try FileManager.default.copyItem(at: raw, to: url)
            defer { try? FileManager.default.removeItem(at: folder) }
            let workspace = AgentWorkspace()
            try await workspace.open(url.path)
            if alreadyDeveloped {
                try await workspace.process()
                _ = try await workspace.edit(["params": ["autoExposure": false, "exposureCompensationEV": 1.25]])
            }
            _ = try await workspace.edit(["decode": ["rawInterpretation": "legacy"]])
            XCTAssertEqual(workspace.session.decode.rawInterpretation, .legacy)
            XCTAssertNotNil(workspace.session.serviceSessionIDForExport)
            XCTAssertEqual(Sidecar.load(for: url)?.decode.rawInterpretation, .legacy)
            if alreadyDeveloped {
                XCTAssertFalse(workspace.session.params.autoExposure)
                XCTAssertEqual(workspace.session.params.exposureCompensationEV, 1.25)
            }
            workspace.session.remove(url)
            await workspace.session.client.stop()
        }
    }

    func testAdaptivePairKeepsExistingUndecodableSourceAsEmptyHole() async throws {
        let source = try image()
        let folder = source.deletingLastPathComponent()
        let broken = folder.appending(path: "broken.png")
        try Data("not an image".utf8).write(to: broken)
        var pair = HalfFramePair(folder: folder.path)
        var left = Session.hole(for: source), right = Session.hole(for: broken)
        left.meterMethod = "adaptive"; right.meterMethod = "adaptive"
        pair.left = left; pair.right = right
        let url = HalfFramePair.newURL(in: folder)
        try pair.save(to: url)
        var look = Sidecar.newPhoto
        look.params.autoExposure = false
        try look.save(for: url)
        let session = try await opened(url)
        XCTAssertNotNil(session.decoded?.pairMeterInputs[.left])
        XCTAssertNil(session.decoded?.pairMeterInputs[.right])
        XCTAssertEqual(session.pairMeterRuns, 1)
        XCTAssertNotNil(session.pair?.left?.meteredEV)
        XCTAssertNil(session.pair?.right?.meteredEV)
        session.remove(url)
        await session.client.stop()
    }

    func testAdaptivePairExposureEqualsIndependentSourceDespitePlacement() async throws {
        let source = try image(gradient: true)
        let independent = try await opened(source)
        let expected = try XCTUnwrap(independent.sidecar.solvedEV)
        independent.flushSave()
        independent.remove(source)
        await independent.client.stop()
        let folder = source.deletingLastPathComponent()
        var pair = HalfFramePair(folder: folder.path)
        var hole = Session.hole(for: source)
        hole.meterMethod = "adaptive"
        hole.placement.scale = 2
        hole.placement.x = 1
        pair.left = hole
        let url = HalfFramePair.newURL(in: folder)
        try pair.save(to: url)
        var look = Sidecar.newPhoto
        look.params.autoExposure = false
        try look.save(for: url)
        let session = try await opened(url)
        XCTAssertEqual(try XCTUnwrap(session.pair?.left?.meteredEV), expected, accuracy: 1e-9)
        session.remove(url)
        await session.client.stop()
    }

    func testCancelledQueuedEngineOpenDoesNotRun() async throws {
        let source = try image()
        let decoded = try ImageDecoder.decode(source, settings: DecodeSettings())
        let session = Session()
        let frame = try ImageDecoder.engineFrame(from: decoded, device: session.renderer.device)
        let client = session.client
        _ = try await client.open(frame, paramsDelta: Session.openDelta(sidecar: Sidecar(), previewLongEdge: 2560))
        let task = Task { try await client.open(frame, paramsDelta: [:]) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("cancelled frame replaced the engine session")
        } catch is CancellationError { }
        await client.stop()
    }

    func testSameURLDecodeEditDuringOpenDiscardsOldPixelsAndJoinsLatestDevelop() async throws {
        let url = try image()
        let workspace = AgentWorkspace()
        try await workspace.open(url.path)
        let oldLifetime = try XCTUnwrap(workspace.session.decoded?.lifetime)
        workspace.session.afterOpenDeltaForTesting = {
            workspace.session.afterOpenDeltaForTesting = nil
            var decode = workspace.session.decode
            decode.rawInterpretation = .legacy
            workspace.session.decode = decode
        }
        try await workspace.develop()
        XCTAssertTrue(workspace.session.decoded?.lifetime !== oldLifetime,
                      "the call returned a frame made from the superseded decode")
        XCTAssertEqual(workspace.session.decode.rawInterpretation, .legacy)
        XCTAssertEqual(Sidecar.load(for: url)?.decode.rawInterpretation, .legacy)
        workspace.session.remove(url)
        await workspace.session.client.stop()
    }

    func testFramingEditDuringOpenDiscardsOldCutAndJoinsLatestDevelop() async throws {
        let url = try image()
        let workspace = AgentWorkspace()
        try await workspace.open(url.path)
        var opens = 0
        workspace.session.afterOpenDeltaForTesting = {
            opens += 1
            if opens == 1 {
                var params = workspace.session.params
                params.filmEdge.active = true
                workspace.session.params = params
            } else {
                workspace.session.afterOpenDeltaForTesting = nil
            }
        }
        try await workspace.develop()
        XCTAssertGreaterThanOrEqual(opens, 2, "the superseded uncut input was published")
        XCTAssertNotNil(workspace.session.wantedEngineFraming)
        XCTAssertNotNil(workspace.session.serviceSessionIDForExport)
        workspace.session.remove(url)
        await workspace.session.client.stop()
    }

    func testMeterEditDuringOpenReportsCurrentAdaptiveBaseline() async throws {
        let url = try image(highlight: true)
        try Sidecar().save(for: url)
        let workspace = AgentWorkspace()
        try await workspace.open(url.path)
        workspace.session.afterOpenDeltaForTesting = {
            workspace.session.afterOpenDeltaForTesting = nil
            workspace.session.aeMethod = .metered(.adaptive)
        }
        try await workspace.develop()
        let sid = try XCTUnwrap(workspace.session.serviceSessionIDForExport)
        let solved = try await workspace.session.client.call(.solve,
            SolveRequest(sessionID: sid, target: "exposure"), as: SolveResponse.self)
        let adaptive = try XCTUnwrap(solved.exposureEvByMethod?["adaptive"])
        let balanced = try XCTUnwrap(solved.exposureEvByMethod?["balanced"])
        XCTAssertGreaterThan(abs(adaptive - balanced), 0.25, "test scene does not distinguish the methods")
        XCTAssertEqual(try XCTUnwrap(workspace.session.sidecar.solvedEV), adaptive, accuracy: 1e-9)
        workspace.session.remove(url)
        await workspace.session.client.stop()
    }

}
