//  Filmstrip.swift — the library. Thumbnails at one height, a white frame on
//  the open frame and a weaker one on the rest of the picked set. Import,
//  filter, sort and the library count share the strip's upper row.
//
//  Selection is the white frame and **nothing else** (PRD §5): the open
//  frame is marked by the strongest frame and a picked one by the same frame
//  held back, and no cell carries a state pip next to it.
//
//  Which frame a cell gets is `Session.framing(of:)`, not a comparison made
//  here — the Browse grid asks the same function, so the two surfaces cannot
//  draw a different set from the same state.
//
//  `LazyHStack` so a 500-image folder builds only what is visible; thumbnails
//  come from ImageIO off the main actor and are replaced by the rendered print
//  once a frame has been through the engine.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct Filmstrip: View {
    @Bindable var session: Session

    var body: some View {
        VStack(spacing: 0) {
            controls
            if !session.filmstripCollapsed { thumbnails(session.filmstripFrames) }
        }
        .railCard()
    }

    private var controls: some View {
        let importing = L("Import", zh: "导入")
        let filter = L("Filter", zh: "筛选")
        let sort = L("Sort", zh: "排序")
        let collapse = session.filmstripCollapsed ? L("Show Thumbnails", zh: "展开缩略图")
                                                  : L("Hide Thumbnails", zh: "收起缩略图")
        return HStack(spacing: 7) {
            Button { session.openPanel() } label: {
                controlLabel(importing) {
                    PhotoTransferIcon(importing: true)
                        .stroke(style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                        .frame(width: 18, height: 18)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(importing)
            .accessibilityIdentifier("filmstrip.import")
            .help(L(.helpOpen) + " (⌘O)")
            .disabled(session.batchExporting)

            optionsMenu(filter, symbol: "line.3.horizontal.decrease", options: FilmstripFilter.allCases,
                        selection: $session.filmstripFilter, title: filterTitle)
                .accessibilityIdentifier("filmstrip.filter")
            optionsMenu(sort, symbol: "arrow.up.arrow.down", options: FilmstripSort.allCases,
                        selection: $session.filmstripSort, title: sortTitle)
                .accessibilityIdentifier("filmstrip.sort")
            Text(L("\(session.picked.count) selected · \(session.frames.count) total",
                   zh: "已选 \(session.picked.count) 张 · 共 \(session.frames.count) 张"))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.secondaryText)
                .padding(.leading, 4)
                .accessibilityIdentifier("filmstrip.count")
            Spacer(minLength: 0)
            Button { withAnimation(.easeOut(duration: 0.18)) { session.filmstripCollapsed.toggle() } } label: {
                Image(systemName: session.filmstripCollapsed ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 24, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(collapse)
            .help(collapse)
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .frame(height: Theme.Metric.filmstripControlsHeight)
    }

    private func optionsMenu<Option: Hashable>(_ label: String, symbol: String, options: [Option],
                                                selection: Binding<Option>, title: @escaping (Option) -> String) -> some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button { selection.wrappedValue = option } label: {
                    if option == selection.wrappedValue {
                        Label(title(option), systemImage: "checkmark")
                    } else {
                        Text(title(option))
                    }
                }
            }
        } label: {
            controlLabel(title(selection.wrappedValue), menu: true) {
                Image(systemName: symbol).font(.system(size: 12))
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(label)
        .accessibilityValue(title(selection.wrappedValue))
        .help(label)
        .disabled(session.frames.isEmpty || session.batchExporting)
    }

    private func controlLabel(_ title: String, menu: Bool = false, @ViewBuilder icon: () -> some View) -> some View {
        HStack(spacing: 6) {
            icon().accessibilityHidden(true)
            Text(title).font(Theme.Font.body)
            if menu {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Color(hex: 0x383837), in: RoundedRectangle(cornerRadius: 5))
        .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.rule, lineWidth: 1).allowsHitTesting(false) }
        .contentShape(Rectangle())
    }

    private func filterTitle(_ option: FilmstripFilter) -> String {
        switch option {
        case .all: L("All Photos", zh: "全部照片")
        case .processed: L("Processed", zh: "已处理")
        case .pending: L("Pending", zh: "待处理")
        }
    }

    private func sortTitle(_ option: FilmstripSort) -> String {
        switch option {
        case .fileName: L("File Name ↑", zh: "文件名 ↑")
        case .fileNameDescending: L("File Name ↓", zh: "文件名 ↓")
        case .manual: L("Custom Order", zh: "自定义顺序")
        }
    }

    private func thumbnails(_ frames: [Frame]) -> some View {
        HStack(spacing: 0) {
            edgeButton("chevron.left", title: L("Previous", zh: "上一张"), enabled: !frames.isEmpty) {
                session.selectRelative(-1)
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(frames) { frame in
                            FilmstripCell(frame: frame,
                                          geometry: session.thumbnailGeometry(for: frame.id),
                                          framing: session.framing(of: frame.id),
                                          state: session.frameStates[frame.id] ?? .unprocessed)
                                .id(frame.id)
                                // Dragged along the strip a frame is moved
                                // (`FrameReorder`); onto a pair's hole on the
                                // canvas it goes into it (`PairDrop`).
                                .onDrag {
                                    session.draggedFrame = frame.id
                                    return NSItemProvider(object: frame.id as NSURL)
                                }
                                .onDrop(of: [.fileURL], delegate: FrameReorder(session: session, target: frame.id))
                                // The modifier is read here rather than
                                // declared as a second gesture: a plain
                                // `TapGesture` on macOS matches a ⌘-click too,
                                // so stacking one would fire both and a
                                // ⌘-click would collapse the set as well.
                                .onTapGesture {
                                    session.click(frame.id,
                                                  command: NSEvent.modifierFlags.contains(.command))
                                }
                                .contextMenu {
                                    Button(L(.helpRevealInFinder)) { NSWorkspace.shared.activateFileViewerSelecting([frame.id]) }
                                    if HalfFramePair.isPair(frame.id) {
                                        Button(L("Delete Pair", zh: "删除半格拼接")) { session.deletePair(frame.id) }
                                    } else {
                                        Button(L("New Half-Frame Pair", zh: "新建半格拼接")) {
                                            if !session.isPicked(frame.id) { session.click(frame.id) }
                                            session.newPair()
                                        }
                                        .disabled(!session.canMakePair)
                                    }
                                    Button(L(.helpResetDefaults)) {
                                        if frame.id == session.selection { session.resetParams(); session.resetAdjustments() }
                                        else { Sidecar.remove(for: frame.id); session.refreshState(for: frame.id) }
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: Theme.Metric.filmstripThumbnailRowHeight)
                }
                .onChange(of: session.selection, initial: true) { _, new in
                    if let new { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(new, anchor: .center) } }
                }
                .onChange(of: frames) {
                    guard session.draggedFrame == nil else { return }
                    if let selected = session.selection, frames.contains(where: { $0.id == selected }) {
                        proxy.scrollTo(selected, anchor: .center)
                    } else if let first = frames.first {
                        proxy.scrollTo(first.id, anchor: .leading)
                    }
                }
            }
            edgeButton("chevron.right", title: L("Next", zh: "下一张"), enabled: !frames.isEmpty) {
                session.selectRelative(1)
            }
        }
        .overlay(alignment: .center) {
            // Always in the tree, hidden by opacity. As a `if
            // frames.isEmpty { … }` inside an overlay builder it was observed
            // still on screen next to a loaded thumbnail: the branch had been
            // taken when the strip was empty and was not re-evaluated when it
            // filled. Opacity depends on the same value every pass, so it
            // cannot go stale.
            Text(session.frames.isEmpty ? L(.statusEmptyFilmstrip)
                 : L("No photos match the filter.", zh: "没有符合筛选条件的照片。"))
                .font(Theme.Font.label).foregroundStyle(Theme.dim)
                .opacity(frames.isEmpty ? 1 : 0)
                .accessibilityHidden(!frames.isEmpty)
                .allowsHitTesting(false)
        }
    }

    private func edgeButton(_ name: String, title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.text)
                .frame(width: 18, height: Theme.Metric.filmstripThumbnailRowHeight).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .disabled(!enabled || session.batchExporting)
    }
}

/// A thumbnail dragged over another takes its place, there and then, so the
/// strip shows the order the drop will leave. Let go, the order is kept for
/// the folder. A file from outside dropped on a cell is the window's drop.
private struct FrameReorder: DropDelegate {
    let session: Session
    let target: URL

    func dropEntered(info: DropInfo) {
        guard let dragged = session.draggedFrame, dragged != target else { return }
        withAnimation(.easeOut(duration: 0.15)) { session.moveFrame(dragged, onto: target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: session.draggedFrame != nil ? .move : .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        if session.draggedFrame != nil { session.frameOrderChanged(); return true }
        let providers = info.itemProviders(for: [.fileURL])
        Task { @MainActor in
            var urls: [URL] = []
            for p in providers {
                if let u = try? await p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                   let url = URL(dataRepresentation: u, relativeTo: nil) { urls.append(url) }
            }
            session.dropped(files: urls)
        }
        return true
    }
}

struct FilmstripCell: View {
    let frame: Frame
    /// The frame's crop, turn and flips, drawn over its thumbnail.
    var geometry: Geometry = .default
    /// Whether this cell is on the canvas, in the picked set, or neither —
    /// one value from `Session.framing(of:)` rather than two booleans, so the
    /// strip and the grid cannot spell the same state two ways.
    let framing: FrameFraming
    /// Unread by this cell; kept as the guard test's construction seam.
    let state: FrameState
    var body: some View {
        CropMaskedThumbnail(url: frame.id, geometry: geometry) { image in
            cell(image)
        }
        .help(frame.name)
    }

    private func cell(_ image: CGImage?) -> some View {
        ZStack {
            Group {
                if let image {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.well)
                        .aspectRatio(3 / 2, contentMode: .fit)
                        .overlay(Image(systemName: "photo").foregroundStyle(Theme.dim))
                }
            }
            .frame(height: Theme.Metric.thumbHeight)
            .overlay(RoundedRectangle(cornerRadius: 2)
                .stroke(Theme.selectionFrame, lineWidth: framing.lineWidth)
                .opacity(framing.opacity))
        }
    }

}
