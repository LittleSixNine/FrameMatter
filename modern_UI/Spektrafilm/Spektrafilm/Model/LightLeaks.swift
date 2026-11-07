// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
// Applies only to FrameMatter contributions; upstream notices are retained. See COPYRIGHT.txt.

import Foundation

enum LightLeakStyle: String, Codable, CaseIterable, Sendable {
    case rim, halo
    @MainActor var title: String {
        self == .rim ? L("Fine rim", zh: "贴孔细亮边") : L("Soft halo", zh: "孔外柔晕")
    }
}

struct LightLeakSettings: Codable, Equatable, Sendable {
    var active = false
    var perforationActive = true
    var wideActive = false
    var wideMaterial = WideLeakMaterial.warm11
    var wideStrength = 0.7
    var wideDepth = 0.28
    var wideScale = 1.2
    var wideSoftness = 0.0
    var wideDirection = WideLeakDirection.left
    var wideSeed = 1
    var wideFlip = WideLeakFlip.original
    var style = LightLeakStyle.rim
    var rimStrength = 0.0
    var rimCoverage = 0.0
    var rimSoftness = 0.0
    var rimSpread = 0.5
    var rimSeed = 1
    var haloStrength = 0.0
    var haloSpread = 0.5
    var haloSeed = 1

    var strength: Double {
        get { style == .rim ? rimStrength : haloStrength }
        set { if style == .rim { rimStrength = newValue } else { haloStrength = newValue } }
    }
    var spread: Double {
        get { style == .rim ? rimSpread : haloSpread }
        set { if style == .rim { rimSpread = newValue } else { haloSpread = newValue } }
    }
    var seed: Int {
        get { style == .rim ? rimSeed : haloSeed }
        set { if style == .rim { rimSeed = newValue } else { haloSeed = newValue } }
    }

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? d.active
        perforationActive = try c.decodeIfPresent(Bool.self, forKey: .perforationActive) ?? d.perforationActive
        wideActive = try c.decodeIfPresent(Bool.self, forKey: .wideActive) ?? d.wideActive
        wideMaterial = try c.decodeIfPresent(WideLeakMaterial.self, forKey: .wideMaterial) ?? d.wideMaterial
        wideStrength = try c.decodeIfPresent(Double.self, forKey: .wideStrength) ?? d.wideStrength
        wideDepth = try c.decodeIfPresent(Double.self, forKey: .wideDepth) ?? d.wideDepth
        wideScale = try c.decodeIfPresent(Double.self, forKey: .wideScale) ?? d.wideScale
        wideSoftness = try c.decodeIfPresent(Double.self, forKey: .wideSoftness) ?? d.wideSoftness
        wideDirection = try c.decodeIfPresent(WideLeakDirection.self, forKey: .wideDirection) ?? d.wideDirection
        wideSeed = try c.decodeIfPresent(Int.self, forKey: .wideSeed) ?? d.wideSeed
        wideFlip = try c.decodeIfPresent(WideLeakFlip.self, forKey: .wideFlip) ?? d.wideFlip
        style = try c.decodeIfPresent(LightLeakStyle.self, forKey: .style) ?? d.style
        rimStrength = try c.decodeIfPresent(Double.self, forKey: .rimStrength) ?? d.rimStrength
        rimCoverage = try c.decodeIfPresent(Double.self, forKey: .rimCoverage) ?? d.rimCoverage
        rimSoftness = try c.decodeIfPresent(Double.self, forKey: .rimSoftness) ?? d.rimSoftness
        rimSpread = try c.decodeIfPresent(Double.self, forKey: .rimSpread) ?? d.rimSpread
        rimSeed = try c.decodeIfPresent(Int.self, forKey: .rimSeed) ?? d.rimSeed
        haloStrength = try c.decodeIfPresent(Double.self, forKey: .haloStrength) ?? d.haloStrength
        haloSpread = try c.decodeIfPresent(Double.self, forKey: .haloSpread) ?? d.haloSpread
        haloSeed = try c.decodeIfPresent(Int.self, forKey: .haloSeed) ?? d.haloSeed
    }
    init(migrating old: ScratchSettings) {
        guard let migratedStyle = LightLeakStyle(rawValue: old.leakStyle.rawValue) else { return }
        style = migratedStyle
        active = old.active && old.leakStrength > 0
        strength = old.leakStrength
        spread = old.leakSpread
        seed = old.seed
        rimCoverage = old.leakCoverage
        rimSoftness = old.leakSoftness
    }
    mutating func randomizeWide() {
        let alternatives = wideMaterial.group.materials.filter { $0 != wideMaterial }
        if let material = alternatives.randomElement() { wideMaterial = material }
        if wideMaterial.isOnetake { wideFlip = WideLeakFlip.allCases.randomElement() ?? .original }
        else { wideDirection = WideLeakDirection.allCases.randomElement() ?? .left }
        let previous = wideSeed
        wideSeed = Int.random(in: ScratchSettings.seedRange)
        if wideSeed == previous { wideSeed = previous == ScratchSettings.seedRange.upperBound ? ScratchSettings.seedRange.lowerBound : previous + 1 }
    }

    func available(on edge: FilmEdgeSettings) -> Bool {
        edge.effective && [.f135, .f135Half, .f135FullWidth].contains(edge.format)
    }
    func wire(filmEdge: FilmEdgeSettings, digitalIntermediate: Bool = false) -> [(name: String, value: ParamValue, layer: ParamLayer)] {
        let on = active && perforationActive && available(on: filmEdge)
        var fields: [(name: String, value: ParamValue, layer: ParamLayer)] = [
            ("scratch_leak_enabled", .double(on ? 1 : 0), .shoot)
        ]
        if on {
            fields += [
            ("scratch_leak_strength", .double(strength.clamped(to: ScratchSettings.amountRange)), .shoot),
            ("scratch_leak_spread", .double(spread.clamped(to: ScratchSettings.amountRange)), .shoot),
            ("scratch_leak_coverage", .double(style == .rim ? rimCoverage.clamped(to: ScratchSettings.amountRange) : 0), .shoot),
            ("scratch_leak_softness", .double(style == .rim ? rimSoftness.clamped(to: ScratchSettings.amountRange) : 0), .shoot),
            ("scratch_leak_style", .string(style.rawValue), .shoot),
            ("scratch_leak_seed", .double(Double(seed.clamped(to: ScratchSettings.seedRange))), .shoot),
        ]
        }
        let wideOn = active && wideActive && !digitalIntermediate && wideMaterial.available
        fields.append(("wide_leak_active", .bool(wideOn), .print))
        if wideOn {
            fields += [
                ("wide_leak_texture", .string(wideMaterial.textureURL.path), .print),
                ("wide_leak_strength", .double(wideStrength.clamped(to: ScratchSettings.amountRange)), .print),
                ("wide_leak_depth", .double(wideDepth.clamped(to: ScratchSettings.amountRange)), .print),
                ("wide_leak_scale", .double(wideScale.clamped(to: 0.5...3.0)), .print),
                ("wide_leak_softness", .double(wideMaterial.isOnetake ? 0 : wideSoftness.clamped(to: ScratchSettings.amountRange)), .print),
                ("wide_leak_direction", .double(Double(wideDirection.rawValue)), .print),
                ("wide_leak_seed", .double(Double(wideSeed.clamped(to: ScratchSettings.seedRange))), .print),
                ("wide_leak_anchored", .bool(wideMaterial.isOnetake), .print),
                ("wide_leak_anchor_x", .double(wideMaterial.anchor.x), .print),
                ("wide_leak_anchor_y", .double(wideMaterial.anchor.y), .print),
                ("wide_leak_flip", .double(Double(wideFlip.rawValue)), .print),
            ]
        }
        return fields
    }
}
