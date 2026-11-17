import SwiftUI

struct FilmArtworkSettingsPage: View {
    @AppStorage("filmArtwork.choices") private var choices = "{}"
    @AppStorage("filmArtwork.alternate") private var alternate = false

    private var saved: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(choices.utf8))) ?? [:]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle(L("Prefer alternate covers", zh: "优先使用第二版封面"), isOn: $alternate)
            Text(L("Choose a cover for each film. Respooler packaging changes the artwork only.",
                   zh: "可逐款指定封面。第三方分装封面仅改变外观，胶片模拟仍按原厂型号运行。"))
                .font(Theme.Font.caption).foregroundStyle(Theme.Ink.tertiary)
            Button(L("Restore cover defaults", zh: "恢复默认封面")) { choices = "{}"; alternate = false }
            ForEach(StockCatalog.shared.films) { stock in
                let variants = FilmArtwork.variants(for: stock.id)
                VStack(alignment: .leading, spacing: 8) {
                    Text(stock.name).font(Theme.Font.label)
                    if variants.isEmpty {
                        Text(L("Cover pending", zh: "封面待补齐")).font(Theme.Font.caption)
                    } else {
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: 10) {
                                Button(L("Follow default", zh: "跟随默认")) { choose(nil, for: stock.id) }
                                ForEach(variants) { artwork in
                                    let selected = FilmArtwork.selected(for: stock.id, choices: choices, alternate: alternate)?.id == artwork.id
                                    Button { choose(artwork.id, for: stock.id) } label: {
                                        VStack(alignment: .leading, spacing: 5) {
                                            FilmArtworkImage(artwork: artwork, name: stock.name)
                                                .frame(width: 88, height: 88)
                                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(selected ? Theme.accent : .clear, lineWidth: 2))
                                            Text(artwork.title).font(Theme.Font.caption).lineLimit(3)
                                                .frame(width: 88, alignment: .leading)
                                        }
                                    }.buttonStyle(.plain).help(artwork.title)
                                        .accessibilityAddTraits(selected ? .isSelected : [])
                                }
                            }.padding(3)
                        }
                    }
                }
            }
        }.padding(.horizontal, 24)
    }

    private func choose(_ id: String?, for stock: String) {
        var next = saved
        next[stock] = id
        if let data = try? JSONEncoder().encode(next), let json = String(data: data, encoding: .utf8) { choices = json }
    }
}
