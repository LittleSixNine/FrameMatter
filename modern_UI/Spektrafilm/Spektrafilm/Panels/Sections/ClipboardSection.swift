import SwiftUI
import AppKit
import CoreImage
import Metal

struct DevelopPresetsSection: View {
    @Bindable var session: Session
    @AppStorage("filmArtwork.choices") private var artworkChoices = "{}"
    @AppStorage("filmArtwork.alternate") private var alternateArtwork = false
    @State private var search = ""
    @State private var category = "__all"
    @State private var favoritesOnly = false
    @State private var editing: DevelopPreset?
    @State private var removal: DevelopPreset?
    @State private var visiblePreviewIDs: Set<UUID> = []
    @State private var previewPhoto: URL?
    @State private var previews: [UUID: NSImage] = [:]
    @State private var previewErrors: [UUID: String] = [:]
    @State private var error: String?
    private var categories: [String] {
        Array(Set(session.developPresets.map { $0.category ?? "" })).filter { !$0.isEmpty }.sorted()
    }
    private var visible: [DevelopPreset] {
        session.developPresets.filter {
            (!favoritesOnly || $0.favorite == true) &&
            (category == "__all" || ($0.category ?? "") == category) &&
            (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
        }
    }
    private var requestedPreviews: [DevelopPreset] {
        PresetPreviewCache.requested(visible, onScreen: visiblePreviewIDs)
    }
    private var previewKey: String {
        guard let url = session.selection else { return "" }
        return requestedPreviews.map {
            $0.id.uuidString + PresetPreviewCache.key(for: $0, target: session.sidecar, url: url)
        }.joined(separator: "|")
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(L("Presets", zh: "预设")).font(Theme.Font.railTitle)
                Spacer(minLength: 0)
                Button { newPreset() } label: {
                    Label(L("New", zh: "新建"), systemImage: "plus")
                        .font(Theme.Font.caption)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Theme.secondaryText.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help(L("Save new preset", zh: "保存新预设"))
                .accessibilityIdentifier("presets.new")
                .disabled(session.selection == nil || session.batchExporting)
                Button { session.toggleInspector(.presets) } label: {
                    Image(systemName: "sidebar.right").font(Theme.Font.caption)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(L("Collapse", zh: "收起"))
                .accessibilityLabel(L("Collapse", zh: "收起"))
                .accessibilityIdentifier("inspector.collapse")
            }
            .padding(.horizontal, Theme.Metric.rowInset)
            .frame(height: Theme.Metric.panelHeaderHeight)
            .background(WindowDragHandle())
            Hairline()

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondaryText)
                    TextField(L("Search presets", zh: "搜索预设"), text: $search)
                        .textFieldStyle(.plain)
                        .accessibilityIdentifier("presets.search")
                }
                .font(Theme.Font.caption)
                .padding(8)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.rule, lineWidth: 1))
                HStack(spacing: 4) {
                    filterButton(L("All", zh: "全部"), favorites: false)
                    filterButton(L("Favorites", zh: "收藏"), favorites: true)
                    Spacer(minLength: 4)
                    Menu {
                        Button(L("All categories", zh: "所有分类")) { category = "__all" }
                        ForEach(categories, id: \.self) { name in
                            Button(name) { category = name }
                        }
                    } label: {
                        Text(category == "__all" ? L("All categories", zh: "所有分类") : category)
                            .lineLimit(1).font(Theme.Font.caption).foregroundStyle(Theme.secondaryText)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(maxWidth: 120, alignment: .trailing)
                    .accessibilityLabel(L("Category", zh: "分类"))
                }
            }
            .padding(.horizontal, Theme.Metric.rowInset)
            .padding(.top, 14).padding(.bottom, 12)

            if let active = session.developPresets.first(where: { $0.id == session.activeDevelopPresetID }) {
                let saved = active.applied(to: session.sidecar)
                let modified = saved.params != session.params || saved.adjustments != session.adjustments || saved.decode != session.sidecar.decode
                VStack(spacing: 0) {
                    Hairline()
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Text(L("Current preset", zh: "当前预设")).foregroundStyle(Theme.secondaryText)
                                if modified { Text(L("· Modified", zh: "· 已修改")).foregroundStyle(Theme.accent) }
                            }.font(Theme.Font.caption)
                            Text(active.name).font(Theme.Font.caption).lineLimit(1).help(active.name)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Button(L("Update", zh: "更新")) {
                            var draft = active
                            draft.settings = session.sidecar
                            editing = draft
                        }
                        .font(Theme.Font.caption)
                        .disabled(session.selection == nil || session.batchExporting || !modified)
                    }.padding(.vertical, 12)
                    Hairline()
                }.padding(.horizontal, Theme.Metric.rowInset)
            }
            if let error {
                Text(error).font(Theme.Font.caption).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Metric.rowInset).padding(.top, 8)
            }
            if visible.isEmpty {
                ContentUnavailableView {
                    Label(L("No presets", zh: "暂无预设"), systemImage: "square.stack")
                } description: {
                    Text(session.developPresets.isEmpty
                        ? L("Adjust a photo, then press New to save its look.", zh: "调整好照片后，点击「新建」保存为预设。")
                        : L("No matching presets. Try another search or category.", zh: "没有匹配的预设，请更换搜索词或分类。"))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    presetGrid
                        .padding(.horizontal, Theme.Metric.rowInset)
                        .padding(.vertical, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("presets.library")
            }
            Hairline()
            HStack {
                Text(L(String(visible.count) + " presets", zh: String(visible.count) + " 个预设"))
                    .font(Theme.Font.caption).foregroundStyle(Theme.secondaryText)
                Spacer(minLength: 0)
                if session.pasteTargets.count > 1,
                   let active = session.developPresets.first(where: { $0.id == session.activeDevelopPresetID }) {
                    Button(L("Apply to " + String(session.pasteTargets.count) + " photos", zh: "应用到 " + String(session.pasteTargets.count) + " 张照片")) {
                        session.applyDevelopPreset(active, toSelected: true)
                    }.font(Theme.Font.caption).disabled(session.batchExporting)
                }
            }.padding(.horizontal, Theme.Metric.rowInset).padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { session.reloadDevelopPresets() }
        .task(id: previewKey) { await generatePreviews() }
        .sheet(item: $editing) { preset in
            PresetEditor(preset: preset, categories: categories,
                         existing: session.developPresets.contains { $0.id == preset.id }, save: {
                try session.storeDevelopPreset($0)
            })
        }
        .alert(L("Delete preset?", zh: "删除预设？"), isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), presenting: removal) { preset in
            Button(L("Cancel", zh: "取消"), role: .cancel) {}
            Button(L("Delete", zh: "删除"), role: .destructive) { session.removeDevelopPreset(preset) }
        } message: { Text($0.name) }
    }

    private var presetGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 18) {
            ForEach(visible) { preset in
                VStack(alignment: .leading, spacing: 6) {
                    Button { session.applyDevelopPreset(preset) } label: {
                        ZStack {
                            Rectangle().fill(Theme.ground)
                            if previewPhoto == session.selection, let image = previews[preset.id] {
                                Image(nsImage: image).resizable().scaledToFit()
                            } else if session.selection != nil && previewErrors[preset.id] == nil {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "photo").foregroundStyle(Theme.secondaryText)
                            }
                        }.aspectRatio(1.25, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(session.activeDevelopPresetID == preset.id ? Theme.accent : .clear, lineWidth: 2))
                            .overlay(alignment: .bottomLeading) {
                                if (preset.includedGroups ?? DevelopPreset.groups).contains(.filmAndPaper),
                                   let artwork = FilmArtwork.selected(for: preset.settings.params.filmStock,
                                                                      choices: artworkChoices, alternate: alternateArtwork),
                                   let url = artwork.url, let image = NSImage(contentsOf: url) {
                                    let filmName = session.catalog.stock(artwork.stockID)?.name ?? artwork.title
                                    Image(nsImage: image).resizable().scaledToFill()
                                        .frame(width: 32, height: 36)
                                        .clipShape(RoundedRectangle(cornerRadius: 2))
                                        .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 2)
                                        .padding(7)
                                        .help(filmName)
                                        .accessibilityLabel(filmName)
                                }
                            }
                            .overlay(alignment: .topTrailing) {
                                if session.activeDevelopPresetID == preset.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.accent)
                                        .background(Theme.card, in: Circle())
                                        .padding(5)
                                        .accessibilityHidden(true)
                                }
                            }
                    }.buttonStyle(.plain)
                        .disabled(session.selection == nil || session.batchExporting)
                        .help(previewErrors[preset.id] ?? L("Apply to current photo", zh: "应用到当前照片"))
                        .accessibilityLabel(preset.name)
                        .accessibilityAddTraits(session.activeDevelopPresetID == preset.id ? .isSelected : [])
                    HStack(alignment: .center, spacing: 6) {
                        Text(preset.name).font(Theme.Font.caption).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            var changed = preset
                            changed.favorite = !(preset.favorite ?? false)
                            persist(changed)
                        } label: {
                            Image(systemName: preset.favorite == true ? "star.fill" : "star")
                                .foregroundStyle(preset.favorite == true ? Theme.accent : Theme.secondaryText)
                                .frame(width: 22, height: 22)
                        }.buttonStyle(.plain).help(L("Favorite", zh: "收藏"))
                        .accessibilityLabel((preset.favorite == true ? L("Unfavorite ", zh: "取消收藏 ") : L("Favorite ", zh: "收藏 ")) + preset.name)
                    }
                }.onScrollVisibilityChange(threshold: 0.01) { shown in
                    if shown { visiblePreviewIDs.insert(preset.id) }
                    else { visiblePreviewIDs.remove(preset.id) }
                }.contextMenu {
                    Button(L("Edit preset", zh: "编辑预设")) { editing = preset }
                    Button(L("Apply to selected photos", zh: "应用到选中照片")) { session.applyDevelopPreset(preset, toSelected: true) }
                        .disabled(session.selection == nil || session.batchExporting)
                    Button(L("Delete", zh: "删除"), role: .destructive) { removal = preset }
                }
            }
        }.padding(3)
    }

    private func filterButton(_ title: String, favorites: Bool) -> some View {
        Button { favoritesOnly = favorites } label: {
            HStack(spacing: 4) {
                if favorites { Image(systemName: "star") }
                Text(title)
            }
            .font(Theme.Font.caption)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .foregroundStyle(favoritesOnly == favorites ? Theme.text : Theme.secondaryText)
            .background(favoritesOnly == favorites ? Theme.secondaryText.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(favoritesOnly == favorites ? .isSelected : [])
    }

    private func newPreset() {
        var draft = DevelopPreset(name: "", source: session.sidecar)
        draft.settings = session.sidecar
        draft.includedGroups = [.filmAndPaper, .filmEffects, .printEffects, .postDev]
        draft.includesEffects = true
        draft.includesSecondPhoto = false
        editing = draft
    }

    private func persist(_ preset: DevelopPreset) {
        do { try session.storeDevelopPreset(preset); error = nil }
        catch { self.error = error.localizedDescription }
    }

    @MainActor private func generatePreviews() async {
        guard let url = session.selection else { return }
        if previewPhoto != url {
            previews = [:]
            previewErrors = [:]
            previewPhoto = url
        }
        let requested = requestedPreviews
        let pending = requested.filter { preset in
            if previews[preset.id] == nil {
                previews[preset.id] = PresetPreviewCache.shared.image(for: PresetPreviewCache.previousKey(for: preset, url: url))
            }
            let key = PresetPreviewCache.key(for: preset, target: session.sidecar, url: url)
            if let image = PresetPreviewCache.shared.image(for: key) {
                previews[preset.id] = image
                previewErrors[preset.id] = nil
                return false
            }
            return true
        }
        guard !pending.isEmpty else { return }
        let target = session.sidecar
        let device = session.renderer.device
        let client = EngineClient(device: device)
        var decodes: [String: DecodedImage] = [:]
        for preset in pending {
            if Task.isCancelled { break }
            do {
                previewErrors[preset.id] = nil
                let previewCacheKey = PresetPreviewCache.key(for: preset, target: target, url: url)
                var applied = preset.applied(to: target, perspectiveAllowed: ImageDecoder.rawExtensions.contains(url.pathExtension.lowercased()))
                let key = CacheKey.encodedConfiguration(applied.decode)
                let decoded: DecodedImage
                if let cached = decodes[key] { decoded = cached }
                else {
                    let decodeSettings = applied.decode
                    decoded = try await Task.detached(priority: .utility) {
                        try ImageDecoder.decode(url, settings: decodeSettings)
                    }.value
                    decodes[key] = decoded
                }
                applied = DevelopPreset.previewSettings(applied, target: target, size: decoded.pixelSize,
                    shooting: ShootingData(exif: decoded.sourceEXIF), stock: session.catalog.stock(applied.params.filmStock))
                let settings = applied
                let frame = try await Task.detached(priority: .utility) {
                    var image = Session.engineImage(decoded.linear, size: decoded.pixelSize,
                        cut: settings.params.cutsFrame ? settings.geometry : nil)
                    if settings.params.doubleExposure.active { image = try settings.params.doubleExposure.compose(image) }
                    let factor = min(1, CGFloat(DevelopPreset.previewLongEdge) / max(image.extent.width, image.extent.height))
                    image = image.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
                    return try ImageDecoder.engineFrame(from: image, device: device)
                }.value
                try Task.checkCancellation()
                var delta = applied.params.fullDelta
                delta["preview_long_edge"] = .double(Double(DevelopPreset.previewLongEdge))
                delta["product_defaults"] = .bool(true)
                let opened = try await client.open(frame, paramsDelta: delta)
                let _: SolveResponse = try await client.call(.solve, SolveRequest(sessionID: opened.sessionID, target: "both"))
                let rendered = try await client.render(.reprint, RenderRequest(sessionID: opened.sessionID))
                try Task.checkCancellation()
                if let texture = rendered.texture,
                   let image = DevelopPreset.previewImage(texture: texture, adjustments: applied.adjustments, device: device, geometry: applied.params.cutsFrame ? .default : applied.geometry) {
                    let thumbnail = NSImage(cgImage: image, size: .zero)
                    PresetPreviewCache.shared.store(thumbnail, for: previewCacheKey)
                    PresetPreviewCache.shared.store(thumbnail, for: PresetPreviewCache.previousKey(for: preset, url: url))
                    previews[preset.id] = thumbnail
                } else { previewErrors[preset.id] = L("Preview unavailable", zh: "预览暂不可用") }
            } catch {
                if !Task.isCancelled { previewErrors[preset.id] = String(describing: error) }
            }
        }
        await client.stop()
    }
}

@MainActor
final class PresetPreviewCache {
    static let shared = PresetPreviewCache()
    private let images = NSCache<NSString, NSImage>()

    init() {
        images.countLimit = 128
        images.totalCostLimit = 32 * 1024 * 1024
    }

    func image(for key: String) -> NSImage? { images.object(forKey: key as NSString) }
    func store(_ image: NSImage, for key: String) {
        images.setObject(image, forKey: key as NSString, cost: 240 * 180 * 8)
    }

    static func requested(_ presets: [DevelopPreset], onScreen: Set<UUID>) -> [DevelopPreset] {
        let indices = presets.indices.filter { onScreen.contains(presets[$0].id) }
        guard let last = indices.last else { return Array(presets.prefix(4)) }
        let next = presets.indices.filter { $0 > last }.prefix(2)
        return (indices + next).map { presets[$0] }
    }

    static func key(for preset: DevelopPreset, target: Sidecar, url: URL) -> String {
        let applied = preset.applied(to: target,
            perspectiveAllowed: ImageDecoder.rawExtensions.contains(url.pathExtension.lowercased()))
        // Keep file state and render inputs; library names, stars and categories do not change pixels.
        var look = Sidecar()
        look.params = applied.params
        look.adjustments = applied.adjustments
        look.decode = applied.decode
        look.geometry = applied.geometry
        look.heldCrop = target.heldCrop
        look.noFilm = applied.noFilm
        let second = applied.params.doubleExposure
        return fileKey(url) + (second.active ? fileKey(URL(fileURLWithPath: second.path)) : "")
            + CacheKey.encodedConfiguration(look)
            + String(target.params.filmEdge.effective) + target.params.filmEdge.format.rawValue
            + String(Session.recalculateEffectsAfterCrop)
    }

    static func previousKey(for preset: DevelopPreset, url: URL) -> String {
        "previous|" + fileKey(url) + preset.id.uuidString
    }

    private static func fileKey(_ url: URL) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return url.path + "|" + String((attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)
            + "|" + String((attributes?[.size] as? Int) ?? 0) + "|"
    }
}

private struct PresetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var preset: DevelopPreset
    let categories: [String]
    let existing: Bool
    let save: (DevelopPreset) throws -> Void
    @State private var error: String?
    private let offered: [ClipboardGroup] = [.filmAndPaper, .filmEffects, .printEffects, .postDev, .exposure, .whiteBalance, .scenePlacement]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(existing ? L("Edit Preset", zh: "编辑预设") : L("Save Preset", zh: "保存预设")).font(.headline)
            TextField(L("Name", zh: "名称"), text: $preset.name)
            TextField(L("Category · enter a new name", zh: "分类 · 可输入新分类"), text: Binding(get: { preset.category ?? "" }, set: { preset.category = $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
            if !categories.isEmpty {
                Menu(L("Existing categories", zh: "选择已有分类")) {
                    ForEach(categories, id: \.self) { category in Button(category) { preset.category = category } }
                }
            }
            Text(L("Include adjustments", zh: "保存范围")).font(.headline)
            ForEach(offered) { group in
                Toggle(group.title, isOn: Binding(get: { (preset.includedGroups ?? DevelopPreset.groups).contains(group) }, set: { on in
                    var groups = preset.includedGroups ?? DevelopPreset.groups
                    if on { groups.insert(group) } else { groups.remove(group) }
                    preset.includedGroups = groups
                }))
            }
            Toggle(L("Effects · diffusion, borders, light and wear", zh: "效果 · 柔光镜、片边、漏光与做旧"), isOn: Binding(get: { preset.includesEffects == true }, set: { preset.includesEffects = $0 }))
            Toggle(L("Include second photo for double exposure", zh: "包含双重曝光的第二张照片"), isOn: Binding(get: { preset.includesSecondPhoto == true }, set: { preset.includesSecondPhoto = $0 }))
            if preset.includesSecondPhoto == true {
                Text(L("The original file must remain available.", zh: "应用时需要能访问第二张照片原文件。")).font(.caption).foregroundStyle(Theme.secondaryText)
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                Button(L("Cancel", zh: "取消")) { dismiss() }
                Spacer()
                if existing { Button(L("Save as New", zh: "另存为")) { commit(copy: true) } }
                Button(existing ? L("Update Preset", zh: "更新原预设") : L("Save", zh: "保存")) { commit(copy: false) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 390)
    }

    private func commit(copy: Bool) {
        var next = preset
        if copy { next.id = UUID(); next.name += L(" Copy", zh: " 副本") }
        do { try save(next); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}


extension DevelopPreset {
    @MainActor static func previewSettings(_ applied: Sidecar, target: Sidecar, size: CGSize,
                                            shooting: ShootingData, stock: Stock?) -> Sidecar {
        var result = applied
        if applied.params.filmEdge.effective && (!target.params.filmEdge.effective || target.params.filmEdge.format != applied.params.filmEdge.format) {
            result.geometry = Session.gateFramed(applied.geometry, format: applied.params.filmEdge, imageSize: size)
        } else if !applied.params.filmEdge.effective && target.params.filmEdge.effective {
            result.geometry = target.heldCrop ?? Session.unheld(target.geometry)
        }
        var params = Session.resolvedFilmEdge(result.params, geometry: result.geometry, shooting: shooting, stock: stock)
        let physical = Session.recalculateEffectsAfterCrop
            ? CGSize(width: size.width * result.geometry.crop.width, height: size.height * result.geometry.crop.height) : size
        let aspect = max(physical.width, physical.height) / max(1, min(physical.width, physical.height))
        let scale = max(size.width, size.height) / max(1, max(physical.width, physical.height))
        params.filmFormatMM = Session.filmFormatMM(side: FilmSide(rawValue: params.filmSide) ?? .short,
            sideLengthMM: params.sideLengthMM, aspect: aspect, cropScale: scale)
        params.dateBack.camera = params.filmEdge.effective ? params.filmEdge.format
            : Session.dateBackCamera(longMM: params.filmFormatMM, shortMM: params.filmFormatMM / aspect)
        let cut = result.geometry.outputSize(for: size)
        params.dateBack.frameScale = max(cut.width, cut.height) / max(1, max(size.width, size.height))
        result.params = params
        return result
    }

    @MainActor static func previewImage(texture: MTLTexture, adjustments: Adjustments, device: MTLDevice, geometry: Geometry = .default) -> CGImage? {
        guard let renderer = Renderer(device: device) else { return nil }
        let size = CGSize(width: 240, height: 180)
        renderer.setLive(texture)
        renderer.geometry = geometry
        renderer.layer2 = adjustments.uniforms
        renderer.hsl = adjustments.colorUniforms
        renderer.setCurves(adjustments.curves)
        renderer.viewport.backingScale = 1
        renderer.viewport.resize(viewport: size, image: CGSize(width: texture.width, height: texture.height))
        renderer.viewport.fit()
        return renderer.renderOffscreen(size: size, backingScale: 1)?.makeCGImage()
    }
}
