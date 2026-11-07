// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
// Applies only to FrameMatter contributions; upstream notices are retained. See COPYRIGHT.txt.

import XCTest
import SwiftUI
import AppKit

@MainActor
final class AgingTextureTests: XCTestCase {
    func testSavedControlsIndependentAndPrintOnly() throws {
        var p = FilmParams.default
        let before = p
        XCTAssertEqual(p.fullDelta["aging_active"], .bool(false))
        p.agingTextures.active = true
        p.agingTextures.material = .dust04
        p.agingTextures.strength = 0.8
        p.agingTextures.rotation = 3
        p.agingTextures.flip = .horizontal
        XCTAssertFalse(p.filmEdge.active)
        XCTAssertEqual(p.fullDelta["aging_active"], .bool(true))
        XCTAssertEqual(p.fullDelta["aging_rotation"], .double(3))
        XCTAssertEqual(p.fullDelta["aging_flip"], .double(1))
        XCTAssertTrue(p.fullDelta["aging_texture"]?.stringValue?.hasSuffix("dust04.spkleak") == true)
        XCTAssertEqual(p.delta(from: before).layers, [.print])
        XCTAssertEqual(p.scratches, before.scratches)
        XCTAssertEqual(p.lightLeaks, before.lightLeaks)
        XCTAssertEqual(try JSONDecoder().decode(FilmParams.self, from: JSONEncoder().encode(p)), p)
        p.digitalIntermediate = true
        XCTAssertEqual(p.fullDelta["aging_active"], .bool(false))
        XCTAssertTrue(p.agingTextures.active)
    }

    func testOldSidecarsDefaultOffAndBoundsClamp() throws {
        let p = FilmParams.default
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
        json.removeValue(forKey: "agingTextures")
        let old = try JSONDecoder().decode(FilmParams.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.agingTextures, AgingTextureSettings())
        var bad = AgingTextureSettings()
        bad.active = true; bad.strength = 3; bad.rotation = -1
        let wire = Dictionary(uniqueKeysWithValues: bad.wire(digitalIntermediate: false).map { ($0.name, $0.value) })
        XCTAssertEqual(wire["aging_strength"], .double(1))
        XCTAssertEqual(wire["aging_rotation"], .double(0))
    }

    func testCardFitsBothLanguages() throws {
        let key = Session.uiKey + "section." + AgingTextureSection.key
        let old = UserDefaults.standard.object(forKey: key)
        let language = Localization.shared.language
        defer { UserDefaults.standard.set(old, forKey: key); Localization.shared.language = language }
        UserDefaults.standard.set(true, forKey: key)
        let session = Session()
        var p = session.params; p.agingTextures.active = true; session.params = p
        for lang in [LanguageSetting.english, .simplifiedChinese] {
            Localization.shared.language = lang
            let host = NSHostingController(rootView: AgingTextureSection(session: session).background(Theme.card))
            let size = host.sizeThatFits(in: CGSize(width: Theme.Metric.leftPanelWidth, height: 2000))
            XCTAssertLessThanOrEqual(size.width, Theme.Metric.leftPanelWidth + 0.5)
            XCTAssertGreaterThan(size.height, Theme.Metric.headerHeight)
            if let directory = ProcessInfo.processInfo.environment["SPK_RENDER_DIR"] {
                let view = host.view
                view.appearance = NSAppearance(named: .darkAqua)
                view.frame = CGRect(origin: .zero, size: size); view.layoutSubtreeIfNeeded()
                let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: rep)
                try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to:
                    URL(fileURLWithPath: directory).appendingPathComponent("aging-\(lang).png"))
            }
        }
    }
}
