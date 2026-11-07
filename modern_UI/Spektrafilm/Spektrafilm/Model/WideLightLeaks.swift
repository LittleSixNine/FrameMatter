import Foundation

enum WideLeakMaterial: String, Codable, CaseIterable, Sendable {
    case warm11 = "11", warm14 = "14", warm28 = "28", warm36 = "36", warm42 = "42", spot17 = "17"
    @MainActor var title: String {
        self == .spot17 ? L("Spot 17", zh: "光斑 17") : L("Warm \(rawValue)", zh: "暖色 \(rawValue)")
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
