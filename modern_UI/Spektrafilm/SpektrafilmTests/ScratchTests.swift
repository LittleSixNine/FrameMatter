import AppKit
import SwiftUI
import XCTest

@MainActor
final class ScratchTests: XCTestCase {
    func testOldEditsAndScratchPersistence() throws {
        let old = try JSONDecoder().decode(ScratchSettings.self, from: Data("{}".utf8))
        XCTAssertFalse(old.active)
        XCTAssertEqual(old.leakStrength, 0)
        XCTAssertEqual(old.leakSpread, 0.5)
        let discarded = try JSONDecoder().decode(ScratchSettings.self,
            from: Data(#"{"active":true,"longLines":0.7,"shortScuffs":1.0}"#.utf8))
        XCTAssertTrue(discarded.active)
        XCTAssertEqual(discarded.longLines, 0.7)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(discarded), as: UTF8.self).contains("shortScuffs"))
        XCTAssertEqual(FilmEdgeSettings().holes, .black)
        let white = try JSONDecoder().decode(FilmEdgeSettings.self, from: Data(#"{"holes":"white"}"#.utf8))
        XCTAssertEqual(white.holes, .white)
        var p = FilmParams.default
        p.filmEdge.active = true
        p.scratches.active = true
        p.scratches.longLines = 0.7
        p.scratches.edgeMarks = 0.6
        p.scratches.leakStrength = 0.45
        p.scratches.leakSpread = 0.7
        p.scratches.seed = 12345
        XCTAssertEqual(try JSONDecoder().decode(FilmParams.self, from: JSONEncoder().encode(p)), p)
        var encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
        encoded.removeValue(forKey: "scratches")
        let legacy = try JSONDecoder().decode(FilmParams.self, from: JSONSerialization.data(withJSONObject: encoded))
        XCTAssertFalse(legacy.scratches.active)
        XCTAssertEqual(p.fullDelta["scratch_active"], .bool(true))
        XCTAssertNil(p.fullDelta["scratch_short_scuffs"])
        XCTAssertEqual(p.fullDelta["scratch_leak_strength"], .double(0.45))
        XCTAssertEqual(p.fullDelta["scratch_leak_spread"], .double(0.7))
        XCTAssertEqual(p.fullDelta["scratch_edge_marks"], .double(0.6))
        let marksBefore = p
        p.scratches.edgeMarks = 0.9
        XCTAssertEqual(p.delta(from: marksBefore).layers, [.shoot])
        XCTAssertEqual(p.filmEdge, marksBefore.filmEdge)
        XCTAssertEqual(p.fullDelta["overscan_holes"], .string("black"))
        p.filmEdge.holes = .white
        XCTAssertEqual(p.fullDelta["overscan_holes"], .string("white"))
        let before = p
        p.scratches.seed = 54321
        XCTAssertEqual(p.delta(from: before).layers, [.shoot])
        XCTAssertEqual(p.filmEdge, before.filmEdge)
        p.scratches.active = false
        let off = p
        p.scratches.seed = 321
        XCTAssertTrue(p.delta(from: off).delta.isEmpty)
        p.scratches.active = true
        p.filmEdge.active = false
        XCTAssertEqual(p.fullDelta["scratch_active"], .bool(false))
        p.filmEdge.active = true
        for format in FilmEdgeFormat.allCases {
            p.filmEdge.format = format
            XCTAssertEqual(p.fullDelta["scratch_active"], .bool([.f135, .f135Half].contains(format)))
        }
    }

    func testScratchCardFitsAndRenders() {
        let key = Session.uiKey + "section." + ScratchSection.key
        let saved = UserDefaults.standard.object(forKey: key)
        let language = Localization.shared.language
        defer { UserDefaults.standard.set(saved, forKey: key); Localization.shared.language = language }
        UserDefaults.standard.set(true, forKey: key)
        let session = Session()
        var p = session.params
        p.filmEdge.active = true; p.scratches.active = true
        session.params = p
        for lang in [LanguageSetting.english, .simplifiedChinese] {
            Localization.shared.language = lang
            let host = NSHostingController(rootView: ScratchSection(session: session).background(Theme.card))
            let size = host.sizeThatFits(in: CGSize(width: Theme.Metric.leftPanelWidth, height: 2000))
            XCTAssertLessThanOrEqual(size.width, Theme.Metric.leftPanelWidth + 0.5)
            XCTAssertGreaterThan(size.height, Theme.Metric.headerHeight)
            if lang == .simplifiedChinese, let dir = ProcessInfo.processInfo.environment["SPK_RENDER_DIR"] {
                let view = host.view
                view.appearance = NSAppearance(named: .darkAqua)
                view.frame = CGRect(origin: .zero, size: size)
                view.layoutSubtreeIfNeeded()
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    if let png = rep.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: dir).appending(path: "scratch-card.png"))
                    }
                }
            }
        }
    }
}
