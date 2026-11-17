import XCTest
import CoreImage

@MainActor
final class OpticalEffectsTests: XCTestCase {
    func testDormantEffectsKeepTheExistingPrintAndImage() throws {
        var p = FilmParams.default
        let original = Session.printStamp(p)
        p.diffusion.strength = 0.9
        p.doubleExposure.path = "/missing/photo.tif"
        XCTAssertEqual(Session.printStamp(p), original)
        let image = CIImage(color: CIColor(red: 0.2, green: 0.3, blue: 0.4))
            .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 12))
        XCTAssertTrue(try p.doubleExposure.compose(image) === image)
        p.doubleExposure.active = true
        XCTAssertThrowsError(try p.doubleExposure.compose(image))
        XCTAssertNotEqual(Session.printStamp(p), original)
    }

    func testDoubleExposureAddsLinearLightAndKeepsTheBaseExtent() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("double-check-" + UUID().uuidString + ".tif")
        defer { try? FileManager.default.removeItem(at: url) }
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.linearSRGB))
        let context = CIContext(options: [.workingColorSpace: space, .workingFormat: CIFormat.RGBAf])
        let second = CIImage(color: try XCTUnwrap(CIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1, colorSpace: space)))
            .cropped(to: CGRect(x: 0, y: 0, width: 24, height: 32))
        try context.writeTIFFRepresentation(of: second, to: url, format: .RGBAf, colorSpace: space)
        let base = CIImage(color: try XCTUnwrap(CIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1, colorSpace: space)))
            .cropped(to: CGRect(x: 0, y: 0, width: 32, height: 24))
        var settings = DoubleExposureSettings()
        settings.path = url.path
        settings.active = true
        settings.turns = 1
        settings.flipped = true
        settings.scale = 1.5
        let output = try settings.compose(base)
        XCTAssertEqual(output.extent, base.extent)
        var pixel = [Float](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 16,
                       bounds: CGRect(x: 16, y: 12, width: 1, height: 1), format: .RGBAf, colorSpace: space)
        for channel in 0..<3 { XCTAssertEqual(pixel[channel], 0.4, accuracy: 0.03) }
    }

    func testCineFiledChoiceAndEffectsSurviveSaving() throws {
        var p = FilmParams.default
        p.filmEdge.active = true
        p.filmEdge.format = .super8
        p.filmEdge.view = .filed
        p.diffusion.active = true
        p.diffusion.family = "cinebloom"
        XCTAssertEqual(p.fullDelta["overscan_mode"], .string("filed"))
        XCTAssertEqual(p.fullDelta["diffusion_filter_family"], .string("cinebloom"))
        XCTAssertEqual(try JSONDecoder().decode(FilmParams.self, from: JSONEncoder().encode(p)), p)
    }
}
