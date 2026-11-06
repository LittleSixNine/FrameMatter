import Foundation

struct ScratchSettings: Codable, Equatable, Sendable {
    var active = false
    var longLines = 0.4
    var strength = 0.35
    var edgeMarks = 0.35
    var leakStrength = 0.0
    var leakSpread = 0.5
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
            ("scratch_leak_strength", .double(leakStrength.clamped(to: Self.amountRange)), .shoot),
            ("scratch_leak_spread", .double(leakSpread.clamped(to: Self.amountRange)), .shoot),
            ("scratch_seed", .double(Double(seed.clamped(to: Self.seedRange))), .shoot),
        ]
        return fields
    }
}
