import XCTest

final class FilmArtworkTests: XCTestCase {
    func testEveryArtworkReferencesARealStockAndBundledImage() {
        let stocks = Set(StockCatalog.shared.films.map(\.id))
        XCTAssertFalse(FilmArtwork.all.isEmpty)
        for artwork in FilmArtwork.all {
            XCTAssertTrue(stocks.contains(artwork.stockID), artwork.stockID)
            XCTAssertNotNil(artwork.url, artwork.file)
            if artwork.thirdParty {
                XCTAssertTrue(artwork.stockID.contains("vision3"))
            }
        }
    }

    func testPreferenceOverridesAndFallbackAreScopedToTheStock() throws {
        let stock = "kodak_portra_400"
        let variants = FilmArtwork.variants(for: stock)
        XCTAssertGreaterThan(variants.count, 1)
        let last = try XCTUnwrap(variants.last)
        let data = try JSONEncoder().encode([stock: last.id])
        let choices = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(FilmArtwork.selected(for: stock, choices: choices, alternate: false)?.id, last.id)
        XCTAssertEqual(FilmArtwork.selected(for: stock, choices: "invalid", alternate: false)?.id, variants.first?.id)
        XCTAssertEqual(FilmArtwork.selected(for: stock, choices: "{}", alternate: true)?.id, variants[1].id)
        XCTAssertNil(FilmArtwork.selected(for: "unknown_stock", choices: choices, alternate: false))
        XCTAssertFalse(variants.contains { $0.sourceID.contains("gold") })
    }
}
