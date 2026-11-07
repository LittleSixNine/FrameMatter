import XCTest
import SwiftUI
import AppKit

@MainActor
final class ExportProgressTests: XCTestCase {
    func testFastCompletionStaysSuccessAndNonWritesAreNotSuccess() {
        var status = ExportRunStatus(total: 1)
        XCTAssertEqual(status.phase, .working)
        status.written = 1; status.processed = 1; status.finished = true
        XCTAssertEqual(status.phase, .success)
        status.hasWarning = true
        XCTAssertEqual(status.phase, .attention)
        status.hasWarning = false; status.written = 0; status.skipped = 1
        XCTAssertEqual(status.phase, .attention)
        status.skipped = 0; status.failed = 1
        XCTAssertEqual(status.phase, .failure)
        status.cancelled = true
        XCTAssertEqual(status.phase, .cancelled)
    }
    func testWorkingSuccessAndFailureWindowsFitBothLanguages() throws {
        let old = Localization.shared.language
        defer { Localization.shared.language = old }
        for lang in [LanguageSetting.english, .simplifiedChinese] {
            Localization.shared.language = lang
            for state in ["working", "success", "failure"] {
                var status = ExportRunStatus(total: 1, currentFile: "photo.jpg")
                if state != "working" {status.finished = true; status.processed = 1}
                if state == "success" {status.written = 1;status.detail = "photo_kodak_portra_400.jpg"}
                if state == "failure" {status.failed = 1;status.detail = "Could not write the file."}
                let host = NSHostingController(rootView: ExportProgressSheet(status: status, stop: {}, done: {}))
                let size = host.sizeThatFits(in: CGSize(width: 600, height: 1000))
                XCTAssertLessThanOrEqual(size.width, 520)
                XCTAssertGreaterThan(size.height, 180)
                if let dir = ProcessInfo.processInfo.environment["SPK_EXPORT_CHECKS"] {
                    let view = host.view;view.appearance = NSAppearance(named: .darkAqua)
                    view.frame = CGRect(origin: .zero, size: size);view.layoutSubtreeIfNeeded()
                    let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to:
                        URL(fileURLWithPath: dir).appendingPathComponent("\(state)-\(lang).png"))
                }
            }
        }
    }
}
