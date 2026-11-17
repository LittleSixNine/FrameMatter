import Foundation
import CoreImage
import CoreGraphics

struct DiffusionSettings: Codable, Equatable, Sendable {
    var active = false
    var family = "black_pro_mist"
    var strength = 0.5
    var scale = 1.0

    var wire: [(name: String, value: ParamValue, layer: ParamLayer)] {
        var fields: [(name: String, value: ParamValue, layer: ParamLayer)] = [
            ("diffusion_filter_active", .bool(active), .shoot)
        ]
        if active {
            fields += [
                ("diffusion_filter_family", .string(family), .shoot),
                ("diffusion_filter_strength", .double(strength.clamped(to: 0...1)), .shoot),
                ("diffusion_filter_spatial_scale", .double(scale.clamped(to: 0.25...4)), .shoot)
            ]
        }
        return fields
    }
}

struct DoubleExposureSettings: Codable, Equatable, Sendable {
    var active = false
    var path = ""
    var balance = 0.5
    var scale = 1.0
    var x = 0.0
    var y = 0.0
    var turns = 0
    var flipped = false

    // Upstream RFC-047/048 adds two linear exposures before film development.
    // shortcut: the combined image is metered as a whole; port per-exposure metering when adding double-exposure projects.
    func compose(_ base: CIImage) throws -> CIImage {
        guard active, !path.isEmpty else { return base }
        let decoded = try ImageDecoder.decode(URL(fileURLWithPath: path), settings: DecodeSettings())
        var top = decoded.linear
        let target = base.extent
        top = top.oriented(forExifOrientation: [1, 6, 3, 8][((turns % 4) + 4) % 4])
        if flipped { top = top.transformed(by: CGAffineTransform(scaleX: -1, y: 1)) }
        let extent = top.extent
        top = top.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        let fit = max(target.width / extent.width, target.height / extent.height) * scale.clamped(to: 1...4)
        top = top.transformed(by: CGAffineTransform(scaleX: fit, y: fit))
        let slackX = max(0, top.extent.width - target.width)
        let slackY = max(0, top.extent.height - target.height)
        top = top.transformed(by: CGAffineTransform(
            translationX: target.minX - slackX * (x.clamped(to: -1...1) + 1) / 2,
            y: target.minY - slackY * (y.clamped(to: -1...1) + 1) / 2)).cropped(to: target)
        func gained(_ image: CIImage, _ gain: Double) -> CIImage {
            image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0)
            ])
        }
        let share = balance.clamped(to: 0.1...0.9)
        return gained(top, share).applyingFilter("CIAdditionCompositing",
            parameters: [kCIInputBackgroundImageKey: gained(base, 1 - share)]).cropped(to: target)
    }
}
