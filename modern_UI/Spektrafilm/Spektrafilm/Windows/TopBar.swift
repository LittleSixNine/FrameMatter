//  File, canvas and viewing actions shared by the inspector tabs.

import SwiftUI

struct TopBar: View {
    @Bindable var session: Session

    var body: some View {
        HStack(spacing: 0) {
            if session.tool == .crop {
                HStack(spacing: 0) {
                    titleContent
                    dragSpace
                }
                .frame(minWidth: 0, maxWidth: .infinity)
                cropActions
                    .fixedSize()
                    .padding(.horizontal, 8)
                HStack(spacing: 0) {
                    dragSpace
                    exportButton.padding(.trailing, 12)
                }
                .frame(minWidth: 0, maxWidth: .infinity)
            } else {
                titleContent
                dragSpace
                exportButton.padding(.trailing, 12)
            }
        }
        .frame(height: Theme.Metric.topBarHeight)
        .barCard()
        // The custom title bar doubles as the window's drag surface.
        .background(WindowDragHandle())
    }

    private var dragSpace: some View {
        WindowDragHandle().frame(minWidth: 8, maxWidth: .infinity)
    }

    private var titleContent: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: Theme.Metric.barLeadingWithButtons)
            Image("BootTitle")
                .resizable()
                .scaledToFit()
                .frame(width: 132, height: 24)
                .padding(.leading, 8)
                .accessibilityLabel("FrameMatter")
            if session.working {
                ProgressView().controlSize(.small).scaleEffect(0.7).padding(.leading, 18)
            }
            Text(statusText)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(statusText)
                .padding(.leading, 12)
                // First call on the bar's spare width, ahead of the drag
                // surface. Outermost, or the HStack never sees it.
                .layoutPriority(1)
            if !session.serviceReady, session.selection != nil {
                Button(L(.actionRestart)) { session.restartService() }
                    .buttonStyle(.plain).font(Theme.Font.caption).foregroundStyle(Theme.accent)
                    .padding(.leading, 8)
                    .help("The render service is not running. Start it again.")
            }
        }
    }

    private var cropActions: some View {
        HStack(spacing: 6) {
            Button { session.cancelCrop() } label: {
                Text(L("Cancel", zh: "取消"))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Color(hex: 0x383837), in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.rule, lineWidth: 1)
                            .allowsHitTesting(false)
                    }
            }
            .accessibilityIdentifier("toolbar.crop.cancel")
            .help(L("Cancel Crop", zh: "取消裁剪") + " (Esc)")

            Button { session.commitCrop() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark").accessibilityHidden(true)
                    Text(L("Apply Crop", zh: "确认裁剪"))
                }
                .foregroundStyle(Color(hex: 0x252016))
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6))
            }
            .accessibilityIdentifier("toolbar.crop.apply")
            .help(L("Apply Crop", zh: "确认裁剪") + " (↩)")
        }
        .buttonStyle(.plain)
        .font(Theme.Font.body)
    }

    private var statusText: String {
        // The service cannot report real progress: a render call does not
        // return until it is finished and the transport is single-flight, so
        // there is nothing to poll. Elapsed time is what is actually known.
        guard session.working else { return session.status }
        return String(format: "%@ · %.1f s", session.status, session.workSeconds)
    }

    private var exportButton: some View {
        let title = L("Export", zh: "导出")
        return Button { session.showExport = true } label: {
            HStack(spacing: 6) {
                PhotoTransferIcon(importing: false)
                    .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 24, height: 24)
                Text(title).font(Theme.Font.body)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(Color(hex: 0xA82E13), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(session.selection == nil)
        .opacity(session.selection == nil ? 0.45 : 1)
        .accessibilityLabel(title)
        .accessibilityIdentifier("toolbar.export")
        .help(L(.helpExport) + " (⌘E)")
    }
}

struct PhotoTransferIcon: Shape {
    let importing: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 3.5, y: 13.6))
        p.addLine(to: CGPoint(x: 3.5, y: 18.5))
        p.addQuadCurve(to: CGPoint(x: 5, y: 20), control: CGPoint(x: 3.5, y: 20))
        p.addLine(to: CGPoint(x: 19, y: 20))
        p.addQuadCurve(to: CGPoint(x: 20.5, y: 18.5), control: CGPoint(x: 20.5, y: 20))
        p.addLine(to: CGPoint(x: 20.5, y: 13.6))

        let tip: CGFloat = importing ? 14.5 : 3.5
        let base: CGFloat = importing ? 3.5 : 14.5
        let shoulder: CGFloat = importing ? 10.75 : 7.25
        p.move(to: CGPoint(x: 12, y: base))
        p.addLine(to: CGPoint(x: 12, y: tip))
        p.move(to: CGPoint(x: 8.25, y: shoulder))
        p.addLine(to: CGPoint(x: 12, y: tip))
        p.addLine(to: CGPoint(x: 15.75, y: shoulder))
        return p.applying(CGAffineTransform(a: rect.width / 24, b: 0, c: 0, d: rect.height / 24,
                                            tx: rect.minX, ty: rect.minY))
    }
}

struct CanvasZoomControls: View {
    @Bindable var session: Session

    var body: some View {
        HStack(spacing: 3) {
            zoomPill.rowEnabled(!session.zoomLocked)
            iconButton("minus.magnifyingglass", L(.helpZoomOut) + " (⌘−)", disabled: session.zoomLocked) { session.zoomStep(-1) }
            iconButton("plus.magnifyingglass", L(.helpZoomIn) + " (⌘+)", disabled: session.zoomLocked) { session.zoomStep(1) }
            Rectangle().fill(Theme.secondaryText.opacity(0.4)).frame(width: 1, height: 16)
            Button { session.comparing.toggle() } label: {
                BeforeAfterIcon(color: session.comparing ? Theme.accent : Theme.text)
                    .frame(width: Theme.Metric.beforeAfterIcon.width,
                           height: Theme.Metric.beforeAfterIcon.height)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!session.canCompare)
            .opacity(session.canCompare ? 1 : 0.4)
            .accessibilityLabel(L(.helpBeforeAfter))
            .help(L(.helpBeforeAfter) + " (⌥\\)")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Theme.card.opacity(0.92), in: Capsule())
    }

    private var zoomPill: some View {
        Menu {
            Button(L(.helpFit)) { session.zoomToFit() }
            ForEach([0.25, 0.5, 1.0, 2.0, 4.0], id: \.self) { f in
                Button("\(Int(f * 100)) %") { session.zoomTo(fraction: f) }
            }
        } label: {
            // zoomPercent is 0 until an image is on the canvas.
            //
            // **No `Fit ·` prefix.** v3's plate is 41.29 pt and the prefix
            // does not fit in it. Whether the canvas is fitted is still worth
            // knowing, so it is said in the tooltip and by the check mark in
            // this menu rather than by a string that would either truncate
            // the number or size the plate for a case that is usually absent.
            //
            // **Sized to its number** (2026-09-28): the drawing's 41.29 pt is
            // the pill's *minimum*, and "100 %", "1600 %" widen it rather than
            // truncate to "100…".
            Text(session.zoomPercent == 0 ? "—" : "\(session.zoomPercent) %")
                .font(Theme.Font.zoomValue)
                .foregroundStyle(Theme.text)
                .fixedSize()
                .padding(.horizontal, 7)
                .frame(minWidth: Theme.Metric.zoomPill.width, minHeight: Theme.Metric.zoomPill.height,
                       maxHeight: Theme.Metric.zoomPill.height)
                // No outline. The previous drawing stroked this capsule in
                // white; the new one draws it as a plain `.st13` pill, like
                // every other pill in the interface.
                .background(Theme.pill, in: Capsule())
                .contentShape(Capsule())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help(session.isFit ? "Fitted to the window — \(session.zoomPercent) % (⌘0)"
                            : "Zoom — \(session.zoomPercent) %")
    }
}

private func iconButton(_ name: String, _ help: String, disabled: Bool = false,
                        action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: name)
            .font(.system(size: Theme.Metric.toolIcon, weight: .regular))
            .foregroundStyle(disabled ? Theme.text.opacity(0.4) : Theme.text)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .accessibilityLabel(help)
    .help(help)
}

