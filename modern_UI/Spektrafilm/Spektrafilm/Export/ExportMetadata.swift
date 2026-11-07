// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
// Applies only to FrameMatter contributions; upstream notices are retained. See COPYRIGHT.txt.

// PhotoTrail metadata code provenance: license/PhotoTrail-Metadata-NOTICE.txt.

import Foundation
import ImageIO

/// Immutable source information; it never enters the pixel pipeline.
struct ExportMetadata: @unchecked Sendable {
    private let properties: [CFString: Any]
    private let metadata: CGImageMetadata?

    init(source: URL?, fallbackEXIF: [CFString: Any]? = nil) {
        let image = source.flatMap { CGImageSourceCreateWithURL($0 as CFURL, nil) }
        var props = image.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] } ?? [:]
        var exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? fallbackEXIF ?? [:]
        if let source {
            for (key, value) in ExifTimeOffsets.read(source) { exif[key] = value }
        }
        props[kCGImagePropertyExifDictionary] = exif
        properties = props
        metadata = image.flatMap { CGImageSourceCopyMetadataAtIndex($0, 0, nil) }
    }

    func output(width: Int, height: Int) -> (properties: [CFString: Any], xmp: CGImageMetadata) {
        let result = CGImageMetadataCreateMutable()
        // Copy descriptive XMP, never old processing instructions, dimensions or HDR references.
        if let metadata, let tags = CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag] {
            let descriptive: [String: Set<String>] = [
                "dc": ["creator", "rights", "description", "subject", "title"],
                "xmp": ["Rating", "Label", "CreateDate"],
                "exif": ["GPSProcessingMethod", "GPSAreaInformation"],
                "photoshop": ["AuthorsPosition", "CaptionWriter", "Category", "City", "Country", "Credit",
                              "DateCreated", "Headline", "Instructions", "Source", "State", "SupplementalCategories", "TransmissionReference", "Urgency"],
                "Iptc4xmpCore": ["CiAdrCity", "CiAdrCtry", "CiAdrExtadr", "CiAdrPcode", "CiAdrRegion",
                                 "CiEmailWork", "CiTelWork", "CiUrlWork", "CountryCode", "IntellectualGenre", "Location", "Scene", "SubjectCode", "CreatorContactInfo"]
            ]
            for tag in tags {
                guard let prefix = CGImageMetadataTagCopyPrefix(tag) as String?,
                      let name = CGImageMetadataTagCopyName(tag) as String?,
                      descriptive[prefix]?.contains(name) == true,
                      let namespace = CGImageMetadataTagCopyNamespace(tag) else { continue }
                CGImageMetadataRegisterNamespaceForPrefix(result, namespace, prefix as CFString, nil)
                if prefix == "exif", let value = CGImageMetadataTagCopyValue(tag) as? String {
                    CGImageMetadataSetValueWithPath(result, nil, "\(prefix):\(name)" as CFString,
                        value.trimmingCharacters(in: .controlCharacters) as CFString)
                } else {
                    CGImageMetadataSetTagWithPath(result, nil, "\(prefix):\(name)" as CFString, tag)
                }
            }
        }
        // ImageIO drops these standard EXIF undefined fields even when supplied in GPS.
        // Keep a readable source value in XMP rather than silently losing it.
        if let gps = properties[kCGImagePropertyGPSDictionary] as? [String: Any] {
            for name in ["ProcessingMethod", "AreaInformation"] {
                if let value = gps[name] as? String {
                    CGImageMetadataRegisterNamespaceForPrefix(result, "urn:framematter:source-metadata:1.0" as CFString, "fm" as CFString, nil)
                    CGImageMetadataSetValueWithPath(result, nil, "fm:GPS\(name)" as CFString,
                        value.trimmingCharacters(in: .controlCharacters) as CFString)
                }
            }
        }
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [String: Any], let software = tiff["Software"] as? String {
            CGImageMetadataRegisterNamespaceForPrefix(result, "urn:framematter:source-metadata:1.0" as CFString, "fm" as CFString, nil)
            CGImageMetadataSetValueWithPath(result, nil, "fm:SourceSoftware" as CFString, software as CFString)
        }
        let groups: [(CFString, Set<String>?)] = [
            (kCGImagePropertyTIFFDictionary, ["Make", "Model", "Artist", "Copyright", "ImageDescription", "DateTime"]),
            (kCGImagePropertyExifDictionary, nil), (kCGImagePropertyGPSDictionary, nil),
            (kCGImagePropertyIPTCDictionary, nil), (kCGImagePropertyExifAuxDictionary, nil)
        ]
        let omitted: Set<String> = ["CFAPattern", "ComponentsConfiguration", "CompressedBitsPerPixel", "ColorSpace",
                                    "PixelXDimension", "PixelYDimension", "MakerNote", "MakerNoteUnknownText"]
        var output: [CFString: Any] = [:]
        for (group, allowed) in groups {
            guard let entries = properties[group] as? [CFString: Any] else { continue }
            var kept: [CFString: Any] = [:]
            for (key, value) in entries {
                let name = key as String
                if let allowed, !allowed.contains(name) { continue }
                if group == kCGImagePropertyExifDictionary && omitted.contains(name) { continue }
                kept[key] = value
            }
            output[group] = kept
        }
        var exif = output[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        exif[kCGImagePropertyExifPixelXDimension] = width
        exif[kCGImagePropertyExifPixelYDimension] = height
        exif[kCGImagePropertyExifColorSpace] = 65535
        output[kCGImagePropertyExifDictionary] = exif
        output[kCGImagePropertyOrientation] = 1
        var tiff = output[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        tiff[kCGImagePropertyTIFFOrientation] = 1
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development"
        tiff[kCGImagePropertyTIFFSoftware] = "FrameMatter Build \(build)"
        output[kCGImagePropertyTIFFDictionary] = tiff
        return (output, result)
    }
}
/// Read only three standard ASCII EXIF offsets omitted by ImageIO on some ARWs.
/// JPEG APP1 and classic TIFF (including ARW) offsets are relative to their TIFF header.
enum ExifTimeOffsets {
    static func read(_ url: URL) -> [CFString: String] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [:] }
        return read(data)
    }
    static func read(_ data: Data) -> [CFString: String] {
        var start = 0, limit = data.count
        guard limit >= 8 else { return [:] }
        if data[0] == 0xff && data[1] == 0xd8 {
            var pos = 2, found = false
            while pos + 4 <= data.count {
                guard data[pos] == 0xff else { return [:] }
                let marker = data[pos + 1]
                if marker == 0xda || marker == 0xd9 { break }
                if marker == 0xff { pos += 1; continue }
                let size = Int(data[pos+2]) * 256 + Int(data[pos+3])
                guard size >= 2, size <= data.count - pos - 2 else { return [:] }
                if marker == 0xe1 && size >= 8 && data[(pos+4)..<(pos+10)].elementsEqual([69,120,105,102,0,0]) {
                    start = pos + 10; limit = pos + 2 + size; found = true; break
                }
                pos += size + 2
            }
            guard found else { return [:] }
        }
        guard start <= limit - 8 else { return [:] }
        let little = data[start] == 73 && data[start+1] == 73
        guard little || (data[start] == 77 && data[start+1] == 77) else { return [:] }
        func number(_ pos: Int, _ bytes: Int) -> Int? {
            guard pos >= start, pos <= limit - bytes else { return nil }
            var value = 0
            for i in 0..<bytes { value = value * 256 + Int(data[pos + (little ? bytes - i - 1 : i)]) }
            return value
        }
        guard number(start+2,2) == 42, let offset = number(start+4,4) else { return [:] }
        func entries(_ offset: Int) -> [Int] {
            guard offset >= 8, offset <= limit - start - 2 else { return [] }
            let base = start + offset
            guard let count = number(base,2), count <= 4096, count <= (limit - base - 2) / 12 else { return [] }
            return (0..<count).map { base + 2 + $0 * 12 }
        }
        guard let pointer = entries(offset).first(where: { number($0,2) == 0x8769 }),
              number(pointer+2,2) == 4, number(pointer+4,4) == 1,
              let exif = number(pointer+8,4) else { return [:] }
        let names: [Int: CFString] = [0x9010: "OffsetTime" as CFString, 0x9011: "OffsetTimeOriginal" as CFString,
                                    0x9012: "OffsetTimeDigitized" as CFString]
        var result: [CFString: String] = [:]
        for entry in entries(exif) {
            guard let tag = number(entry,2), let key = names[tag], number(entry+2,2) == 2,
                  number(entry+4,4) == 7, let relative = number(entry+8,4), relative <= limit - start - 7 else { continue }
            let p = start + relative
            let bytes = Array(data[p..<(p+7)])
            guard bytes[6] == 0, bytes[0] == 43 || bytes[0] == 45, bytes[3] == 58,
                  [1,2,4,5].allSatisfy({ bytes[$0] >= 48 && bytes[$0] <= 57 }),
                  (Int(bytes[1]-48)*10+Int(bytes[2]-48)) <= 23,
                  (Int(bytes[4]-48)*10+Int(bytes[5]-48)) <= 59 else { continue }
            result[key] = String(bytes: bytes.prefix(6), encoding: .ascii)
        }
        return result
    }
}
