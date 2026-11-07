// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
// Applies only to FrameMatter contributions; upstream notices are retained. See COPYRIGHT.txt.

import XCTest
import ImageIO
import CryptoKit

@MainActor
final class ExportUserMetadataTests: XCTestCase {
    private struct Sample: Decodable {
        let file: String
        let make: String
        let model: String
        let offset: String
        let dateTime: String
        let iso: Int
        let hasGPS: Bool
    }
    private func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(180)
        while !condition() {
            guard Date() < deadline else { XCTFail("Timed out waiting for real-file export"); throw CancellationError() }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
    func testBothUserSamplesThroughActualExporter() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let folder = env["SPK_METADATA_SAMPLES"], let out = env["SPK_EXPORT_CHECKS"],
              let cases = env["SPK_METADATA_CASES"] else {
            throw XCTSkip("Opt in with local samples, a private case manifest and output folder")
        }
        let output = URL(fileURLWithPath: out)
        let inputs = output.appendingPathComponent("inputs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: inputs, withIntermediateDirectories: true)
        let samples = try JSONDecoder().decode([Sample].self, from: Data(contentsOf: URL(fileURLWithPath: cases)))
        XCTAssertFalse(samples.isEmpty, "The private manifest must exercise at least one source")
        for (index, sample) in samples.enumerated() {
            let original = URL(fileURLWithPath: folder).appendingPathComponent(sample.file)
            let hash = SHA256.hash(data: try Data(contentsOf: original))
            let input = inputs.appendingPathComponent(sample.file)
            try FileManager.default.copyItem(at: original, to: input)
            let session = Session()
            session.open(urls: [input])
            try await wait { session.decoded != nil && session.serviceReady }
            var p = session.params
            p.grainActive = false; p.glareActive = false
            session.params = p; session.solveNow()
            try await wait { session.serviceSessionIDForExport != nil && session.frameStates[input] == .processed && !session.busy }
            let sid = try XCTUnwrap(session.serviceSessionIDForExport)
            for format in [ExportFormat.jpeg, .tiff, .png] {
                var recipe = ExportRecipe()
                recipe.folder = .fixed(path: output.path); recipe.subfolder = ""
                recipe.format = format; recipe.existing = .overwrite; recipe.outputSize = .longEdge(1600)
                let context = NamingRule.Context(originalName: "sample-\(index)", filmStock: session.params.filmStock,
                    printStock: session.params.printStock, pixelSize: session.decoded?.pixelSize ?? .zero, counter: 1, date: Date())
                let result = try await Exporter.export(session: session, recipe: recipe, context: context, sessionID: sid)
                guard case .wrote(let files, _, _) = result else { return XCTFail("Real sample skipped") }
                let file = try XCTUnwrap(files.first)
                let source = try XCTUnwrap(CGImageSourceCreateWithURL(file as CFURL, nil))
                let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any])
                let tiff = props[kCGImagePropertyTIFFDictionary] as? [String:Any]
                XCTAssertEqual(tiff?["Make"] as? String, sample.make)
                XCTAssertEqual(tiff?["Model"] as? String, sample.model)
                let exif = try XCTUnwrap(props[kCGImagePropertyExifDictionary] as? [String:Any])
                XCTAssertEqual(exif["OffsetTimeOriginal"] as? String, sample.offset)
                XCTAssertEqual(exif["DateTimeOriginal"] as? String, sample.dateTime)
                XCTAssertEqual(exif["ISOSpeedRatings"] as? [Int], [sample.iso])
                XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 1600)
                XCTAssertEqual(props[kCGImagePropertyOrientation] as? Int, 1)
                XCTAssertEqual(props[kCGImagePropertyProfileName] as? String, "Display P3")
                if sample.hasGPS {
                    let gps = try XCTUnwrap(props[kCGImagePropertyGPSDictionary] as? [String:Any])
                    let inputMeta = try XCTUnwrap(CGImageSourceCreateWithURL(original as CFURL, nil))
                    let old = CGImageSourceCopyPropertiesAtIndex(inputMeta,0,nil) as! [CFString:Any]
                    var expected = old[kCGImagePropertyGPSDictionary] as! [String: Any]
                    let method = expected.removeValue(forKey: "ProcessingMethod") as? String
                    var comparable = gps
                    comparable.removeValue(forKey: "ProcessingMethod")
                    XCTAssertEqual(comparable as NSDictionary, expected as NSDictionary)
                    let metadata = try XCTUnwrap(CGImageSourceCopyMetadataAtIndex(source,0,nil))
                    XCTAssertEqual(CGImageMetadataCopyStringValueWithPath(metadata,nil,"fm:GPSProcessingMethod" as CFString) as String?, method?.trimmingCharacters(in: .controlCharacters))
                }
                print("METADATA VERIFIED \(sample.make) \(format) \(file.path)")
            }
            XCTAssertEqual(hash, SHA256.hash(data: try Data(contentsOf: original)), "Original file changed")
        }
    }
}
