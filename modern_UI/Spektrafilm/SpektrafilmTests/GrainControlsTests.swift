import AppKit
import SwiftUI
import XCTest

@MainActor
final class GrainControlsTests: XCTestCase {
    func testCardFitsTheLeftRailInBothLanguagesAndSwitchStates() {
        let key = Session.uiKey + "section." + GrainSection.key
        let saved = UserDefaults.standard.object(forKey: key)
        let language = Localization.shared.language
        defer {
            UserDefaults.standard.set(saved, forKey: key)
            Localization.shared.language = language
        }
        UserDefaults.standard.set(true, forKey: key)
        let session = Session()
        for setting in [LanguageSetting.english, .simplifiedChinese] {
            Localization.shared.language = setting
            for active in [false, true] {
                var p = session.params
                p.grainActive = active
                session.params = p
                let host = NSHostingController(rootView: GrainSection(session: session))
                let offered = Theme.Metric.leftPanelWidth
                let size = host.sizeThatFits(in: CGSize(width: offered, height: 1000))
                XCTAssertLessThanOrEqual(size.width, offered + 0.5)
                XCTAssertGreaterThan(size.height, Theme.Metric.headerHeight)
            }
        }
    }

    func testOldEffectsDecodeWithUpstreamDefaults() throws {
        let effects = try JSONDecoder().decode(EffectStrengths.self,
            from: Data(#"{"grain":0.5,"grainLayered":false}"#.utf8))
        XCTAssertEqual(effects.grain, 0.5)
        XCTAssertFalse(effects.grainLayered)
        XCTAssertEqual(effects.grainParticleAreaUM2, 0.2)
        XCTAssertEqual(effects.grainBlur, 0.65)
    }

    func testControlsRoundTripAndInvalidateTheNegative() throws {
        for kp in [\EffectStrengths.grainParticleAreaUM2, \EffectStrengths.grainBlur] {
            var sidecar = Sidecar()
            sidecar.params.effects[keyPath: kp] = 0.9
            let data = try JSONEncoder().encode(sidecar)
            let saved = try JSONDecoder().decode(Sidecar.self, from: data)
            XCTAssertEqual(saved.params, sidecar.params)
            XCTAssertEqual(saved.params.delta(from: .default).layers, [.shoot])
            XCTAssertNotEqual(Session.printStamp(saved.params), Session.printStamp(.default))
            let clip = SettingsClip(groups: [.filmEffects], settings: sidecar, sourceName: "grain-test")
            XCTAssertEqual(clip.applied(to: Sidecar()).params.effects, sidecar.params.effects)
        }
    }

    func testWireUsesUpstreamUnitsAndProductBounds() {
        var p = FilmParams.default
        p.effects.grainParticleAreaUM2 = 0.4
        p.effects.grainBlur = 0.9
        var delta = p.delta(from: .default).delta
        XCTAssertEqual(delta["grain_particle_area_um2"], .double(0.4))
        XCTAssertEqual(delta["grain_blur"], .double(0.9))
        XCTAssertEqual(p.filmFormatMM, FilmParams.default.filmFormatMM)
        p.effects.grainParticleAreaUM2 = 0
        p.effects.grainBlur = 3
        delta = p.delta(from: .default).delta
        XCTAssertEqual(delta["grain_particle_area_um2"], .double(0.01))
        XCTAssertEqual(delta["grain_blur"], .double(2))
    }

    func testGrainResetLeavesOtherEffectsAlone() {
        var effects = EffectStrengths.default
        effects.grain = 0.5
        effects.grainLayered = false
        effects.grainParticleAreaUM2 = 0.8
        effects.grainBlur = 1.2
        effects.halation = 3
        effects.glare = 4
        effects.resetGrain()
        var expected = EffectStrengths.default
        expected.halation = 3
        expected.glare = 4
        XCTAssertEqual(effects, expected)
    }
}
