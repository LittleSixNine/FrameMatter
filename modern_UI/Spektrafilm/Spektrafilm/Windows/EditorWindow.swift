//  The filmstrip and toolbar span the editor. Only the inspector changes width.

import SwiftUI
import UniformTypeIdentifiers

struct EditorWindow: View {
    @Bindable var session: Session
    /// Opening the export page's scene. A `Window` scene is addressed by its
    /// id from anywhere with the environment, which is how this window hands
    /// the request on without either of them owning the other.
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // One layout. The window used to switch to a `BrowseView` worklist
        // whenever a folder was open and no frame chosen; that page is gone
        // and the filmstrip is the only list. Opening a folder still develops
        // nothing until a frame is picked — see `Session.unloadSelection()`.
        printLayout
        // A batch export writes whatever frame is open, with whatever it is
        // set to (`Session.batchExporting`): the editor is look-only until the
        // run finishes, so a slider or a click cannot land mid-file.
        .allowsHitTesting(!session.batchExporting)
        .background(Theme.ground)
        // Above the browse/print switch, so the buttons are re-placed in
        // either state and the observer outlives every card that can fold.
        // See `TrafficLightAlignment` for why that matters.
        .background(
            TrafficLightAlignment(centreY: Theme.Metric.trafficLightCentreY,
                                  leading: Theme.Metric.trafficLightLeading)
                .frame(width: 0, height: 0)
        )
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onExitCommand {
            if session.tool == .crop { session.cancelCrop() }
            else if !session.endPlacement(), !session.rightCollapsed {
                session.toggleInspector(session.inspectorTab)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
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
        // The export page is a window of its own (RFC-018 §6): with a
        // per-destination transform the canvas is a Display P3 proof of a
        // different thing, so the two are worth looking at side by side, which
        // a modal sheet over the editor forbids. `showExport` is unchanged and
        // still means "an export was asked for" — it is now consumed here
        // rather than presented, so ⌘E, the editor's menu item and the
        // toolbar's button all keep working without knowing the page moved.
        .onChange(of: session.showExport) { _, wanted in
            guard wanted else { return }
            session.showExport = false
            openWindow(id: ExportWindowID.scene)
        }
    }

    @State private var rightWidth = PanelWidthStore(name: "editor.right",
                                                    range: Theme.Metric.rightPanelRange)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var printLayout: some View {
        let width = session.snapshotPanelWidths ? rightWidth.range.standard : rightWidth.width
        return VStack(spacing: 0) {
            TopBar(session: session)
            Hairline(tier: .region)
            HStack(spacing: 0) {
                CanvasArea(session: session)
                RightPanel(session: session)
                    .environment(\.colorBalanceWidth, ColorBalanceLayout.interior(panelWidth: width))
                    .frame(width: width)
                    .overlay(alignment: .leading) {
                        PanelResizeHandle(side: .leadingEdge, range: rightWidth.range, width: $rightWidth.width)
                    }
                    .overlay(alignment: .leading) { VerticalHairline().allowsHitTesting(false) }
                    .frame(width: session.rightCollapsed ? 0 : width, alignment: .trailing)
                    .clipped()
                    .allowsHitTesting(!session.rightCollapsed)
                    .accessibilityHidden(session.rightCollapsed)
                InspectorTabs(session: session)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: session.rightCollapsed)
            if !session.filmstripCollapsed {
                Hairline(tier: .region)
                Filmstrip(session: session)
                    .frame(height: Theme.Metric.filmstripHeight)
                    .transition(.move(edge: .bottom))
            }
        }
    }
}

/// The centre: the Metal view (or, in snapshot mode, an offscreen render of
/// it) with the four collapse tabs on its edges.
struct CanvasArea: View {
    @Bindable var session: Session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var showsNavigator: Bool {
        session.selection != nil && !session.zoomLocked && session.viewportSnapshot.imageOverflowsCanvas
    }
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        ZStack {
            if snapshotMode {
                SnapshotCanvas(session: session)
            } else {
                MetalCanvasView(host: session)
            }
            // Handles, thirds grid and the straighten line. The shader does
            // the dimming; this does the lines, which want to stay crisp.
            if session.tool == .crop && !snapshotMode {
                CropOverlay(session: session)
            } else if FeatureFlags.masks && !snapshotMode && session.selectedMask != nil {
                MaskOverlay(session: session)
            }
            // Above both: the split's handle is a control, and it is the only
            // overlay that takes the mouse.
            //
            // Drawn in snapshot mode too, unlike the other two. The shader
            // puts the split at `ouv.x`, this puts the line at a view point,
            // and the two arithmetics are written in different files — so a
            // capture where the line does not sit on the seam is the only
            // thing that catches them disagreeing.
            CompareOverlay(session: session)
            // A pair's own marks: the + on an empty hole, the picked hole's
            // frame, the frame picker.
            if session.pair != nil { PairOverlay(session: session) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(PairDrop(session: session))
        // Everything in this stack is positioned in **view coordinates**, and
        // a view coordinate at high zoom is off the canvas: the crop frame's
        // corners, its grips and the mask handles all ran past the canvas edge
        // and were painted over the side panels and the toolbar. SwiftUI does
        // not clip by default; the canvas is the one place that must.
        //
        // Not the Metal view's problem — a `CAMetalLayer` cannot draw outside
        // itself (which is why a zoomed picture looks *cut off* at the canvas
        // edge rather than spilling, and why the crop tool's view is fitted to
        // the picture: `Renderer.fitRotatedPhoto`). This is the overlay half.
        .clipped()
        // **One edge, not three.** The left and right tabs are gone: the
        // drawing folds a rail with the `sidebar.left` / `sidebar.right`
        // button in that rail's own header, and a second control that does
        // the same thing is a control that will disagree with the first about
        // being there. The bottom one is untouched — "except the bottom
        // gallery view remains unchanged" — and is still the pill that
        // appears when the pointer comes near the canvas's lower edge.
        .overlay(alignment: .bottom) { HoverEdgeTab(edge: .bottom, collapsed: $session.filmstripCollapsed) }
        .overlay(alignment: .topLeading) {
            ZStack {
                if showsNavigator {
                    NavigatorSection(session: session)
                        .id(session.selection)
                        .padding(CanvasBadges.inset)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: showsNavigator)
            .allowsHitTesting(showsNavigator)
        }
        .overlay(alignment: .topTrailing) {
            // The finished picture's histogram heads the stack: it describes
            // the pixels on this canvas, as the tier badge under it does, so
            // it moved here from the right rail. No ground and no grid -- it
            // sits on the surround like the text below it. Not a hit target.
            VStack(alignment: .trailing, spacing: CanvasBadges.spacing) {
                if session.selection != nil {
                    HistogramPlot(bins: session.histogram, channels: [.rgb],
                                  showGrid: false, showGround: false)
                        .frame(width: CanvasBadges.histogram.width,
                               height: CanvasBadges.histogram.height)
                        // A soft black haze, not a plate: blurred past its
                        // own edge so there is no outline to read, and dark
                        // enough that the lines hold over a white print.
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.black.opacity(0.45))
                                .padding(-6)
                                .blur(radius: 10)
                        }
                }
                ForEach(session.canvasBadges, id: \.self) { badge($0) }
            }
            .padding(CanvasBadges.inset)
            .allowsHitTesting(false)
        }
        // Contract §2's "a visible error rather than a blank canvas". Centred
        // and opaque, not a corner badge: the app is not going to render, and
        // a caption the user has to go looking for would leave them staring at
        // an empty canvas deciding the app is broken — which it is, but not in
        // a way they can act on without being told.
        .overlay {
            if let why = session.serviceBlocked {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(Theme.accent)
                    Text(L("The render service cannot be used", zh: "渲染服务无法使用"))
                        .font(Theme.Font.sectionTitle).foregroundStyle(Theme.text)
                    Text(why)
                        .font(Theme.Font.caption).foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center).frame(maxWidth: 380)
                    Button(L("Restart the render service", zh: "重启渲染服务")) { session.restartService() }
                        .buttonStyle(.plain).font(Theme.Font.caption).foregroundStyle(Theme.accent)
                        .padding(.top, 2)
                }
                .padding(20)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 8)
            }
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 6) {
                if let warning = session.stockWarning {
                    Text(warning).font(Theme.Font.caption).foregroundStyle(Theme.text).lineLimit(2)
                        .padding(6).background(Theme.card.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                        .frame(maxWidth: 360, alignment: .leading)
                }
                CanvasZoomControls(session: session)
            }
            .padding(CanvasBadges.inset)
        }
        .overlay(alignment: .bottomTrailing) {
            OriginalPreviewButton(session: session)
                .padding(CanvasBadges.inset)
        }
    }

    /// Plain text, no capsule. The shadow is not a plate: it is what keeps a
    /// white word readable where the picture under the corner is white too.
    private func badge(_ text: String) -> some View {
        Text(text).font(Theme.Font.caption).foregroundStyle(Theme.text)
            .frame(height: CanvasBadges.height)
            .shadow(color: .black.opacity(0.6), radius: 1.5)
    }
}

private struct OriginalPreviewButton: View {
    @Bindable var session: Session
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        let available = session.selection != nil
        let help = L("Hold to view original", zh: "按住查看原图")
        Label(L(.actionOriginal), systemImage: "eye")
            .font(Theme.Font.caption)
            .foregroundStyle(session.showingOriginal ? Theme.accent : Theme.text)
            .padding(.horizontal, 9)
            .frame(height: 32)
            .background(Theme.card.opacity(0.92), in: Capsule())
            .contentShape(Capsule())
            .overlay {
                OriginalPressTarget(session: session)
                    .accessibilityHidden(true)
            }
            .onChange(of: activeState) { _, state in
                if state == .inactive { session.holdOriginalButton(false) }
            }
            .onDisappear { session.holdOriginalButton(false) }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(L(.actionOriginal))
            .accessibilityValue(session.showingOriginal ? L(.actionOriginal) : L(.actionDeveloped))
            .accessibilityAction { session.holdOriginalButton(!session.showingOriginal) }
            .disabled(!available)
            .rowEnabled(available)
            .help(help)
    }
}

private struct OriginalPressTarget: NSViewRepresentable {
    let session: Session

    final class Target: NSView {
        weak var session: Session?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { session?.holdOriginalButton(true) }
        override func mouseUp(with event: NSEvent) { session?.holdOriginalButton(false) }
    }

    func makeNSView(context: Context) -> Target { Target() }
    func updateNSView(_ target: Target, context: Context) { target.session = session }
}

/// Snapshot stand-in: the renderer draws offscreen into an image at the
/// canvas's real size, so a capture shows the real render path.
///
/// It takes over `Renderer.needsDraw`, which in the running app is the
/// `MTKView`'s `scheduleDraw`. That is the whole point: the previous version
/// re-rendered on a hand-written list of properties — `previewSoft`,
/// `histogram`, `zoomPercent`, `detailTier`, `detailPending` — and so was
/// blind to every state that invalidates the canvas without touching one of
/// them. Masks were the case that found it: `--mask` captured an image with
/// no mask in it, and the feature was fine. Anything the renderer considers a
/// reason to redraw is now a reason to re-capture, with no list to maintain.
struct SnapshotCanvas: View {
    @Bindable var session: Session
    @State private var image: CGImage?
    @State private var revision = 0
    @State private var rendering = false
    /// The scene's own window does not draw. It is up too in a snapshot run,
    /// with a stand-in of its own at another size; the two
    /// share one renderer, and whichever appeared last took its redraw
    /// callback and its viewport -- when that was the scene's, the capture
    /// was of a canvas that never drew, and of a zoom fitted to another view.
    @Environment(\.snapshotCapture) private var capture

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image { Image(decorative: image, scale: 2).resizable() } else { Theme.ground }
            }
            .onAppear { if capture { session.renderer.needsDraw = { revision &+= 1 } } }
            .onChange(of: geo.size, initial: true) { _, size in render(size) }
            .onChange(of: revision) { _, _ in render(geo.size) }
        }
    }

    private func render(_ size: CGSize) {
        guard capture, size.width > 1, size.height > 1 else { return }
        // A render can invalidate the canvas again (the detail tier swaps a
        // texture in), and that arrives here as another revision. One level
        // is enough; re-entering would be a loop.
        guard !rendering else { return }
        rendering = true
        defer { rendering = false }
        session.renderer.viewport.backingScale = 2
        session.renderer.viewport.resize(viewport: size)
        session.viewportChanged()
        image = session.renderer.renderOffscreen(size: size, backingScale: 2)?.makeCGImage()
    }
}

private struct SnapshotModeKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var snapshotMode: Bool { get { self[SnapshotModeKey.self] } set { self[SnapshotModeKey.self] = newValue } }
    /// False in the one window a snapshot run is not taken of (see `SnapshotCanvas`).
    var snapshotCapture: Bool { get { self[SnapshotCaptureKey.self] } set { self[SnapshotCaptureKey.self] = newValue } }
}

private struct SnapshotCaptureKey: EnvironmentKey { static let defaultValue = true }

/// The window's drag handle. `.windowStyle(.hiddenTitleBar)` removes the
/// titlebar a window is normally dragged by, and the strip reserved for the
/// traffic lights is SwiftUI content, which would otherwise eat the gesture.
/// `performDrag` hands it to the window server the way the real titlebar does.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { window?.performZoom(nil) } else { window?.performDrag(with: event) }
        }
    }
}
