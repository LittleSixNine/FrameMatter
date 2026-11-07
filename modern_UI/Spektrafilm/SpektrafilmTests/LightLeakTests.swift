// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
// Applies only to FrameMatter contributions; upstream notices are retained. See COPYRIGHT.txt.

import AppKit
import SwiftUI
import XCTest

@MainActor
final class LightLeakTests: XCTestCase {
    func testIndependentSwitchSeedsAndPerStylePersistence() throws {
        var p = FilmParams.default
        p.filmEdge.active = true
        p.lightLeaks.active = true
        p.lightLeaks.rimStrength = 0.75
        p.lightLeaks.rimCoverage = 0.8
        p.lightLeaks.rimSoftness = 0.4
        p.lightLeaks.rimSpread = 0.3
        p.lightLeaks.rimSeed = 17
        XCTAssertFalse(p.scratches.active)
        XCTAssertEqual(p.fullDelta["scratch_leak_enabled"], .double(1))
        XCTAssertEqual(p.fullDelta["scratch_active"], .bool(false))
        XCTAssertEqual(p.fullDelta["scratch_leak_strength"], .double(0.75))
        let rim = p.lightLeaks
        p.lightLeaks.style = .halo
        p.lightLeaks.strength = 0.45
        p.lightLeaks.spread = 0.9
        p.lightLeaks.seed = 29
        XCTAssertEqual(p.fullDelta["scratch_leak_style"], .string("halo"))
        XCTAssertEqual(p.fullDelta["scratch_leak_seed"], .double(29))
        XCTAssertEqual(p.fullDelta["scratch_leak_coverage"], .double(0))
        XCTAssertEqual(p.fullDelta["scratch_leak_softness"], .double(0))
        p.lightLeaks.style = .rim
        XCTAssertEqual(p.lightLeaks.strength, rim.strength)
        XCTAssertEqual(p.lightLeaks.spread, rim.spread)
        XCTAssertEqual(p.lightLeaks.seed, rim.seed)
        XCTAssertEqual(p.lightLeaks.rimCoverage, rim.rimCoverage)
        XCTAssertEqual(p.lightLeaks.rimSoftness, rim.rimSoftness)
        XCTAssertEqual(try JSONDecoder().decode(FilmParams.self, from: JSONEncoder().encode(p)), p)
        let before = p
        p.lightLeaks.seed = 31
        XCTAssertEqual(p.scratches, before.scratches)
        XCTAssertEqual(p.lightLeaks.haloSeed, 29)
        XCTAssertEqual(p.delta(from: before).layers, [.shoot])
        p.scratches.active = true
        p.lightLeaks.active = false
        XCTAssertEqual(p.fullDelta["scratch_leak_enabled"], .double(0))
        XCTAssertEqual(p.fullDelta["scratch_active"], .bool(true))
        p.lightLeaks.active = true
        p.filmEdge.active = false
        XCTAssertEqual(p.fullDelta["scratch_leak_enabled"], .double(0))
    }

    func testLegacyMigrationAndModernDocumentPrecedence() throws {
        for style in [PerforationAppearance.rim, .halo] {
            var old = FilmParams.default
            old.scratches.active = true
            old.scratches.leakStyle = style
            old.scratches.leakStrength = 0.65
            old.scratches.leakSpread = 0.85
            old.scratches.leakCoverage = 0.7
            old.scratches.leakSoftness = 0.55
            old.scratches.seed = 12345
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
            json.removeValue(forKey: "lightLeaks")
            let migrated = try JSONDecoder().decode(FilmParams.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertTrue(migrated.lightLeaks.active)
            XCTAssertEqual(migrated.lightLeaks.style.rawValue, style.rawValue)
            XCTAssertEqual(migrated.lightLeaks.strength, 0.65)
            XCTAssertEqual(migrated.lightLeaks.spread, 0.85)
            XCTAssertEqual(migrated.lightLeaks.seed, 12345)
            XCTAssertEqual(migrated.lightLeaks.rimCoverage, 0.7)
            XCTAssertEqual(migrated.lightLeaks.rimSoftness, 0.55)
            XCTAssertEqual(migrated.scratches, old.scratches)
            // A saved independent off switch must never be re-enabled from stale legacy fields.
            let modern = try JSONDecoder().decode(FilmParams.self, from: JSONEncoder().encode(old))
            XCTAssertFalse(modern.lightLeaks.active)
            json["scratches"] = [:]
            let empty = try JSONDecoder().decode(FilmParams.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertFalse(empty.lightLeaks.active)
        }
    }

    func testBothCardsRenderInBothLanguages() throws {
        let key = Session.uiKey + "section." + LightLeakSection.key
        let old = UserDefaults.standard.object(forKey: key)
        let language = Localization.shared.language
        defer { UserDefaults.standard.set(old, forKey: key); Localization.shared.language = language }
        UserDefaults.standard.set(true, forKey: key)
        let session = Session()
        for lang in [LanguageSetting.english, .simplifiedChinese] {
            Localization.shared.language = lang
            for style in LightLeakStyle.allCases {
                var p = session.params
                p.filmEdge.active = true
                p.lightLeaks.active = true
                p.lightLeaks.style = style
                p.lightLeaks.strength = 0.65
                p.lightLeaks.rimCoverage = 0.75
                p.lightLeaks.rimSoftness = 0.5
                session.params = p
                let host = NSHostingController(rootView: LightLeakSection(session: session).background(Theme.card))
                let size = host.sizeThatFits(in: CGSize(width: Theme.Metric.leftPanelWidth, height: 2000))
                XCTAssertLessThanOrEqual(size.width, Theme.Metric.leftPanelWidth + 0.5)
                XCTAssertGreaterThan(size.height, Theme.Metric.headerHeight)
                if let directory = ProcessInfo.processInfo.environment["SPK_RENDER_DIR"] {
                    let view = host.view
                    view.appearance = NSAppearance(named: .darkAqua)
                    view.frame = CGRect(origin: .zero, size: size)
                    view.layoutSubtreeIfNeeded()
                    let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                    view.cacheDisplay(in: view.bounds, to: rep)
                    let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                    try png.write(to: URL(fileURLWithPath: directory).appending(path: "light-leaks-\(style.rawValue)-\(lang).png"))
                }
            }
        }
    }
}
