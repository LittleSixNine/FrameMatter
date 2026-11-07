// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
// Applies only to FrameMatter contributions; upstream notices are retained. See COPYRIGHT.txt.

import XCTest
import SwiftUI
import AppKit

@MainActor
final class ChromeLocalizationTests: XCTestCase {
    func testSystemResolutionAndLicenceTitlesKeepTheirOriginalTexts() throws {
        XCTAssertEqual(Localization.resolve(["zh-Hans-CN", "en"]), .simplifiedChinese)
        XCTAssertEqual(Localization.resolve(["en-US", "zh-Hans"]), .english)
        let original = Localization.shared.language
        defer { Localization.shared.language = original }
        let gpl = try XCTUnwrap(AboutWindow.licences.first { $0.id == "FrameMatter-GPL-3.0.txt" })
        let texts = AboutWindow.licences.map(\.body)
        Localization.shared.language = .english
        XCTAssertEqual(gpl.localizedTitle, "GNU GPL v3 — the application and the engine")
        Localization.shared.language = .simplifiedChinese
        XCTAssertEqual(gpl.localizedTitle, "GNU GPL v3 — 应用与引擎")
        XCTAssertEqual(AboutWindow.licences.map(\.body), texts, "Localizing the UI must not translate legal texts")
        XCTAssertFalse(AboutWindow.licences.contains { $0.chineseTitle.isEmpty })
    }

    func testAboutFitsBothLanguagesAndRenders() throws {
        let old = Localization.shared.language
        defer { Localization.shared.language = old }
        for language in [LanguageSetting.english, .simplifiedChinese] {
            Localization.shared.language = language
            let host = NSHostingController(rootView: AboutWindow())
            let size = host.sizeThatFits(in: CGSize(width: 460, height: 1600))
            XCTAssertLessThanOrEqual(size.width, 461)
            XCTAssertLessThan(size.height, 1000)
            XCTAssertGreaterThan(size.height, 400)
            if let path = ProcessInfo.processInfo.environment["SPK_CHROME_CHECKS"] {
                let view = host.view; view.appearance = NSAppearance(named: .darkAqua)
                view.frame = CGRect(origin: .zero, size: size); view.layoutSubtreeIfNeeded()
                let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: rep)
                try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to:
                    URL(fileURLWithPath: path).appendingPathComponent("about-\(language).png"))
            }
        }
    }
}
