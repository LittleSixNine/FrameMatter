// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
// Applies only to FrameMatter contributions; upstream notices are retained. See COPYRIGHT.txt.

import AppKit
import SwiftUI
import XCTest

@MainActor
final class WideLeakTests: XCTestCase {
    func testOlderLightSettingsDecodeWithWideLightOff() throws {
        var value = LightLeakSettings()
        value.active = true; value.style = .halo
        value.haloStrength = 0.7; value.haloSeed = 123
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        for key in Array(json.keys) where key.hasPrefix("wide") || key == "perforationActive" { json.removeValue(forKey: key) }
        let decoded = try JSONDecoder().decode(LightLeakSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(decoded.active)
        XCTAssertTrue(decoded.perforationActive)
        XCTAssertFalse(decoded.wideActive)
        XCTAssertEqual(decoded.haloStrength, 0.7)
        XCTAssertEqual(decoded.haloSeed, 123)
        XCTAssertEqual(decoded.wideMaterial, .warm11)
    }

    func testWideWireWithoutFilmEdgeAndPrintLayer() throws {
        guard WideLeakMaterial.warm11.available else { throw XCTSkip("private local textures not installed") }
        var p = FilmParams.default
        p.lightLeaks.active = true
        p.lightLeaks.perforationActive = false
        p.lightLeaks.wideActive = true
        let before = p
        p.lightLeaks.wideStrength = 1
        p.lightLeaks.wideDirection = .bottom
        p.lightLeaks.wideDepth = 0.5
        p.lightLeaks.wideSoftness = 0.7
        p.lightLeaks.wideSeed = 29
        XCTAssertFalse(p.filmEdge.active)
        XCTAssertEqual(p.fullDelta["scratch_leak_enabled"], .double(0))
        XCTAssertEqual(p.fullDelta["wide_leak_active"], .bool(true))
        XCTAssertEqual(p.fullDelta["wide_leak_texture"], .string(WideLeakMaterial.warm11.textureURL.path))
        XCTAssertEqual(p.fullDelta["wide_leak_strength"], .double(1))
        XCTAssertEqual(p.fullDelta["wide_leak_direction"], .double(3))
        XCTAssertEqual(p.delta(from: before).layers, [.print])
        XCTAssertEqual(try JSONDecoder().decode(FilmParams.self, from: JSONEncoder().encode(p)), p)
        p.filmEdge.active = true
        p.lightLeaks.perforationActive = true
        XCTAssertEqual(p.fullDelta["scratch_leak_enabled"], .double(1))
        XCTAssertEqual(p.fullDelta["wide_leak_active"], .bool(true))
        p.lightLeaks.active = false
        XCTAssertEqual(p.fullDelta["scratch_leak_enabled"], .double(0))
        XCTAssertEqual(p.fullDelta["wide_leak_active"], .bool(false))
        p.lightLeaks.active = true; p.digitalIntermediate = true
        XCTAssertEqual(p.fullDelta["wide_leak_active"], .bool(false))
        XCTAssertEqual(p.lightLeaks.wideStrength, 1)
    }

    func testNewMaterialsRoundTripAndPlacementControls() throws {
        for material in [WideLeakMaterial.streak34, .neutral39, .cyan15, .violet23] {
            var p = FilmParams.default
            p.lightLeaks.active = true
            p.lightLeaks.wideActive = true
            p.lightLeaks.wideMaterial = material
            p.lightLeaks.wideStrength = 0.75
            p.lightLeaks.wideDirection = .right
            p.lightLeaks.wideScale = 1.5
            p.lightLeaks.wideSoftness = 0.4
            XCTAssertEqual(try JSONDecoder().decode(FilmParams.self, from: JSONEncoder().encode(p)), p)
            XCTAssertEqual(material.usesIntrusion, material == .neutral39)
            if material.available {
                XCTAssertEqual(p.fullDelta["wide_leak_texture"], .string(material.textureURL.path))
                XCTAssertEqual(p.fullDelta["wide_leak_active"], .bool(true))
            }
        }
    }

    func testSeventyPercentDefaultAndStoredValuesSurvive() throws {
        XCTAssertEqual(LightLeakSettings().wideStrength, 0.7)
        XCTAssertEqual(FilmParams.default.lightLeaks.wideStrength, 0.7)
        var old = LightLeakSettings()
        old.wideStrength = 0.42
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        json.removeValue(forKey: "wideFlip")
        let restored = try JSONDecoder().decode(LightLeakSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.wideStrength, 0.42)
        XCTAssertEqual(restored.wideFlip, .original)
    }

    @MainActor
    func testMaterialMenuUsesVisualNamesInBothLanguages() {
        let old = Localization.shared.language
        defer { Localization.shared.language = old }
        for language in [LanguageSetting.english, .simplifiedChinese] {
            Localization.shared.language = language
            let titles = WideLeakMaterial.allCases.map(\.title)
            XCTAssertEqual(Set(titles).count, 41)
            XCTAssertTrue(titles.allSatisfy { !$0.contains(where: \.isNumber) })
            XCTAssertFalse(WideLeakGroup.allCases.contains {
                $0.title.contains("Onetake") || $0.title.contains("一闪")
            })
            let grouped = WideLeakGroup.allCases.flatMap(\.materials)
            XCTAssertEqual(grouped.count, 41)
            XCTAssertEqual(Set(grouped), Set(WideLeakMaterial.allCases))
        }
    }

    func testOnetakeWireAndSavedFlip() throws {
        XCTAssertEqual(Set(WideLeakMaterial.allCases.filter(\.isOnetake).map(\.rawValue)),
                       ["onetake_020_v1", "onetake_035_v1", "onetake_040_v1", "onetake_060_v1"])
        for material in WideLeakMaterial.allCases.filter(\.isOnetake) {
            XCTAssertFalse(material.usesIntrusion)
            for flip in WideLeakFlip.allCases {
                var p = FilmParams.default
                p.lightLeaks.active = true; p.lightLeaks.wideActive = true
                p.lightLeaks.wideMaterial = material; p.lightLeaks.wideFlip = flip
                p.lightLeaks.wideSoftness = 1
                XCTAssertEqual(try JSONDecoder().decode(FilmParams.self, from: JSONEncoder().encode(p)), p)
                if material.available {
                    XCTAssertEqual(p.fullDelta["wide_leak_anchored"], .bool(true))
                    XCTAssertEqual(p.fullDelta["wide_leak_anchor_x"], .double(material.anchor.x))
                    XCTAssertEqual(p.fullDelta["wide_leak_anchor_y"], .double(material.anchor.y))
                    XCTAssertEqual(p.fullDelta["wide_leak_flip"], .double(Double(flip.rawValue)))
                    XCTAssertEqual(p.fullDelta["wide_leak_softness"], .double(0))
                    XCTAssertEqual(p.fullDelta["wide_leak_strength"], .double(0.7))
                }
            }
        }
    }

    func testAnotherStaysWithinItsMaterialPoolAndKeepsStrength() {
        for group in WideLeakGroup.allCases {
            var settings = LightLeakSettings()
            settings.wideMaterial = group.materials[0]
            settings.wideStrength = 0.62
            for _ in 0..<20 {
                let previous = settings
                settings.randomizeWide()
                XCTAssertEqual(settings.wideMaterial.group, group)
                if group.materials.count > 1 { XCTAssertNotEqual(settings.wideMaterial, previous.wideMaterial) }
                XCTAssertNotEqual(settings.wideSeed, previous.wideSeed)
                XCTAssertEqual(settings.wideStrength, 0.62)
                XCTAssertEqual(settings.rimSeed, previous.rimSeed)
                XCTAssertEqual(settings.haloSeed, previous.haloSeed)
            }
        }
    }

    func testAllMaterialsAndExpandedCard() throws {
        XCTAssertEqual(Array(WideLeakMaterial.allCases.prefix(10)).map(\.rawValue), ["11","14","28","36","42","17","34","39","15","23"])
        XCTAssertEqual(WideLeakMaterial.allCases.count, 41)
        XCTAssertEqual(Set(WideLeakMaterial.allCases.map(\.rawValue)).count, 41)
        XCTAssertFalse(WideLeakMaterial.allCases.contains { $0.rawValue.contains("spot") })
        XCTAssertEqual(WideLeakGroup.allCases.flatMap(\.materials).count, 41)
        let key = Session.uiKey + "section." + LightLeakSection.key
        let old = UserDefaults.standard.object(forKey: key)
        let language = Localization.shared.language
        defer { UserDefaults.standard.set(old, forKey: key); Localization.shared.language = language }
        UserDefaults.standard.set(true, forKey: key)
        let session = Session()
        for lang in [LanguageSetting.english, .simplifiedChinese] {
            Localization.shared.language = lang
            if let directory = ProcessInfo.processInfo.environment["SPK_RENDER_DIR"] {
                let rows: [[String: Any]] = WideLeakMaterial.allCases.map { material in
                    ["id": material.rawValue, "title": material.title,
                     "group": String(describing: material.group), "groupTitle": material.group.title,
                     "anchored": material.isOnetake, "anchor": [material.anchor.x, material.anchor.y],
                     "usesIntrusion": material.usesIntrusion]
                }
                let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: URL(fileURLWithPath: directory).appending(path: "catalog-\(lang).json"))
            }
            for material in WideLeakMaterial.allCases {
                var p = session.params
                p.lightLeaks.active = true; p.lightLeaks.perforationActive = false
                p.lightLeaks.wideActive = true; p.lightLeaks.wideStrength = 0.7
                p.lightLeaks.wideMaterial = material
                session.params = p
                let host = NSHostingController(rootView: LightLeakSection(session: session).background(Theme.card))
                let size = host.sizeThatFits(in: CGSize(width: Theme.Metric.leftPanelWidth, height: 2400))
                XCTAssertLessThanOrEqual(size.width, Theme.Metric.leftPanelWidth + 0.5)
                XCTAssertLessThan(size.height, 1500)
                if let directory = ProcessInfo.processInfo.environment["SPK_RENDER_DIR"] {
                    let view = host.view
                    view.appearance = NSAppearance(named: .darkAqua)
                    view.frame = CGRect(origin: .zero, size: size); view.layoutSubtreeIfNeeded()
                    let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                    view.cacheDisplay(in: view.bounds, to: rep)
                    let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                    try png.write(to: URL(fileURLWithPath: directory).appending(path: "wide-leaks-\(material.rawValue)-\(lang).png"))
                }
            }
        }
    }
}
