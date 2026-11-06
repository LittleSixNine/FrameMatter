import AppKit
import ImageIO
import SwiftUI
import XCTest

@MainActor
final class DateBackControlsTests: XCTestCase {
    func testDateTimeFormatsAndMissingClock() throws {
        let shot = ShootingData(exif: [kCGImagePropertyExifDateTimeOriginal: "2026:09:16 17:50:08"])
        let expected: [DateBackOrder: String] = [
            .japan: "'26 9 16", .us: "9 16 '26", .europe: "16 9 '26",
            .dayTime: "16 17 : 50", .timeSeconds: "17 : 50 : 08",
            .dateTimeSeconds: "'26 09 16 17 : 50 : 08",
            .yearMonthDayHour: "'26 09 16 17", .monthDayTime: "09 16 17 : 50",
            .dayTimeSeconds: "16 17 : 50 : 08"
        ]
        XCTAssertEqual(Set(expected.keys), Set(DateBackOrder.allCases))
        XCTAssertEqual(DateBackOrder.selectableCases, [.japan, .us, .europe, .dayTime, .timeSeconds, .dateTimeSeconds])
        XCTAssertEqual(DateBackSettings().order, .japan)
        for (order, text) in expected { XCTAssertEqual(shot.dateText(order: order), text) }
        XCTAssertEqual(shot.captureDay?.second, 8)
        for order in DateBackOrder.allCases where order != .us && order != .japan && order != .europe {
            XCTAssertEqual(ShootingData(exif: [kCGImagePropertyExifDateTimeOriginal: "2026:09:16"]).dateText(order: order), "")
        }
        XCTAssertEqual(DateBackSettings.format(year: 2026, month: 9, day: 16, hour: 17, minute: 50, second: 60, order: .timeSeconds), "")
        XCTAssertEqual(try JSONDecoder().decode(DateBackSettings.self, from: Data("{}".utf8)).timeMark, .colon)
    }

    func testUnderlineRoutingAndManualSeconds() throws {
        var p = FilmParams.default
        p.dateBack.active = true
        p.dateBack.order = .dayTime
        p.dateBack.timeMark = .underline
        p.dateBack.customDateTime = "2026:09:16 17:50:08"
        p.dateBack.text = p.dateBack.resolvedDateText(shooting: ShootingData())
        XCTAssertEqual(p.fullDelta["date_imprint_text"], .string("16 17 50"))
        XCTAssertEqual(p.fullDelta["date_imprint_time_underline"], .bool(true))
        let previous = p
        p.dateBack.timeMark = .colon
        XCTAssertEqual(p.delta(from: previous).layers, [.shoot])
        XCTAssertEqual(p.fullDelta["date_imprint_text"], .string("16 17 : 50"))
        p.dateBack.order = .timeSeconds
        p.dateBack.timeMark = .underline
        XCTAssertFalse(p.dateBack.underlinesTime)
        XCTAssertEqual(p.dateBack.resolvedDateText(shooting: ShootingData()), "17 : 50 : 08")
        XCTAssertEqual(try JSONDecoder().decode(FilmParams.self, from: JSONEncoder().encode(p)), p)
    }

    func testFullTimestampRequiresAndSelectsBetweenFrames() {
        let session = Session()
        for camera in [FilmEdgeFormat.f135, .f135Half] {
            var p = session.params
            p.filmEdge.active = camera == .f135Half
            p.filmEdge.format = camera
            p.dateBack.camera = camera
            p.dateBack.active = true
            p.dateBack.order = .japan
            p.dateBack.placement = .frame
            session.params = p
            session.setDateBackOrder(.dateTimeSeconds)
            XCTAssertTrue(session.params.filmEdge.effective)
            XCTAssertEqual(session.params.filmEdge.format, camera)
            XCTAssertEqual(session.params.dateBack.placement, .between)
            var date = session.params.dateBack
            date.placement = .frame
            XCTAssertEqual(date.effectivePlacement, .between)
            XCTAssertTrue(date.effective(filmEdge: session.params.filmEdge))
            XCTAssertFalse(date.effective(filmEdge: FilmEdgeSettings()))
        }
        var p = session.params
        p.filmEdge.format = .f645
        p.dateBack.order = .japan
        session.params = p
        session.setDateBackOrder(.dateTimeSeconds)
        XCTAssertEqual(session.params.dateBack.order, .japan)
        p.dateBack.order = .dateTimeSeconds
        XCTAssertFalse(p.dateBack.effective(filmEdge: p.filmEdge))
    }

    func testLCDMenuOrderAndSavedFaces() throws {
        XCTAssertEqual(DateBackLCDStyle.allCases, [.classicRegular, .classicMiniRegular, .classicMiniItalic, .dseg, .original])
        XCTAssertEqual(DateBackLCDStyle.selectableCases, [.classicRegular, .classicMiniRegular, .classicMiniItalic, .dseg])
        XCTAssertEqual(DateBackSettings().lcdStyle, .classicRegular)
        for (stored, style, wireStyle) in [("style1", DateBackLCDStyle.original, "lcd"), ("style2", .dseg, "dseg"),
                                           ("classicMiniItalic", .classicMiniItalic, "dseg_mini_italic"),
                                           ("classicMiniRegular", .classicMiniRegular, "dseg_mini_regular"),
                                           ("classicRegular", .classicRegular, "dseg_classic_regular")] {
            let json = Data("{\"active\":true,\"lcdStyle\":\"\(stored)\"}".utf8)
            let date = try JSONDecoder().decode(DateBackSettings.self, from: json)
            XCTAssertEqual(date.lcdStyle, style)
            XCTAssertEqual(date.lcdStyle.rawValue, stored)
            XCTAssertEqual(try JSONDecoder().decode(DateBackSettings.self, from: JSONEncoder().encode(date)), date)
            XCTAssertEqual(date.wire(filmEdge: FilmEdgeSettings()).first { $0.name == "date_imprint_style" }?.value, .string(wireStyle))
        }
        let savedLanguage = Localization.shared.language
        defer { Localization.shared.language = savedLanguage }
        Localization.shared.language = .simplifiedChinese
        XCTAssertEqual(DateBackLCDStyle.dseg.title, "DSEG7（经典 迷你 粗 斜）")
        XCTAssertEqual(DateBackLCDStyle.classicMiniItalic.title, "DSEG7（经典 迷你 斜）")
        XCTAssertEqual(DateBackLCDStyle.classicMiniRegular.title, "DSEG7（经典 迷你 常规）")
        XCTAssertEqual(DateBackLCDStyle.classicRegular.title, "DSEG7（经典 常规）")
        XCTAssertEqual(DateBackLCDStyle.original.title, "旧版日期字体")
        Localization.shared.language = .english
        XCTAssertEqual(DateBackLCDStyle.selectableCases.map(\.title), [
            "DSEG7 Classic Regular", "DSEG7 Classic Mini Regular",
            "DSEG7 Classic Mini Italic", "DSEG7 Classic Mini Bold Italic"
        ])
    }

    func testAllDSEGChoicesKeepSpacingYearMarkAndRenderInvalidation() {
        var previous = FilmParams.default
        previous.dateBack.active = true
        for style in DateBackLCDStyle.allCases where style != .original {
            var p = previous
            p.dateBack.lcdStyle = style
            p.dateBack.fieldGapH = 2.5
            p.dateBack.text = "'26 9 15"
            XCTAssertEqual(p.fullDelta["date_imprint_field_gap"], .double(2.5))
            XCTAssertEqual(p.fullDelta["date_imprint_text"], .string("26 9 15"))
            XCTAssertEqual(p.delta(from: previous).layers, [.shoot])
            previous = p
        }
    }

    func testAllDateFacesUseTheNewSizeDefaultAndMinimum() throws {
        XCTAssertEqual(DateBackSettings.sizeRange, 0.2...1)
        for face in DateBackFace.allCases {
            var date = DateBackSettings()
            date.active = true; date.face = face
            XCTAssertEqual(date.wireSize(on: .f135), 0.4)
            date.size = 0.41
            XCTAssertEqual(date.wireSize(on: .f135), 0.41)
            date.size = 1.01
            XCTAssertEqual(date.wireSize(on: .f135), 1.0)
            date.size = 0.2
            XCTAssertEqual(date.wireSize(on: .f135), 0.2)
            XCTAssertEqual(try JSONDecoder().decode(DateBackSettings.self, from: JSONEncoder().encode(date)).size, 0.2)
        }
        let old = try JSONDecoder().decode(DateBackSettings.self, from: Data(#"{"size":0.7}"#.utf8))
        XCTAssertEqual(old.size, 0.7)
        let missing = try JSONDecoder().decode(DateBackSettings.self, from: Data(#"{}"#.utf8))
        XCTAssertEqual(missing.size, 0.4)
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
        date.lcdStyle = .original
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
            for (format, style) in [FilmEdgeFormat.f135, .f135Half, .f645].flatMap({ format in
                DateBackLCDStyle.allCases.map { (format, $0) }
            }) {
                var p = session.params
                p.filmEdge.active = true
                p.filmEdge.format = format
                p.dateBack.active = true
                p.dateBack.lcdStyle = style
                p.dateBack.order = style == .classicRegular ? .dateTimeSeconds : .dayTime
                p.dateBack.timeMark = .underline
                p.dateBack.customDateTime = "2026:09:15 12:37:00"
                session.params = p
                let host = NSHostingController(rootView: DateBackSection(session: session).background(Theme.card))
                let offered = Theme.Metric.leftPanelWidth
                let size = host.sizeThatFits(in: CGSize(width: offered, height: 4000))
                XCTAssertLessThanOrEqual(size.width, offered + 0.5, "\(language), \(format)")
                XCTAssertGreaterThan(size.height, Theme.Metric.headerHeight)
                if language == .simplifiedChinese, format == .f135, style == .dseg,
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
