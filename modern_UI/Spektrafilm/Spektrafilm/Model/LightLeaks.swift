import Foundation

enum LightLeakStyle: String, Codable, CaseIterable, Sendable {
    case rim, halo
    @MainActor var title: String {
        self == .rim ? L("Fine rim", zh: "贴孔细亮边") : L("Soft halo", zh: "孔外柔晕")
    }
}

struct LightLeakSettings: Codable, Equatable, Sendable {
    var active = false
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
    func available(on edge: FilmEdgeSettings) -> Bool {
        edge.effective && [.f135, .f135Half, .f135FullWidth].contains(edge.format)
    }
    func wire(filmEdge: FilmEdgeSettings) -> [(name: String, value: ParamValue, layer: ParamLayer)] {
        let on = active && available(on: filmEdge)
        var fields: [(name: String, value: ParamValue, layer: ParamLayer)] = [
            ("scratch_leak_enabled", .double(on ? 1 : 0), .shoot)
        ]
        guard on else { return fields }
        fields += [
            ("scratch_leak_strength", .double(strength.clamped(to: ScratchSettings.amountRange)), .shoot),
            ("scratch_leak_spread", .double(spread.clamped(to: ScratchSettings.amountRange)), .shoot),
            ("scratch_leak_coverage", .double(style == .rim ? rimCoverage.clamped(to: ScratchSettings.amountRange) : 0), .shoot),
            ("scratch_leak_softness", .double(style == .rim ? rimSoftness.clamped(to: ScratchSettings.amountRange) : 0), .shoot),
            ("scratch_leak_style", .string(style.rawValue), .shoot),
            ("scratch_leak_seed", .double(Double(seed.clamped(to: ScratchSettings.seedRange))), .shoot),
        ]
        return fields
    }
}
