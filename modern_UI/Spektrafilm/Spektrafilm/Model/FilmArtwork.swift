import Foundation

struct FilmArtwork: Codable, Identifiable, Sendable {
    let stockID: String
    let id: String
    let file: String
    let title: String
    let sourceID: String
    let thirdParty: Bool

    static let all: [FilmArtwork] = {
        guard let url = StockCatalog.bundle.url(forResource: "catalog", withExtension: "json",
                                                subdirectory: "Resources/FilmArtwork"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([FilmArtwork].self, from: data) else { return [] }
        return items
    }()

    static func variants(for stock: String) -> [FilmArtwork] { all.filter { $0.stockID == stock } }

    static func selected(for stock: String, choices: String, alternate: Bool) -> FilmArtwork? {
        let variants = variants(for: stock)
        let saved = (try? JSONDecoder().decode([String: String].self, from: Data(choices.utf8))) ?? [:]
        if let id = saved[stock], let chosen = variants.first(where: { $0.id == id }) { return chosen }
        return variants.dropFirst(alternate && variants.count > 1 ? 1 : 0).first
    }

    var url: URL? {
        StockCatalog.bundle.url(forResource: file, withExtension: nil, subdirectory: "Resources/FilmArtwork")
    }
}
