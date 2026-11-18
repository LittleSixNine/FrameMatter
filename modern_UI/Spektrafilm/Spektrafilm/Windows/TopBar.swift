//  File, canvas and viewing actions shared by the inspector tabs.

import SwiftUI

struct TopBar: View {
    @Bindable var session: Session

    var body: some View {
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
            // The empty middle of the bar is the window's drag surface: the
            // titlebar is hidden, and this is where a toolbar would be.
            WindowDragHandle().frame(minWidth: 8, maxWidth: .infinity)
            transferButton(importing: true, title: L("Import", zh: "导入"), help: L(.helpOpen) + " (⌘O)") { session.openPanel() }
            transferButton(importing: false, title: L("Export", zh: "导出"), help: L(.helpExport) + " (⌘E)", disabled: session.selection == nil) {
                session.showExport = true
            }
            .padding(.leading, Theme.Metric.barIconGap)
            Spacer().frame(width: 12)
        }
        .frame(height: Theme.Metric.topBarHeight)
        .barCard()
        // The whole bar is a window drag surface behind its controls: with the
        // titlebar hidden this row *is* where a titlebar would be.
        .background(WindowDragHandle())
    }

    private var statusText: String {
        // The service cannot report real progress: a render call does not
        // return until it is finished and the transport is single-flight, so
        // there is nothing to poll. Elapsed time is what is actually known.
        guard session.working else { return session.status }
        return String(format: "%@ · %.1f s", session.status, session.workSeconds)
    }

    private func transferButton(importing: Bool, title: String, help: String, disabled: Bool = false,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                PhotoTransferIcon(importing: importing).stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 24, height: 24)
                Text(title).font(Theme.Font.caption)
            }
            .foregroundStyle(disabled ? Theme.secondaryText : Theme.text)
            .padding(.horizontal, 8).frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(title)
        .help(help)
    }
}

private struct PhotoTransferIcon: Shape {
    let importing: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let x: CGFloat = importing ? 8 : 2
        p.addRoundedRect(in: CGRect(x: x, y: 3, width: 14, height: 18), cornerSize: CGSize(width: 2, height: 2))
        p.move(to: CGPoint(x: x + 3, y: 17)); p.addLines([CGPoint(x: x + 7, y: 13), CGPoint(x: x + 11, y: 17)])
        let tip: CGFloat = importing ? 12 : 22
        p.move(to: CGPoint(x: tip - 10, y: 10)); p.addLine(to: CGPoint(x: tip, y: 10))
        p.move(to: CGPoint(x: tip - 4, y: 6)); p.addLines([CGPoint(x: tip, y: 10), CGPoint(x: tip - 4, y: 14)])
        return p.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
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

