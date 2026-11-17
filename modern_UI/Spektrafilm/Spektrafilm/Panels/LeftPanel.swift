// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
// Applies only to FrameMatter contributions; upstream notices are retained. See COPYRIGHT.txt.

import SwiftUI

struct PanelIconButton: View {
    let systemImage: String
    var help: String = ""
    var active = false
    /// A glyph that cannot be used is greyed, like every other non-selectable
    /// control in the app (PRD; `View.rowEnabled(_:)`).
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: Theme.Metric.panelIcon, weight: .regular))
                .foregroundStyle(active ? Theme.accent : Theme.text)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rowEnabled(enabled)
        .help(help)
    }
}

struct VerticalEllipsis: View {
    var body: some View {
        VStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in Circle().fill(Theme.text).frame(width: 3, height: 3) } }
    }
}

extension View {
    // `panelCard()` — a rounded card on a visible ground — used to live here
    // for the export page and the Browse grid. Both are gone: the grid was
    // removed with the import page, and the export page is three flush rails
    // like the editor. Nothing in the app is a floating card now, so the
    // modifier is not kept "just in case" — a second surface treatment that
    // nothing uses is how the two pages drifted apart in the first place.

    /// A rail, or the filmstrip: flush with the window and square, because
    /// the 2026-09-17 drawing separates regions with a hairline rather than
    /// with a gap and a radius.
    func railCard() -> some View {
        self.background(Theme.card)
    }

    /// The one thing that still floats: the tool bar's pill.
    func barCard() -> some View {
        self.background(Theme.card,
                        in: RoundedRectangle(cornerRadius: Theme.Metric.barRadius, style: .continuous))
    }
}
