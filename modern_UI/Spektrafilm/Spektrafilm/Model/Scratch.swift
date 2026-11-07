import Foundation

enum PerforationAppearance: String, Codable, CaseIterable, Sendable {
    case rim, halo, shadow, band, streak, burn

    @MainActor var title: String {
        switch self {
        case .rim: L("Fine rim", zh: "贴孔细亮边")
        case .halo: L("Soft halo", zh: "孔外柔软色晕")
        case .shadow: L("Dark transition", zh: "孔旁暗色过渡")
        case .band: L("Continuous band", zh: "整排连续色带")
        case .streak: L("Independent streak", zh: "独立条纹")
        case .burn: L("Edge burn", zh: "强烈片边曝光")
        }
    }
}

struct ScratchSettings: Codable, Equatable, Sendable {
    var active = false
    var longLines = 0.4
    var strength = 0.35
    var edgeMarks = 0.35
    var leakStrength = 0.0
    var leakSpread = 0.5
    var leakSoftness = 0.0
    var leakCoverage = 0.0
    var leakStyle = PerforationAppearance.rim
    var dustAmount = 0.0
    var dustSize = 0.5
    var dustStrength = 0.5
    var dustFullFrame = false
    var dustFiberRatio = 0.25
    var seed = 1
    static let amountRange = 0.0...1.0
    static let seedRange = 1...Int(Int32.max)

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? d.active
        longLines = try c.decodeIfPresent(Double.self, forKey: .longLines) ?? d.longLines
        strength = try c.decodeIfPresent(Double.self, forKey: .strength) ?? d.strength
        edgeMarks = try c.decodeIfPresent(Double.self, forKey: .edgeMarks) ?? d.edgeMarks
        leakStrength = try c.decodeIfPresent(Double.self, forKey: .leakStrength) ?? d.leakStrength
        leakSpread = try c.decodeIfPresent(Double.self, forKey: .leakSpread) ?? d.leakSpread
        leakSoftness = try c.decodeIfPresent(Double.self, forKey: .leakSoftness) ?? d.leakSoftness
        leakCoverage = try c.decodeIfPresent(Double.self, forKey: .leakCoverage) ?? d.leakCoverage
        leakStyle = try c.decodeIfPresent(PerforationAppearance.self, forKey: .leakStyle) ?? d.leakStyle
        dustAmount = try c.decodeIfPresent(Double.self, forKey: .dustAmount) ?? d.dustAmount
        dustSize = try c.decodeIfPresent(Double.self, forKey: .dustSize) ?? d.dustSize
        dustStrength = try c.decodeIfPresent(Double.self, forKey: .dustStrength) ?? d.dustStrength
        dustFiberRatio = try c.decodeIfPresent(Double.self, forKey: .dustFiberRatio) ?? d.dustFiberRatio
        dustFullFrame = try c.decodeIfPresent(Bool.self, forKey: .dustFullFrame) ?? d.dustFullFrame
        seed = try c.decodeIfPresent(Int.self, forKey: .seed) ?? d.seed
    }
    func available(on edge: FilmEdgeSettings) -> Bool {
        edge.effective && [.f135, .f135Half, .f135FullWidth].contains(edge.format)
    }
    func wire(filmEdge: FilmEdgeSettings) -> [(name: String, value: ParamValue, layer: ParamLayer)] {
        let on = active && available(on: filmEdge)
        var fields: [(name: String, value: ParamValue, layer: ParamLayer)] = [("scratch_active", .bool(on), .shoot)]
        guard on else { return fields }
        fields += [
            ("scratch_long_lines", .double(longLines.clamped(to: Self.amountRange)), .shoot),
            ("scratch_strength", .double(strength.clamped(to: Self.amountRange)), .shoot),
            ("scratch_edge_marks", .double(edgeMarks.clamped(to: Self.amountRange)), .shoot),
            ("scratch_dust_amount", .double(dustAmount.clamped(to: Self.amountRange)), .shoot),
            ("scratch_dust_size", .double(dustSize.clamped(to: Self.amountRange)), .shoot),
            ("scratch_dust_strength", .double(dustStrength.clamped(to: Self.amountRange)), .shoot),
            ("scratch_dust_fiber_ratio", .double(dustFiberRatio.clamped(to: Self.amountRange)), .shoot),
            ("scratch_dust_full_frame", .bool(dustFullFrame), .shoot),
            ("scratch_seed", .double(Double(seed.clamped(to: Self.seedRange))), .shoot),
        ]
        return fields
    }
}
