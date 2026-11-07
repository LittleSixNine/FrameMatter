// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
// Applies only to FrameMatter contributions; upstream notices are retained. See COPYRIGHT.txt.

import Foundation

enum WideLeakGroup: CaseIterable, Sendable {
    case fineEdges, wideEdges, mist, neutralEdges, bands, spots
    @MainActor var title: String {
        switch self {
        case .fineEdges: L("Fine edge leaks", zh: "细边漏光")
        case .wideEdges: L("Wide edge leaks", zh: "宽边漏光")
        case .mist: L("Coloured mist", zh: "彩色光雾")
        case .neutralEdges: L("White edges", zh: "白色边缘")
        case .bands: L("Light streaks", zh: "线状光带")
        case .spots: L("Local glow", zh: "局部光斑")
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
        case .warm11, .warm14, .warm28, .warm36, .warm42, .edge18, .edge19,
             .edge20, .edge27, .edge32, .edge41, .onetake020: .wideEdges
        case .cyan15, .violet23, .edge10, .mist38, .onetake035, .onetake040, .onetake060: .mist
        case .neutral39, .edge16, .edge22, .edge26, .edge29: .neutralEdges
        case .streak34, .edge24, .pair40, .warm40, .cool40: .bands
        case .spot17: .spots
        default: .fineEdges
        }
    }
    // Anchoring follows the texture format, independently of its visual menu category.
    var isOnetake: Bool {
        switch self {
        case .onetake020, .onetake035, .onetake040, .onetake060: true
        default: false
        }
    }
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
        case .warm11: L("Amber haze edge", zh: "琥珀雾边")
        case .warm14: L("Red-orange gradient", zh: "橙红渐变")
        case .warm28: L("Pale gold gradient", zh: "浅金渐边")
        case .warm36: L("Layered red-orange edge", zh: "橙红叠层")
        case .warm42: L("Golden wash", zh: "金黄漫边")
        case .spot17: L("Blue-white flare", zh: "蓝白光斑")
        case .streak34: L("Soft orange streak", zh: "橙色柔光带")
        case .neutral39: L("Diffuse white glow", zh: "白色漫光")
        case .cyan15: L("Turquoise haze", zh: "青绿光雾")
        case .violet23: L("Indigo haze", zh: "蓝紫光雾")
        case .edge01: L("Fiery orange fine edge", zh: "火橙细边")
        case .edge02: L("Soft red-orange edge", zh: "橙红柔边")
        case .edge03: L("Rose-red fine edge", zh: "玫红细边")
        case .edge04: L("Bright orange edge", zh: "橙色亮边")
        case .edge05: L("Violet-red frayed edge", zh: "紫红毛边")
        case .edge06: L("Pale orange fade", zh: "浅橙渐边")
        case .edge07: L("Golden fine edge", zh: "金黄细边")
        case .edge09: L("Sharp red-orange edge", zh: "橙红硬边")
        case .edge10: L("Cyan and gold haze", zh: "青金光雾")
        case .edge12: L("Violet-gold fine edge", zh: "紫金细边")
        case .edge13: L("Soft orange-white edge", zh: "橙白柔边")
        case .edge16: L("Clean white edge", zh: "平直白边")
        case .edge18: L("Rust-orange glow", zh: "锈橙漫边")
        case .edge19: L("Gold-violet transition", zh: "金紫过渡")
        case .edge20: L("Honey-gold glow", zh: "蜜金光晕")
        case .edge22: L("Wispy white edge", zh: "丝状白边")
        case .edge24: L("Icy white filament", zh: "冷白细线")
        case .edge26: L("Wavy white edge", zh: "波浪白边")
        case .edge27: L("Lemon-yellow glow", zh: "柠黄亮边")
        case .edge29: L("Feathered white edge", zh: "羽状白边")
        case .edge31: L("Vermilion fine edge", zh: "朱红细边")
        case .edge32: L("Soft yellow wash", zh: "柔黄漫边")
        case .mist38: L("Mottled green haze", zh: "斑驳绿雾")
        case .edge41: L("Lavender curved edge", zh: "淡紫弧边")
        case .pair40: L("Orange-cyan twin streaks", zh: "橙青双光带")
        case .warm40: L("Fiery orange streak", zh: "火橙光带")
        case .cool40: L("Cyan filament", zh: "青色细线")
        case .onetake020: L("Pink wash edge", zh: "粉红宽边")
        case .onetake035: L("Diffuse red haze", zh: "红色弥散光雾")
        case .onetake040: L("Coral glow", zh: "珊瑚红光晕")
        case .onetake060: L("Rose and violet haze", zh: "玫红紫雾")
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
