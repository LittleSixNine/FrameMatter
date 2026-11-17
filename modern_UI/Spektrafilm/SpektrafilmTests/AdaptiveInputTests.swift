import CoreImage
import XCTest

@MainActor
final class AdaptiveInputTests: XCTestCase {
    func testNewPhotoDefaultsAndLegacyMissingFieldsRemainSeparate() throws {
        XCTAssertEqual(Sidecar.newPhoto.params.autoExposureMethod, "adaptive")
        XCTAssertEqual(Sidecar.newPhoto.decode.rawInterpretation, .shadowNeutralV1)
        let old = try JSONDecoder().decode(Sidecar.self, from: Data("{}".utf8))
        XCTAssertEqual(old.decode.rawInterpretation, .legacy)
        XCTAssertEqual(old.params.autoExposureMethod, "balanced")
        let legacyDecode = Data(#"{"whiteBalance":"As Shot","temperature":5500,"tint":0,"lensCorrection":false}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(DecodeSettings.self, from: legacyDecode).rawInterpretation, .legacy)
        let fresh = Sidecar.newPhoto
        XCTAssertEqual(try JSONDecoder().decode(Sidecar.self, from: JSONEncoder().encode(fresh)), fresh)
        let document = String(decoding: try JSONEncoder().encode(fresh), as: UTF8.self)
        XCTAssertFalse(document.contains("faces"))
        XCTAssertFalse(document.contains(FrameFaceDetector.identity))
    }

    func testDecodeCacheKeepsLegacyBytesAndSeparatesNeutral() throws {
        let legacy = DecodeSettings()
        let expected = #"{"lensCorrection":false,"temperature":5500,"tint":0,"whiteBalance":"As Shot"}"#
        XCTAssertEqual(CacheKey.decodeConfiguration(legacy), expected)
        var neutral = legacy
        neutral.rawInterpretation = .shadowNeutralV1
        XCTAssertNotEqual(CacheKey.decodeConfiguration(legacy), CacheKey.decodeConfiguration(neutral))
        let url = URL(fileURLWithPath: "/tmp/adaptive-input-cache.ARW")
        let a = Session.printCacheKey(url: url, params: .default, settings: legacy,
                                     tier: .live, previewLongEdge: 2560, engineVersion: "test")
        let b = Session.printCacheKey(url: url, params: .newPhoto, settings: neutral,
                                     tier: .live, previewLongEdge: 2560, engineVersion: "test")
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(b.configuration.contains(FrameFaceDetector.identity))
        XCTAssertFalse(a.configuration.contains(FrameFaceDetector.identity))
    }

    func testCopyExposureDoesNotCopyDecodeAndRAWGroupIsExplicit() {
        let source = Sidecar.newPhoto, target = Sidecar()
        let exposure = SettingsClip(groups: [.exposure], settings: source, sourceName: "source").applied(to: target)
        XCTAssertEqual(exposure.params.autoExposureMethod, "adaptive")
        XCTAssertEqual(exposure.decode.rawInterpretation, .legacy)
        let clip = SettingsClip(groups: [.rawInterpretation], settings: source, sourceName: "source")
        let copied = clip.applied(to: target)
        XCTAssertEqual(copied.decode.rawInterpretation, .shadowNeutralV1)
        XCTAssertEqual(copied.params, target.params)
        XCTAssertEqual(clip.applied(to: target, perspectiveAllowed: false), target)
    }

    func testAgentPatchKeepsMeterAndDecodeIndependentAndRejectsFaceEdits() throws {
        let before = AgentDocument(params: .default, adjustments: .default, geometry: .default, decode: DecodeSettings())
        let changed = try before.merged(with: ["params": ["autoExposureMethod": "adaptive"]])
        XCTAssertEqual(changed.decode.rawInterpretation, .legacy)
        let decoded = try before.merged(with: ["decode": ["rawInterpretation": "shadowNeutralV1"]])
        XCTAssertEqual(decoded.params, before.params)
        XCTAssertThrowsError(try AgentDocument.validate(["decode": ["rawInterpretation": "unknown"]]))
        XCTAssertThrowsError(try AgentDocument.validate(["decode": ["faces": []]]))
    }

    func testFaceExtentRejectsNonfiniteEmptyAndOverflowBeforeConversion() throws {
        XCTAssertEqual(try FrameFaceDetector.sourceSize(CGRect(x: 0, y: 0, width: 1600, height: 1067)).width, 1600)
        for extent in [CGRect.zero, CGRect.infinite,
                       CGRect(x: 0, y: 0, width: Double(Int.max), height: 2),
                       CGRect(x: 0, y: 0, width: 1e10, height: 1e10)] {
            XCTAssertThrowsError(try FrameFaceDetector.sourceSize(extent))
        }
    }

    func testNewRAWClipboardGroupStartsOff() throws {
        let name = "adaptive-clipboard-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let session = Session(clipboardDefaults: defaults)
        XCTAssertFalse(session.clipboardGroups.contains(.rawInterpretation))
        session.clipboardGroups.insert(.rawInterpretation)
        XCTAssertTrue(Session(clipboardDefaults: defaults).clipboardGroups.contains(.rawInterpretation))
    }

    func testSuccessfulNoFaceEvidenceAndPerDecodeCache() throws {
        let solid = CIImage(color: CIColor(red: 0.2, green: 0.2, blue: 0.2))
            .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 48))
        let lifetime = DecodeLifetime()
        let evidence = try lifetime.faceEvidence(display: solid, key: "same-domain")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(evidence.utf8)) as? [String: Any])
        XCTAssertEqual(json["width"] as? Int, 64)
        XCTAssertEqual(json["height"] as? Int, 48)
        XCTAssertEqual(json["detector"] as? String, FrameFaceDetector.identity)
        XCTAssertEqual((json["faces"] as? [[String: Any]])?.count, 0)
        // A hit must not invoke Vision or try to render another image.
        XCTAssertEqual(try lifetime.faceEvidence(display: CIImage.empty(), key: "same-domain"), evidence)
        XCTAssertThrowsError(try lifetime.faceEvidence(display: CIImage.empty(), key: "changed-domain"))
        XCTAssertThrowsError(try DecodeLifetime().faceEvidence(display: CIImage.empty(), key: "same-domain"))
    }

    func testTileGeometryUsesActualIntegerRectsAndBottomLeftMapping() {
        let rects = FrameFaceDetector.tileRects(width: 1600, height: 1067)
        XCTAssertEqual(rects, [CGRect(x: 0, y: 426, width: 960, height: 641),
                             CGRect(x: 640, y: 426, width: 960, height: 641),
                             CGRect(x: 0, y: 0, width: 960, height: 641),
                             CGRect(x: 640, y: 0, width: 960, height: 641)])
        let bottom = FrameFaceDetector.normalizedROI(rects[0], width: 1600, height: 1067)
        let top = FrameFaceDetector.normalizedROI(rects[2], width: 1600, height: 1067)
        XCTAssertEqual(bottom.minY, 0)
        XCTAssertEqual(top.maxY, 1)
        XCTAssertEqual(bottom.width, 0.6)
        XCTAssertEqual(bottom.height, 641.0 / 1067)
        let portrait = FrameFaceDetector.tileRects(width: 1067, height: 1600)
        XCTAssertEqual(portrait[0].width, 641)
        XCTAssertEqual(portrait[0].height, 960)
    }

    func testNeutralRAWOnlyChangesShadowInterpretation() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let standard = root.appending(path: "tests/Test_image/Nikon Z7ii/_DSC2439.NEF")
        let privateRAW = root.appending(path: "pravite/02-研究与实验/相对测光候选v2-20261109/16/C/2026.11.01.140334.ILCE-7CM2.ARW")
        let url = FileManager.default.fileExists(atPath: standard.path) ? standard : privateRAW
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "RAW fixture unavailable")
        var neutral = DecodeSettings()
        neutral.rawInterpretation = .shadowNeutralV1
        for look in [ImageDecoder.RAWLook.linear, .display] {
            let legacy = try ImageDecoder.rawFilter(url, look: look, settings: DecodeSettings()).filter
            let current = try ImageDecoder.rawFilter(url, look: look, settings: neutral).filter
            XCTAssertEqual(current.shadowBias, 0)
            XCTAssertEqual(current.baselineExposure, legacy.baselineExposure)
            XCTAssertEqual(current.exposure, legacy.exposure)
            XCTAssertEqual(current.neutralTemperature, legacy.neutralTemperature)
            XCTAssertEqual(current.neutralTint, legacy.neutralTint)
            XCTAssertEqual(current.boostAmount, legacy.boostAmount)
            XCTAssertEqual(current.boostShadowAmount, legacy.boostShadowAmount)
            XCTAssertEqual(current.outputImage?.extent, legacy.outputImage?.extent)
        }
    }
}
