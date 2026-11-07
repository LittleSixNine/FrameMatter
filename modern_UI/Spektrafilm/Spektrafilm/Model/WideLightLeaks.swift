// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
// Applies only to FrameMatter contributions; upstream notices are retained. See COPYRIGHT.txt.

import Foundation

enum WideLeakGroup: CaseIterable, Sendable {
    case warm, colour, neutral, bands, spots, onetake
    @MainActor var title: String {
        switch self {
        case .warm: L("Warm edges", zh: "暖色边缘")
        case .colour: L("Colour mist and edges", zh: "彩色光雾与边缘")
        case .neutral: L("Neutral edges", zh: "无色边缘")
        case .bands: L("Light bands", zh: "光带")
        case .spots: L("Local spots", zh: "局部光斑")
        case .onetake: L("Onetake · local", zh: "一闪 · 本地素材")
        }
    }
    var materials: [WideLeakMaterial] { WideLeakMaterial.allCases.filter { $0.group == self } }
}

enum WideLeakMaterial: String, Codable, CaseIterable, Sendable {
    case warm11 = "11", warm14 = "14", warm28 = "28", warm36 = "36", warm42 = "42", spot17 = "17"
    case streak34 = "34", neutral39 = "39", cyan15 = "15", violet23 = "23"
    case edge01 = "01", edge02 = "02", edge03 = "03", edge04 = "04", edge05 = "05", edge06 = "06", edge07 = "07", edge09 = "09"
    case edge10 = "10", edge12 = "12", edge13 = "13", edge16 = "16", edge18 = "18", edge19 = "19", edge20 = "20", edge22 = "22"
    case edge24 = "24", edge26 = "26", edge27 = "27", edge29 = "29", edge31 = "31", edge32 = "32", mist38 = "38", edge41 = "41"
    case pair40 = "40-pair", warm40 = "40-warm", cool40 = "40-cool"
    case onetake020 = "onetake_020_v1", onetake035 = "onetake_035_v1", onetake040 = "onetake_040_v1", onetake060 = "onetake_060_v1"
    var group: WideLeakGroup {
        switch self {
        case .spot17: .spots
        case .cyan15, .violet23, .edge10, .mist38, .edge41: .colour
        case .neutral39, .edge16, .edge22, .edge26, .edge29: .neutral
        case .streak34, .edge24, .pair40, .warm40, .cool40: .bands
        case .onetake020, .onetake035, .onetake040, .onetake060: .onetake
        default: .warm
        }
    }
    var isOnetake: Bool { group == .onetake }
    var anchor: (x: Double, y: Double) {
        switch self {
        case .onetake020: (0.27, 0.5)
        case .onetake035: (0.38, 0.5)
        case .onetake040: (1, 0.5)
        case .onetake060: (0.5, 1)
        default: (0.5, 0.5)
        }
    }
    var usesIntrusion: Bool {
        switch self {
        case .spot17, .streak34, .cyan15, .violet23, .edge24, .mist38, .pair40, .warm40, .cool40: false
        default: !isOnetake
        }
    }
    @MainActor var title: String {
        switch self {
        case .spot17: L("Spot 17", zh: "光斑 17")
        case .streak34: L("Streak 34", zh: "橙色窄光带 34")
        case .neutral39: L("Neutral 39", zh: "无色柔光 39")
        case .cyan15: L("Cyan mist 15", zh: "青绿光雾 15")
        case .violet23: L("Violet mist 23", zh: "蓝紫光雾 23")
        case .edge10: L("Cool/warm 10", zh: "冷暖分段 10")
        case .edge12: L("Purple/gold 12", zh: "紫橙分段 12")
        case .edge16: L("Hard edge 16", zh: "干净硬边 16")
        case .edge22: L("Fine edge 22", zh: "丝状细边 22")
        case .edge24: L("Cool line 24", zh: "冷白窄边 24")
        case .edge26: L("Wave edge 26", zh: "波浪边缘 26")
        case .edge29: L("Feather 29", zh: "羽状白边 29")
        case .mist38: L("Green mist 38", zh: "浅绿光雾 38")
        case .edge41: L("Violet arc 41", zh: "粉紫弧边 41")
        case .pair40: L("Dual band 40", zh: "冷暖双带 40")
        case .warm40: L("Warm band 40", zh: "橙色光带 40")
        case .cool40: L("Cool line 40", zh: "冷色细线 40")
        case .onetake020: L("Pink edge 020", zh: "粉红边缘 020")
        case .onetake035: L("Red mist 035", zh: "宽红光雾 035")
        case .onetake040: L("Glow/spot 040", zh: "红边光斑 040")
        case .onetake060: L("Soft red 060", zh: "红紫柔雾 060")
        default: L("Warm \(rawValue)", zh: "暖色 \(rawValue)")
        }
    }
    var textureURL: URL {
        EngineClient.defaultResources().appendingPathComponent("local_light_leaks/\(rawValue).spkleak")
    }
    var available: Bool { FileManager.default.fileExists(atPath: textureURL.path) }
}

enum WideLeakFlip: Int, Codable, CaseIterable, Sendable {
    case original, horizontal, vertical, both
    @MainActor var title: String {
        switch self {
        case .original: L("Original", zh: "原始")
        case .horizontal: L("Horizontal", zh: "左右翻转")
        case .vertical: L("Vertical", zh: "上下翻转")
        case .both: L("Both axes", zh: "双向翻转")
        }
    }
}

enum WideLeakDirection: Int, Codable, CaseIterable, Sendable {
    case left, right, top, bottom
    @MainActor var title: String {
        switch self {
        case .left: L("Left", zh: "左侧")
        case .right: L("Right", zh: "右侧")
        case .top: L("Top", zh: "上方")
        case .bottom: L("Bottom", zh: "下方")
        }
    }
}
