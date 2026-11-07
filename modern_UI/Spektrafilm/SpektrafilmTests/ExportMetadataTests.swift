// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
// Applies only to FrameMatter contributions; upstream notices are retained. See COPYRIGHT.txt.

import XCTest
import ImageIO
import CoreGraphics

@MainActor
final class ExportMetadataTests: XCTestCase {
    private func image() throws -> CGImage {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8,
            bytesPerRow: 128, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }
    private func properties(_ url: URL) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }
    func testCameraGPSAndTimeOffsetsSurviveWithNewGeometryAndICC() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.jpg")
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(source as CFURL, "public.jpeg" as CFString, 1, nil))
        let sourceProps: [CFString: Any] = [
            kCGImagePropertyOrientation: 6,
            kCGImageDestinationMergeMetadata: true,
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "SONY", kCGImagePropertyTIFFModel: "Camera Test",
                                           kCGImagePropertyTIFFArtist: "作者", kCGImagePropertyTIFFCopyright: "测试版权"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2025:10:05 16:31:27",
                "OffsetTimeOriginal": "+09:00", kCGImagePropertyExifISOSpeedRatings: [100],
                kCGImagePropertyExifExposureTime: 1.0/2500, kCGImagePropertyExifLensModel: "Test Lens"],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 31.25, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 121.5, kCGImagePropertyGPSLongitudeRef: "E", kCGImagePropertyGPSAltitude: 32.9],
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCKeywords: ["测试", "旅行"]]
        ]
        let xmp = CGImageMetadataCreateMutable()
        CGImageMetadataRegisterNamespaceForPrefix(xmp, "http://ns.adobe.com/xap/1.0/" as CFString, "xmp" as CFString, nil)
        CGImageMetadataSetValueWithPath(xmp, nil, "xmp:Rating" as CFString, 4 as CFNumber)
        CGImageDestinationAddImageAndMetadata(dest, try image(), xmp, sourceProps as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        let metadata = ExportMetadata(source: source)
        for format in [ExportFormat.jpeg, .tiff, .png] {
            let output = directory.appendingPathComponent("output.\(format.ext)")
            try Exporter.write(image(), to: output, format: format, sourceMetadata: metadata)
            let p = try properties(output)
            let tiff = p[kCGImagePropertyTIFFDictionary] as? [String: Any]
            XCTAssertEqual(tiff?["Make"] as? String, "SONY")
            XCTAssertEqual(tiff?["Model"] as? String, "Camera Test")
            XCTAssertEqual(tiff?["Artist"] as? String, "作者")
            XCTAssertEqual(tiff?["Copyright"] as? String, "测试版权")
            let iptc = p[kCGImagePropertyIPTCDictionary] as? [String: Any]
            XCTAssertEqual(iptc?["Keywords"] as? [String], ["测试", "旅行"])
            let gps = try XCTUnwrap(p[kCGImagePropertyGPSDictionary] as? [String: Any])
            XCTAssertEqual(gps["Latitude"] as? Double, 31.25)
            XCTAssertEqual(gps["Longitude"] as? Double, 121.5)
            let exif = try XCTUnwrap(p[kCGImagePropertyExifDictionary] as? [String: Any])
            XCTAssertEqual(exif["OffsetTimeOriginal"] as? String, "+09:00")
            XCTAssertEqual(exif["DateTimeOriginal"] as? String, "2025:10:05 16:31:27")
            XCTAssertEqual(exif["PixelXDimension"] as? Int, 32)
            XCTAssertEqual(exif["PixelYDimension"] as? Int, 24)
            XCTAssertEqual(p[kCGImagePropertyOrientation] as? Int, 1)
            XCTAssertEqual(p[kCGImagePropertyProfileName] as? String, "Display P3")
            let readback = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
            let savedXMP = try XCTUnwrap(CGImageSourceCopyMetadataAtIndex(readback,0,nil))
            XCTAssertEqual(CGImageMetadataCopyStringValueWithPath(savedXMP,nil,"xmp:Rating" as CFString) as String?, "4")
        }
    }

    func testDensityWriterDoesNotInventADisplayProfile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("density-\(UUID().uuidString).tif")
        defer { try? FileManager.default.removeItem(at: file) }
        let context = try XCTUnwrap(CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 16,
            bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        try Exporter.write(try XCTUnwrap(context.makeImage()), to: file, format: .tiff,
                           sourceMetadata: ExportMetadata(source: nil, fallbackEXIF: [kCGImagePropertyExifColorSpace: 1]))
        let p = try properties(file)
        XCTAssertNil(p[kCGImagePropertyProfileName])
        XCTAssertEqual((p[kCGImagePropertyExifDictionary] as? [String: Any])?["ColorSpace"] as? Int, 65535)
    }

    func testBoundedTimeOffsetReaderForTIFFARWAndJPEG() {
        for little in [false, true] {
            var d = Data(little ? [73,73,42,0,8,0,0,0] : [77,77,0,42,0,0,0,8])
            func append(_ value: Int, _ bytes: Int) {
                for i in 0..<bytes { d.append(UInt8((value >> ((little ? i : bytes-i-1)*8)) & 255)) }
            }
            append(1,2); append(0x8769,2);append(4,2);append(1,4);append(26,4);append(0,4)
            append(3,2)
            for i in 0..<3 { append(0x9010+i,2);append(2,2);append(7,4);append(68+i*7,4) }
            append(0,4)
            for _ in 0..<3 {d.append(contentsOf: Array("+09:00\0".utf8))}
            XCTAssertEqual(ExifTimeOffsets.read(d).count, 3)
            XCTAssertEqual(ExifTimeOffsets.read(d)["OffsetTimeOriginal" as CFString], "+09:00")
            let size=d.count+8
            let jpeg=Data([255,216,255,225,UInt8(size>>8),UInt8(size&255),69,120,105,102,0,0])+d+Data([255,217])
            XCTAssertEqual(ExifTimeOffsets.read(jpeg).count, 3)
            for length in [0,7,20,67,73] { XCTAssertTrue(ExifTimeOffsets.read(Data(d.prefix(length))).isEmpty) }
            var invalid=d; invalid[68]=65
            XCTAssertNil(ExifTimeOffsets.read(invalid)["OffsetTime" as CFString])
        }
    }
}
