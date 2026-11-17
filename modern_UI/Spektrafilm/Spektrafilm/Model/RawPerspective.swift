// SPDX-FileCopyrightText: 2026 Hanze Qiu (Keystone projection)
// SPDX-FileCopyrightText: 2026 LittleSixNine (FrameMatter integration)
// SPDX-License-Identifier: GPL-3.0-or-later
// Keystone math adapted from SpektraLab 2.2.0, commit 243d3a362a6443db34109a93b622230699596d68.

import CoreImage
import simd

/// RAW-only source correction, after decode and before any film/crop. No scene or border pixels downstream are warped.
struct RawPerspective: Codable, Equatable, Hashable, Sendable {
    var vertical: Double = 0
    var horizontal: Double = 0
    static let maxAngle: Double = 30
    var isNeutral: Bool { vertical == 0 && horizontal == 0 }

    func map(in size: CGSize) -> Keystone {
        Keystone.make(vertical: vertical.isFinite ? vertical : 0,
                      horizontal: horizontal.isFinite ? horizontal : 0, size: size)
    }

    func applying(to image: CIImage) throws -> CIImage {
        guard !isNeutral else { return image }
        let extent = image.extent.integral, size = extent.size
        let map = map(in: size)
        let source = image.transformed(by: .init(translationX: -extent.minX, y: -extent.minY))
        func up(_ p: CGPoint) -> CIVector { CIVector(x:p.x,y:size.height-p.y) }
        guard let filter = CIFilter(name:"CIPerspectiveTransform") else { throw Failure.unavailable }
        filter.setValue(source,forKey:kCIInputImageKey)
        filter.setValue(up(map.corrected(CGPoint(x:0,y:0))),forKey:"inputTopLeft")
        filter.setValue(up(map.corrected(CGPoint(x:size.width,y:0))),forKey:"inputTopRight")
        filter.setValue(up(map.corrected(CGPoint(x:size.width,y:size.height))),forKey:"inputBottomRight")
        filter.setValue(up(map.corrected(CGPoint(x:0,y:size.height))),forKey:"inputBottomLeft")
        guard let made = filter.outputImage else { throw Failure.unavailable }
        return made.clampedToExtent().cropped(to:CGRect(origin:.zero,size:size))
    }
    enum Failure: LocalizedError {
        case unavailable
        var errorDescription: String? { "RAW perspective correction could not be constructed." }
    }
}

struct Keystone: Equatable, Sendable {
    /// Source pixels → corrected pixels.
    var forward: simd_double3x3
    /// Corrected pixels → source pixels.
    var inverse: simd_double3x3
    /// How much the corrected frame is of the re-projected picture (≤ 1).
    var fill: Double

    static let identity = Keystone(forward: matrix_identity_double3x3, inverse: matrix_identity_double3x3, fill: 1)
    var isIdentity: Bool { fill == 1 && forward == matrix_identity_double3x3 }

    static func apply(_ m: simd_double3x3, _ p: CGPoint) -> CGPoint {
        let v = m * SIMD3<Double>(Double(p.x), Double(p.y), 1)
        let w = abs(v.z) < 1e-12 ? 1e-12 : v.z
        return CGPoint(x: v.x / w, y: v.y / w)
    }

    func corrected(_ source: CGPoint) -> CGPoint { Self.apply(forward, source) }
    func source(_ corrected: CGPoint) -> CGPoint { Self.apply(inverse, corrected) }

    /// The keystone of a frame `size` pixels large, `vertical` and
    /// `horizontal` degrees of the camera's turn.
    static func make(vertical: Double, horizontal: Double, size: CGSize) -> Keystone {
        guard vertical != 0 || horizontal != 0 else { return .identity }
        let w = max(Double(size.width), 1), h = max(Double(size.height), 1)
        let f = max(w, h), cx = w / 2, cy = h / 2
        let k = simd_double3x3(rows: [SIMD3(f, 0, cx), SIMD3(0, f, cy), SIMD3(0, 0, 1)])
        let a = vertical.clamped(to: -RawPerspective.maxAngle...RawPerspective.maxAngle) * .pi / 180
        let b = horizontal.clamped(to: -RawPerspective.maxAngle...RawPerspective.maxAngle) * .pi / 180
        let rx = simd_double3x3(rows: [SIMD3(1, 0, 0), SIMD3(0, cos(a), -sin(a)), SIMD3(0, sin(a), cos(a))])
        let ry = simd_double3x3(rows: [SIMD3(cos(b), 0, sin(b)), SIMD3(0, 1, 0), SIMD3(-sin(b), 0, cos(b))])
        let turned = k * rx * ry * k.inverse
        // The centre back to the centre.
        let c = apply(turned, CGPoint(x: cx, y: cy))
        let back = simd_double3x3(rows: [SIMD3(1, 0, cx - Double(c.x)), SIMD3(0, 1, cy - Double(c.y)), SIMD3(0, 0, 1)])
        let projected = back * turned
        let toSource = projected.inverse
        // The largest frame about the centre with picture under all four corners.
        func inside(_ s: Double) -> Bool {
            for (x, y) in [(0.0, 0.0), (w, 0.0), (w, h), (0.0, h)] {
                let v = toSource * SIMD3(cx + s * (x - cx), cy + s * (y - cy), 1)
                guard v.z > 1e-9 else { return false }
                let px = v.x / v.z, py = v.y / v.z
                if px < -1e-6 || py < -1e-6 || px > w + 1e-6 || py > h + 1e-6 { return false }
            }
            return true
        }
        var fill = 1.0
        if !inside(1) {
            var lo = 0.0, hi = 1.0
            for _ in 0..<48 {
                let mid = (lo + hi) / 2
                if inside(mid) { lo = mid } else { hi = mid }
            }
            fill = max(lo, 1e-3)
        }
        let unscale = simd_double3x3(rows: [SIMD3(1 / fill, 0, cx - cx / fill), SIMD3(0, 1 / fill, cy - cy / fill), SIMD3(0, 0, 1)])
        let forward = unscale * projected
        return Keystone(forward: forward, inverse: forward.inverse, fill: fill)
    }
}
