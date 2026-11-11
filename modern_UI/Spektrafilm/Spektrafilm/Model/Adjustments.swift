//  Adjustments.swift — Layer 2: adjustments to the print output, client-side.
//
//  These operate on the encoded print output the way a scan of a print is
//  adjusted afterwards (frontend SPEC §3.1). They live entirely in the Metal
//  shader (`Shaders.metal`, `layer2`) and cost < 1 ms; nothing here reaches
//  the service. Order of operations is fixed and matches the shader:
//
//      white balance → exposure/contrast/brightness → highlights/shadows
//      → black/white point → saturation → colour balance → vibrance → HSL
//      → channel mixer → curves → local masks → vignette
//
//  Zero is "nothing applied" for every field, so a fresh image reads as the
//  pure simulation, and `enabled = false` bypasses the whole layer.

import Foundation
import simd

struct ColorZone: Codable, Equatable, Sendable {
    /// Hue angle in degrees, saturation 0…1 (wheel radius), luminance −1…1.
    var hue: Double = 0
    var saturation: Double = 0
    var luminance: Double = 0
    var isNeutral: Bool { saturation == 0 && luminance == 0 }

    /// The RGB offset this zone applies, in the shader's units.
    var rgbOffset: SIMD3<Float> {
        let h = hue * .pi / 180
        // Hue on the wheel → unit RGB direction (0° = red, 120° = green, 240° = blue).
        let r = cos(h), g = cos(h - 2 * .pi / 3), b = cos(h + 2 * .pi / 3)
        let s = Float(saturation) * 0.25
        return SIMD3<Float>(Float(r), Float(g), Float(b)) * s
    }
}

struct ColorBalance: Codable, Equatable, Sendable {
    var master = ColorZone()
    var shadows = ColorZone()
    var midtones = ColorZone()
    var highlights = ColorZone()
    var isNeutral: Bool { master.isNeutral && shadows.isNeutral && midtones.isNeutral && highlights.isNeutral }
}

struct Vignette: Codable, Equatable, Sendable {
    var amount: Double = 0      // −100…100, negative darkens the corners
    var midpoint: Double = 50   // 0…100, radius at which falloff starts
    var isNeutral: Bool { amount == 0 }
}

/// Eight cyclic hue anchors in the encoded ProPhoto working space; zero bypasses HSL.
struct HSLBand: Codable, Equatable, Sendable {
    var hue: Double = 0             // degrees, −30…30
    var saturation: Double = 0      // percent, −100…100
    var lightness: Double = 0       // percent, −100…100
    var isNeutral: Bool { hue == 0 && saturation == 0 && lightness == 0 }
    var uniform: SIMD4<Float> {
        func finite(_ x: Double, _ r: ClosedRange<Double>) -> Float { Float(x.isFinite ? min(max(x, r.lowerBound), r.upperBound) : 0) }
        return SIMD4(finite(hue, -30...30) / 360, finite(saturation, -100...100) / 100,
                     finite(lightness, -100...100) / 100, 0)
    }
}

struct HSLAdjustments: Codable, Equatable, Sendable {
    var red = HSLBand(), orange = HSLBand(), yellow = HSLBand(), green = HSLBand()
    var aqua = HSLBand(), blue = HSLBand(), purple = HSLBand(), magenta = HSLBand()
    static var keys: [WritableKeyPath<HSLAdjustments, HSLBand>] {
        [\.red, \.orange, \.yellow, \.green, \.aqua, \.blue, \.purple, \.magenta]
    }
    static let names = ["red", "orange", "yellow", "green", "aqua", "blue", "purple", "magenta"]
    var isNeutral: Bool { Self.keys.allSatisfy { self[keyPath: $0].isNeutral } }
    var uniforms: HSLUniforms {
        var u = HSLUniforms()
        u.hslRed = red.uniform; u.hslOrange = orange.uniform
        u.hslYellow = yellow.uniform; u.hslGreen = green.uniform
        u.hslAqua = aqua.uniform; u.hslBlue = blue.uniform
        u.hslPurple = purple.uniform; u.hslMagenta = magenta.uniform
        u.active = isNeutral ? 0 : 1
        return u
    }

}

// Mixer math adapted from SpektraLab 2.2.0 (Hanze Qiu), GPL-3.0-or-later.
struct MixerRow: Codable, Equatable, Sendable {
    /// The keys as they are written: renaming a property must not move its key.
    enum CodingKeys: String, CodingKey { case red = "red", green = "green", blue = "blue" }
    var red: Double = 0
    var green: Double = 0
    var blue: Double = 0
    var isNeutral: Bool { red == 0 && green == 0 && blue == 0 }

    init(red: Double = 0, green: Double = 0, blue: Double = 0) { self.red = red; self.green = green; self.blue = blue }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        red = try c.decodeIfPresent(Double.self, forKey: .red) ?? 0
        green = try c.decodeIfPresent(Double.self, forKey: .green) ?? 0
        blue = try c.decodeIfPresent(Double.self, forKey: .blue) ?? 0
    }

    subscript(input: ChannelMixer.Channel) -> Double {
        get {
            switch input {
            case .red: red
            case .green: green
            case .blue: blue
            }
        }
        set {
            let v = min(max(newValue, ChannelMixer.range.lowerBound), ChannelMixer.range.upperBound)
            switch input {
            case .red: red = v
            case .green: green = v
            case .blue: blue = v
            }
        }
    }
}

/// 通道: the channel mixer. Each output channel is a sum of the three inputs.
struct ChannelMixer: Codable, Equatable, Sendable {
    /// The keys as they are written: renaming a property must not move its key.
    enum CodingKeys: String, CodingKey { case red = "red", green = "green", blue = "blue" }
    var red = MixerRow()
    var green = MixerRow()
    var blue = MixerRow()

    static let range: ClosedRange<Double> = -100...100

    enum Channel: String, CaseIterable, Codable, Sendable, Identifiable {
        case red, green, blue
        var id: String { rawValue }
        @MainActor var title: String {
            switch self {
            case .red: L("Red", zh: "红")
            case .green: L("Green", zh: "绿")
            case .blue: L("Blue", zh: "蓝")
            }
        }
        /// Its place in a pixel: red 0, green 1, blue 2.
        var index: Int { Channel.allCases.firstIndex(of: self) ?? 0 }
    }

    var isNeutral: Bool { red.isNeutral && green.isNeutral && blue.isNeutral }

    subscript(output: Channel) -> MixerRow {
        get {
            switch output {
            case .red: red
            case .green: green
            case .blue: blue
            }
        }
        set {
            switch output {
            case .red: red = newValue
            case .green: green = newValue
            case .blue: blue = newValue
            }
        }
    }

    /// An output channel's row of the matrix the shader multiplies by: the
    /// identity's row, plus the offsets.
    func row(_ output: Channel) -> SIMD3<Float> {
        func bounded(_ x: Double) -> Float { Float(x.isFinite ? min(max(x, -100), 100) : 0) / 100 }
        var r = SIMD3<Float>(bounded(self[output].red), bounded(self[output].green), bounded(self[output].blue))
        r[output.index] += 1
        return r
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        red = try c.decodeIfPresent(MixerRow.self, forKey: .red) ?? MixerRow()
        green = try c.decodeIfPresent(MixerRow.self, forKey: .green) ?? MixerRow()
        blue = try c.decodeIfPresent(MixerRow.self, forKey: .blue) ?? MixerRow()
    }
}

struct Adjustments: Codable, Equatable, Sendable {
    var enabled: Bool = true
    // White balance, post-print (Capture One's model, but as an offset).
    var temperature: Double = 0    // −100…100, blue ↔ amber
    var tint: Double = 0           // −100…100, green ↔ magenta
    // Exposure group (Capture One's four).
    var exposure: Double = 0       // stops, −3…3
    var contrast: Double = 0       // −50…50
    var brightness: Double = 0     // −50…50
    var saturation: Double = 0     // −100…100
    // Tone-region recovery.
    var highlights: Double = 0     // −100…100
    var shadows: Double = 0        // −100…100
    var blackPoint: Double = 0     // 0…50  (percent of range lifted to black)
    var whitePoint: Double = 0     // 0…50
    var curves = CurveSet()
    var colorBalance = ColorBalance()
    var vignette = Vignette()
    var hsl = HSLAdjustments()
    var vibrance: Double = 0 // −100…100
    var channelMixer = ChannelMixer()

    init(enabled: Bool = true) { self.enabled = enabled }
    private enum CodingKeys: String, CodingKey { case enabled, temperature, tint, exposure, contrast, brightness, saturation, highlights, shadows, blackPoint, whitePoint, curves, colorBalance, vignette, hsl, vibrance, channelMixer }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        temperature = try c.decode(Double.self, forKey: .temperature)
        tint = try c.decode(Double.self, forKey: .tint)
        exposure = try c.decode(Double.self, forKey: .exposure)
        contrast = try c.decode(Double.self, forKey: .contrast)
        brightness = try c.decode(Double.self, forKey: .brightness)
        saturation = try c.decode(Double.self, forKey: .saturation)
        highlights = try c.decode(Double.self, forKey: .highlights)
        shadows = try c.decode(Double.self, forKey: .shadows)
        blackPoint = try c.decode(Double.self, forKey: .blackPoint)
        whitePoint = try c.decode(Double.self, forKey: .whitePoint)
        curves = try c.decode(CurveSet.self, forKey: .curves)
        colorBalance = try c.decode(ColorBalance.self, forKey: .colorBalance)
        vignette = try c.decode(Vignette.self, forKey: .vignette)
        hsl = try c.decodeIfPresent(HSLAdjustments.self, forKey: .hsl) ?? HSLAdjustments()
        vibrance = try c.decodeIfPresent(Double.self, forKey: .vibrance) ?? 0
        channelMixer = try c.decodeIfPresent(ChannelMixer.self, forKey: .channelMixer) ?? ChannelMixer()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(temperature, forKey: .temperature)
        try c.encode(tint, forKey: .tint)
        try c.encode(exposure, forKey: .exposure)
        try c.encode(contrast, forKey: .contrast)
        try c.encode(brightness, forKey: .brightness)
        try c.encode(saturation, forKey: .saturation)
        try c.encode(highlights, forKey: .highlights)
        try c.encode(shadows, forKey: .shadows)
        try c.encode(blackPoint, forKey: .blackPoint)
        try c.encode(whitePoint, forKey: .whitePoint)
        try c.encode(curves, forKey: .curves)
        try c.encode(colorBalance, forKey: .colorBalance)
        try c.encode(vignette, forKey: .vignette)
        try c.encode(hsl, forKey: .hsl)
        if vibrance != 0 { try c.encode(vibrance, forKey: .vibrance) }
        if !channelMixer.isNeutral { try c.encode(channelMixer, forKey: .channelMixer) }
    }

    static let `default` = Adjustments()
    var isNeutral: Bool { self == Adjustments(enabled: enabled) }
    var colorUniforms: HSLUniforms {
        var u = hsl.uniforms
        u.vibrance = Float(vibrance.isFinite ? min(max(vibrance, -100), 100) : 0) / 100
        u.mixerActive = channelMixer.isNeutral ? 0 : 1
        u.mixR = SIMD4(channelMixer.row(.red), 0)
        u.mixG = SIMD4(channelMixer.row(.green), 0)
        u.mixB = SIMD4(channelMixer.row(.blue), 0)
        return u
    }

    /// The per-frame uniform block the shader reads. Computed on the CPU once
    /// per change, not per pixel.
    var uniforms: Layer2Uniforms {
        // The tone block is `Layer2Uniforms.tone` — the *same* function every
        // mask uses (`Model/Mask.swift`). Temperature and tint become channel
        // gains there, ±100 → roughly ±0.18 on the opposing channels, which
        // is the visual range of a scan white-balance correction rather than
        // a scene one. Sharing it is what makes "+1 stop" mean one stop
        // whether the slider was the global one or a mask's.
        var u = Layer2Uniforms.tone(temperature: temperature, tint: tint, exposure: exposure,
                                    contrast: contrast, brightness: brightness, saturation: saturation,
                                    highlights: highlights, shadows: shadows,
                                    blackPoint: blackPoint, whitePoint: whitePoint)
        u.enabled = enabled ? 1 : 0
        u.cbMaster = colorBalance.master.rgbOffset
        u.cbShadows = colorBalance.shadows.rgbOffset
        u.cbMidtones = colorBalance.midtones.rgbOffset
        u.cbHighlights = colorBalance.highlights.rgbOffset
        u.cbLum = SIMD4<Float>(Float(colorBalance.master.luminance), Float(colorBalance.shadows.luminance),
                               Float(colorBalance.midtones.luminance), Float(colorBalance.highlights.luminance)) * 0.25
        u.vignetteAmount = Float(vignette.amount) / 100
        u.vignetteMidpoint = Float(vignette.midpoint) / 100
        u.curvesActive = curves.isIdentity ? 0 : 1
        return u
    }
}

/// Must match `Layer2Uniforms` in Shaders.metal field for field and in order.
struct Layer2Uniforms: Sendable {
    var wbGain = SIMD3<Float>(repeating: 1)
    var exposureGain: Float = 1
    var cbMaster = SIMD3<Float>(repeating: 0)
    var contrast: Float = 0
    var cbShadows = SIMD3<Float>(repeating: 0)
    var brightness: Float = 0
    var cbMidtones = SIMD3<Float>(repeating: 0)
    var saturation: Float = 1
    var cbHighlights = SIMD3<Float>(repeating: 0)
    var highlights: Float = 0
    var cbLum = SIMD4<Float>(repeating: 0)
    var shadows: Float = 0
    var blackPoint: Float = 0
    var whitePoint: Float = 0
    var vignetteAmount: Float = 0
    var vignetteMidpoint: Float = 0.5
    /// Encoded mid-grey (linear 0.18) in the working space — RFC-018 D1's
    /// pivot. See `Layer2Uniforms.tone` for the two constants and why the
    /// default is the ROMM one.
    var midGrey: Float = Layer2Uniforms.proPhotoMidGrey
    var curvesActive: UInt32 = 0
    var enabled: UInt32 = 1
    /// RFC-028: read the source through the Cineon → ProPhoto table first.
    /// Set by the renderer for a Digital Intermediate, never by an edit.
    var inputDecode: UInt32 = 0


    /// `pow(0.18, 1/1.8)` — mid-grey through ROMM γ1.8, the working space's
    /// own curve since RFC-018. The number `layer2Tone` pivots on.
    ///
    /// Kept beside `srgbMidGrey` rather than inlined because the *pair* is the
    /// decision: D1 says the pivot follows the encoding, so a future move to
    /// another working space is a swap of which constant is the default, not a
    /// hunt for literals.
    static let proPhotoMidGrey: Float = 0.3857
    /// `1.055·0.18^(1/2.4) − 0.055` — the same through an sRGB-like curve,
    /// which is what Display P3 has and what this code pivoted on by accident
    /// until RFC-018.
    static let srgbMidGrey: Float = 0.4614
}

/// Global colour tools share this block so local mask uniforms retain their existing size.
struct HSLUniforms: Sendable {
    var hslRed = SIMD4<Float>(repeating: 0), hslOrange = SIMD4<Float>(repeating: 0)
    var hslYellow = SIMD4<Float>(repeating: 0), hslGreen = SIMD4<Float>(repeating: 0)
    var hslAqua = SIMD4<Float>(repeating: 0), hslBlue = SIMD4<Float>(repeating: 0)
    var hslPurple = SIMD4<Float>(repeating: 0), hslMagenta = SIMD4<Float>(repeating: 0)
    var active: UInt32 = 0
    var vibrance: Float = 0
    var mixerActive: UInt32 = 0
    var padding: UInt32 = 0
    var mixR = SIMD4<Float>(1, 0, 0, 0), mixG = SIMD4<Float>(0, 1, 0, 0), mixB = SIMD4<Float>(0, 0, 1, 0)
}
