// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
import CoreImage
import Foundation
import Vision

/// Derived source evidence, never a user edit or a saved/clipboard parameter.
enum FrameFaceDetector {
    static let identity = "vision-face-v3-tile-v1"
    struct Box: Codable, Equatable, Sendable {
        let x: Double, y: Double, width: Double, height: Double, confidence: Double
        init(_ observation: VNFaceObservation, roi: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) {
            let b = observation.boundingBox
            x = roi.minX + b.minX * roi.width
            y = roi.minY + b.minY * roi.height
            width = b.width * roi.width
            height = b.height * roi.height
            confidence = Double(observation.confidence)
        }
    }
    struct Evidence: Encodable, Sendable {
        let version = 1
        let detector = FrameFaceDetector.identity
        let width: Int, height: Int
        let faces: [Box]
    }
    enum Failure: Error, LocalizedError {
        case image, crop
        var errorDescription: String? { "Could not prepare face detection evidence for adaptive metering." }
    }

    static func sourceSize(_ extent: CGRect) throws -> (width: Int, height: Int) {
        guard [extent.minX, extent.minY, extent.width, extent.height, extent.maxX, extent.maxY].allSatisfy(\.isFinite),
              extent.width >= 1, extent.height >= 1,
              extent.width < Double(Int.max), extent.height < Double(Int.max) else { throw Failure.image }
        let width = Int(extent.width), height = Int(extent.height)
        guard width <= Int.max / height / 16 else { throw Failure.image }
        return (width, height)
    }

    static func tileRects(width: Int, height: Int) -> [CGRect] {
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        return [0.0, 0.4].flatMap { y in
            [0.0, 0.4].map { x in
                CGRect(x: x * Double(width), y: (1 - y - 0.6) * Double(height),
                       width: 0.6 * Double(width), height: 0.6 * Double(height)).integral.intersection(full)
            }
        }
    }
    static func normalizedROI(_ rect: CGRect, width: Int, height: Int) -> CGRect {
        CGRect(x: rect.minX / Double(width), y: 1 - rect.maxY / Double(height),
               width: rect.width / Double(width), height: rect.height / Double(height))
    }

    static func detect(_ cg: CGImage, checkpoint: () throws -> Void = {}) throws -> [Box] {
        func request(_ image: CGImage, roi: CGRect) throws -> [Box] {
            try checkpoint()
            let request = VNDetectFaceRectanglesRequest()
            request.revision = 3
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
            try checkpoint()
            return (request.results ?? []).map { Box($0, roi: roi) }
        }
        let whole = try request(cg, roi: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard whole.isEmpty else { return whole }
        var faces: [Box] = []
        for rect in tileRects(width: cg.width, height: cg.height) {
            guard let crop = cg.cropping(to: rect) else { throw Failure.crop }
            faces += try request(crop, roi: normalizedROI(rect, width: cg.width, height: cg.height))
        }
        return faces
    }

    static func evidence(display: CIImage, frameExtent: CGRect? = nil,
                         checkpoint: () throws -> Void = {}) throws -> String {
        try checkpoint()
        guard !display.extent.isInfinite, !display.extent.isEmpty else { throw Failure.image }
        let extent = display.extent.integral
        // The boxes are normalized. For a preview, report the resized engine
        // frame's dimensions while detecting faces on the full display decode.
        let source = try sourceSize(frameExtent?.integral ?? extent)
        let scale = min(1, 1600 / max(extent.width, extent.height))
        let width = Int((extent.width * scale).rounded()), height = Int((extent.height * scale).rounded())
        let preview = display.transformed(by: .init(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: .init(scaleX: Double(width) / extent.width, y: Double(height) / extent.height))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let cg = ImageDecoder.context.createCGImage(preview,
                  from: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBA8, colorSpace: space)
        else { throw Failure.image }
        let faces = try detect(cg, checkpoint: checkpoint)
        let data = try JSONEncoder().encode(Evidence(width: source.width, height: source.height, faces: faces))
        return String(decoding: data, as: UTF8.self)
    }
}
