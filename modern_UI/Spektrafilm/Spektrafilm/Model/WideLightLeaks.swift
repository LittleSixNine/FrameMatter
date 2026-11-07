import Foundation

enum WideLeakMaterial: String, Codable, CaseIterable, Sendable {
    case warm11 = "11", warm14 = "14", warm28 = "28", warm36 = "36", warm42 = "42", spot17 = "17"
    case streak34 = "34", neutral39 = "39", cyan15 = "15", violet23 = "23"
    var usesIntrusion: Bool {
        switch self {
        case .spot17, .streak34, .cyan15, .violet23: false
        default: true
        }
    }
    @MainActor var title: String {
        switch self {
        case .spot17: L("Spot 17", zh: "光斑 17")
        case .streak34: L("Streak 34", zh: "橙色窄光带 34")
        case .neutral39: L("Neutral 39", zh: "无色柔光 39")
        case .cyan15: L("Cyan mist 15", zh: "青绿色光雾 15")
        case .violet23: L("Violet mist 23", zh: "蓝紫色光雾 23")
        default: L("Warm \(rawValue)", zh: "暖色 \(rawValue)")
        }
    }
    var textureURL: URL {
        EngineClient.defaultResources().appendingPathComponent("local_light_leaks/\(rawValue).spkleak")
    }
    var available: Bool { FileManager.default.fileExists(atPath: textureURL.path) }
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
