import Foundation

struct ScratchSettings: Codable, Equatable, Sendable {
    var active = false
    var longLines = 0.4
    var shortScuffs = 0.25
    var strength = 0.35
    var seed = 1
    static let amountRange = 0.0...1.0
    static let seedRange = 1...Int(Int32.max)

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? d.active
        longLines = try c.decodeIfPresent(Double.self, forKey: .longLines) ?? d.longLines
        shortScuffs = try c.decodeIfPresent(Double.self, forKey: .shortScuffs) ?? d.shortScuffs
        strength = try c.decodeIfPresent(Double.self, forKey: .strength) ?? d.strength
        seed = try c.decodeIfPresent(Int.self, forKey: .seed) ?? d.seed
    }
    func available(on edge: FilmEdgeSettings) -> Bool {
        edge.effective && [.f135, .f135Half].contains(edge.format)
    }
    func wire(filmEdge: FilmEdgeSettings) -> [(name: String, value: ParamValue, layer: ParamLayer)] {
        let on = active && available(on: filmEdge)
        var fields: [(name: String, value: ParamValue, layer: ParamLayer)] = [("scratch_active", .bool(on), .shoot)]
        guard on else { return fields }
        fields += [
            ("scratch_long_lines", .double(longLines.clamped(to: Self.amountRange)), .shoot),
            ("scratch_short_scuffs", .double(shortScuffs.clamped(to: Self.amountRange)), .shoot),
            ("scratch_strength", .double(strength.clamped(to: Self.amountRange)), .shoot),
            ("scratch_seed", .double(Double(seed.clamped(to: Self.seedRange))), .shoot),
        ]
        return fields
    }
}
