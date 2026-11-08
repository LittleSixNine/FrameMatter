// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
// Applies only to FrameMatter contributions; upstream notices are retained. See COPYRIGHT.txt.

import Foundation

enum AgingTextureMaterial: String, Codable, CaseIterable, Sendable {
    case dust01, dust02, dust03, dust04, dust05

    @MainActor var title: String {
        switch self {
        case .dust01: L("Aging 1", zh: "做旧 1")
        case .dust02: L("Aging 2", zh: "做旧 2")
        case .dust03: L("Aging 3", zh: "做旧 3")
        case .dust04: L("Aging 4", zh: "做旧 4")
        case .dust05: L("Aging 5", zh: "做旧 5")
        }
    }
    var assetName: String {
        switch self {
        case .dust01: "aging-001"
        case .dust02: "aging-002"
        case .dust03: "aging-003"
        case .dust04: "aging-004"
        case .dust05: "aging-005"
        }
    }
    var textureURL: URL {
        EngineClient.defaultResources().appendingPathComponent("textures/aging/\(assetName).spkleak")
    }
    var available: Bool { FileManager.default.fileExists(atPath: textureURL.path) }
}

struct AgingTextureSettings: Codable, Equatable, Sendable {
    var active = false
    var material = AgingTextureMaterial.dust01
    var strength = 0.5
    /// Clockwise quarter-turns after automatic portrait alignment.
    var rotation = 0
    var flip = WideLeakFlip.original

    func wire(digitalIntermediate: Bool) -> [(name: String, value: ParamValue, layer: ParamLayer)] {
        let on = active && !digitalIntermediate
        var fields: [(name: String, value: ParamValue, layer: ParamLayer)] = [("aging_active", .bool(on), .print)]
        if on {
            fields += [
                ("aging_texture", .string(material.textureURL.path), .print),
                ("aging_strength", .double(strength.clamped(to: 0...1)), .print),
                ("aging_rotation", .double(Double(rotation.clamped(to: 0...3))), .print),
                ("aging_flip", .double(Double(flip.rawValue)), .print),
            ]
        }
        return fields
    }
}
