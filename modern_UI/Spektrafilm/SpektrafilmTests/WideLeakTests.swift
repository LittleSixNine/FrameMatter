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

    func testAllTenMaterialsAndExpandedCard() throws {
        XCTAssertEqual(WideLeakMaterial.allCases.map(\.rawValue), ["11","14","28","36","42","17","34","39","15","23"])
        let key = Session.uiKey + "section." + LightLeakSection.key
        let old = UserDefaults.standard.object(forKey: key)
        let language = Localization.shared.language
        defer { UserDefaults.standard.set(old, forKey: key); Localization.shared.language = language }
        UserDefaults.standard.set(true, forKey: key)
        let session = Session()
        for lang in [LanguageSetting.english, .simplifiedChinese] {
            Localization.shared.language = lang
            for material in WideLeakMaterial.allCases {
                var p = session.params
                p.lightLeaks.active = true; p.lightLeaks.perforationActive = false
                p.lightLeaks.wideActive = true; p.lightLeaks.wideStrength = 1
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
