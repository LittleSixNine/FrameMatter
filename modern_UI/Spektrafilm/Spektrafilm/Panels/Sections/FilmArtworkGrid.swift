import SwiftUI
import AppKit

struct FilmArtworkImage: View {
    let artwork: FilmArtwork?
    let name: String
    var body: some View {
        ZStack {
            if let url = artwork?.url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Text(name).font(Theme.Font.caption).multilineTextAlignment(.center).padding(8)
            }
        }.aspectRatio(1, contentMode: .fit)
    }
}

struct FilmArtworkGrid: View {
    @Bindable var session: Session
    let select: (String) -> Void
    @AppStorage("filmArtwork.choices") private var choices = "{}"
    @AppStorage("filmArtwork.alternate") private var alternate = false
    @Environment(\.sectionSized) private var sized
    @FocusState private var focusedStock: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(session.catalog.filmGroups.filter { !$0.films.isEmpty }, id: \.title) { group in
                        Text(L(filmGroup: group.title)).font(Theme.Font.stockGroup)
                            .foregroundStyle(Theme.Ink.tertiary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 12) {
                            ForEach(group.films) { stock in
                                let on = session.params.filmStock == stock.id
                                Button { select(stock.id) } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        FilmArtworkImage(artwork: FilmArtwork.selected(for: stock.id, choices: choices, alternate: alternate), name: stock.name)
                                        Text(stock.name).font(Theme.Font.caption)
                                            .foregroundStyle(Theme.text)
                                            .lineLimit(2).frame(height: 30, alignment: .topLeading)
                                    }
                                    .padding(5)
                                    .background(on ? Theme.text.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain).help(stock.name).id(stock.id)
                                    .focused($focusedStock, equals: stock.id)
                                    .accessibilityLabel(stock.name)
                                    .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                    }
                }.padding(4)
            }.scrollIndicators(.visible)
                .onMoveCommand { direction in
                    let stocks = session.catalog.filmGroups.flatMap(\.films)
                    guard let current = stocks.firstIndex(where: { $0.id == (focusedStock ?? session.params.filmStock) }) else { return }
                    let offset: Int
                    switch direction {
                    case .left: offset = -1
                    case .right: offset = 1
                    case .up: offset = -3
                    case .down: offset = 3
                    @unknown default: return
                    }
                    let next = min(max(current + offset, 0), stocks.count - 1)
                    focusedStock = stocks[next].id
                    proxy.scrollTo(stocks[next].id, anchor: .center)
                }
                .onAppear { proxy.scrollTo(session.params.filmStock, anchor: .center) }
        }.frame(minHeight: 260, maxHeight: sized ? .infinity : 300)
    }
}
