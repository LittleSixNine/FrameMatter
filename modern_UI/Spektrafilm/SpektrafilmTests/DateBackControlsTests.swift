import AppKit
import ImageIO
import SwiftUI
import XCTest

@MainActor
final class DateBackControlsTests: XCTestCase {
    func testStyleRenumberingPreservesSavedFaces() throws {
        XCTAssertEqual(DateBackLCDStyle.allCases, [.dseg, .original])
        for (stored, style, wireStyle) in [("style1", DateBackLCDStyle.original, "lcd"), ("style2", .dseg, "dseg")] {
            let json = Data("{\"active\":true,\"lcdStyle\":\"\(stored)\"}".utf8)
            let date = try JSONDecoder().decode(DateBackSettings.self, from: json)
            XCTAssertEqual(date.lcdStyle, style)
            XCTAssertEqual(date.lcdStyle.rawValue, stored)
            XCTAssertEqual(date.wire(filmEdge: FilmEdgeSettings()).first { $0.name == "date_imprint_style" }?.value, .string(wireStyle))
        }
        let savedLanguage = Localization.shared.language
        defer { Localization.shared.language = savedLanguage }
        Localization.shared.language = .simplifiedChinese
        XCTAssertEqual(DateBackLCDStyle.dseg.title, "LCD 样式 1（DSEG7）")
        XCTAssertEqual(DateBackLCDStyle.original.title, "LCD 样式 2")
    }

    func testAllDateFacesUseTheNewSizeDefaultAndMinimum() throws {
        XCTAssertEqual(DateBackSettings.sizeRange, 0.2...3)
        for face in DateBackFace.allCases {
            var date = DateBackSettings()
            date.active = true; date.face = face
            XCTAssertEqual(date.wireSize(on: .f135), 0.5)
            date.size = 0.2
            XCTAssertEqual(date.wireSize(on: .f135), 0.2)
            XCTAssertEqual(try JSONDecoder().decode(DateBackSettings.self, from: JSONEncoder().encode(date)).size, 0.2)
        }
        let old = try JSONDecoder().decode(DateBackSettings.self, from: Data(#"{"size":0.7}"#.utf8))
        XCTAssertEqual(old.size, 0.7)
        let missing = try JSONDecoder().decode(DateBackSettings.self, from: Data(#"{}"#.utf8))
        XCTAssertEqual(missing.size, 0.5)
    }

    func testDSEGFieldSpacingPersistsAndOtherFacesIgnoreIt() throws {
        var p = FilmParams.default
        p.dateBack.active = true
        p.dateBack.lcdStyle = .dseg
        XCTAssertEqual(p.fullDelta["date_imprint_field_gap"], .double(1.20))
        let before = p
        p.dateBack.fieldGapH = 1.10
        XCTAssertEqual(p.fullDelta["date_imprint_field_gap"], .double(1.10))
        XCTAssertEqual(p.delta(from: before).layers, [.shoot])
        let saved = try JSONDecoder().decode(FilmParams.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(saved, p)
        let legacy = try JSONDecoder().decode(DateBackSettings.self, from: Data(#"{"lcdStyle":"style2"}"#.utf8))
        XCTAssertEqual(legacy.fieldGapH, 1.20)
        p.dateBack.lcdStyle = .original
        var other = p
        other.dateBack.fieldGapH = 0.20
        XCTAssertTrue(p.delta(from: other).delta.isEmpty)
        XCTAssertEqual(p.fullDelta["date_imprint_field_gap"], .double(1.20))
        p.dateBack.face = .dots
        p.dateBack.lcdStyle = .dseg
        XCTAssertEqual(p.fullDelta["date_imprint_field_gap"], .double(1.20))
        XCTAssertEqual(p.dateBack.wire(filmEdge: p.filmEdge, scale: 0.5).first { $0.name == "date_imprint_field_gap" }?.value, .double(1.20))
    }

    func testOnlyDSEGOmitsTheYearMarkIncludingBothPairFrames() {
        var date = DateBackSettings()
        date.active = true
        date.text = "'26 9 15"
        date.textB = "'26 9 16"
        XCTAssertEqual(date.printedText, "'26 9 15")
        date.lcdStyle = .dseg
        XCTAssertEqual(date.printedText, "26 9 15")
        var edge = FilmEdgeSettings()
        edge.active = true; edge.format = .f135Half; edge.pair = true
        let wire = Dictionary(uniqueKeysWithValues: date.wire(filmEdge: edge).map { ($0.name, $0.value) })
        XCTAssertEqual(wire["date_imprint_text"], .string("26 9 15"))
        XCTAssertEqual(wire["date_imprint_text_b"], .string("26 9 16"))
        date.text = "15 12 : 37"
        XCTAssertEqual(date.printedText, "15 12 : 37")
        date.text = "'26 9 15"
        date.face = .dots
        XCTAssertEqual(date.printedText, "'26 9 15")
    }

    func testDayTimeUsesCaptureClockAndDoesNotInventMissingTime() {
        let shot = ShootingData(exif: [kCGImagePropertyExifDateTimeOriginal: "2026:09:15 12:37:02"])
        XCTAssertEqual(shot.dateText(order: .dayTime), "15 12 : 37")
        XCTAssertEqual(DateBackSettings.format(year: 2026, month: 9, day: 7, hour: 8, minute: 9, order: .dayTime), "07 08 : 09")
        XCTAssertEqual(ShootingData(exif: [kCGImagePropertyExifDateTimeOriginal: "2026:09:15"]).dateText(order: .dayTime), "")
        XCTAssertEqual(ShootingData(exif: [kCGImagePropertyExifDateTimeOriginal: "2026:09:15 25:61:00"]).dateText(order: .dayTime), "")
    }

    func testManualTimeOverridesExifAndSurvivesSaving() throws {
        let shot = ShootingData(exif: [kCGImagePropertyExifDateTimeOriginal: "2026:09:15 12:37:02"])
        var p = FilmParams.default
        p.dateBack.active = true
        p.dateBack.order = .dayTime
        p.dateBack.customDateTime = "2027:04:03 08:09:00"
        p.dateBack.lcdStyle = .dseg
        p.dateBack.marginPercent = 65
        let resolved = Session.resolvedFilmEdge(p, geometry: Geometry(), shooting: shot, stock: nil)
        XCTAssertEqual(resolved.dateBack.text, "03 08 : 09")
        let restored = try JSONDecoder().decode(FilmParams.self, from: JSONEncoder().encode(resolved))
        XCTAssertEqual(restored, resolved)
        p.dateBack.customDateTime = nil
        XCTAssertEqual(p.dateBack.resolvedDateText(shooting: shot), "15 12 : 37")
        p.dateBack.customDateTime = "invalid"
        XCTAssertEqual(p.dateBack.resolvedDateText(shooting: shot), "")
    }

    func testOldEditsKeepTheirStyleAndPhysicalInsets() throws {
        let old = Data(#"{"active":true,"insetXMM":5,"insetYMM":4,"text":"'26 9 15"}"#.utf8)
        let decoded = try JSONDecoder().decode(DateBackSettings.self, from: old)
        XCTAssertEqual(decoded.lcdStyle, .original)
        XCTAssertNil(decoded.marginPercent)
        XCTAssertNil(decoded.customDateTime)
        let wire = Dictionary(uniqueKeysWithValues: decoded.wire(filmEdge: FilmEdgeSettings()).map { ($0.name, $0.value) })
        XCTAssertEqual(wire["date_imprint_style"], .string("lcd"))
        XCTAssertEqual(wire["date_imprint_margin"], .double(-1))
        XCTAssertEqual(wire["date_imprint_inset_x"], .double(5))
        XCTAssertEqual(wire["date_imprint_inset_y"], .double(4))
        XCTAssertEqual(DateBackSettings.default.marginPercent, 20)
    }

    func testStyleAndMarginRouteToTheNegative() {
        var p = FilmParams.default
        p.dateBack.active = true
        p.dateBack.lcdStyle = .dseg
        p.dateBack.marginPercent = 100
        let wire = p.fullDelta
        XCTAssertEqual(wire["date_imprint_style"], .string("dseg"))
        XCTAssertEqual(wire["date_imprint_margin"], .double(100))
        p.dateBack.face = .dots
        XCTAssertEqual(p.fullDelta["date_imprint_style"], .string("dots"))
        p.dateBack.face = .lcd
        var other = p
        other.dateBack.marginPercent = 20
        XCTAssertEqual(p.delta(from: other).layers, [.shoot])
    }

    func testDateCardFitsBothLanguagesWithManualTimeAndNewStyle() {
        let key = Session.uiKey + "section." + DateBackSection.key
        let saved = UserDefaults.standard.object(forKey: key)
        let language = Localization.shared.language
        defer {
            UserDefaults.standard.set(saved, forKey: key)
            Localization.shared.language = language
        }
        UserDefaults.standard.set(true, forKey: key)
        let session = Session()
        for language in [LanguageSetting.english, .simplifiedChinese] {
            Localization.shared.language = language
            for format in [FilmEdgeFormat.f135, .f135Half, .f645] {
                var p = session.params
                p.filmEdge.active = true
                p.filmEdge.format = format
                p.dateBack.active = true
                p.dateBack.lcdStyle = .dseg
                p.dateBack.order = .dayTime
                p.dateBack.customDateTime = "2026:09:15 12:37:00"
                session.params = p
                let host = NSHostingController(rootView: DateBackSection(session: session).background(Theme.card))
                let offered = Theme.Metric.leftPanelWidth
                let size = host.sizeThatFits(in: CGSize(width: offered, height: 4000))
                XCTAssertLessThanOrEqual(size.width, offered + 0.5, "\(language), \(format)")
                XCTAssertGreaterThan(size.height, Theme.Metric.headerHeight)
                if language == .simplifiedChinese, format == .f135,
                   let directory = ProcessInfo.processInfo.environment["SPK_RENDER_DIR"] {
                    let view = host.view
                    view.appearance = NSAppearance(named: .darkAqua)
                    view.frame = CGRect(origin: .zero, size: size)
                    view.layoutSubtreeIfNeeded()
                    if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                        view.cacheDisplay(in: view.bounds, to: rep)
                        if let png = rep.representation(using: .png, properties: [:]) {
                            try? png.write(to: URL(fileURLWithPath: directory).appending(path: "date-back-card.png"))
                        }
                    }
                }
            }
        }
    }
}
