import SwiftUI

struct ScratchSection: View {
    @Bindable var session: Session
    static let key = "scratches"
    private var settings: ScratchSettings { session.params.scratches }
    private var available: Bool { settings.available(on: session.params.filmEdge) }

    var body: some View {
        PanelSection(L("Scratches", zh: "划痕"), key: Self.key, initiallyExpanded: false,
                     action: SectionAction(help: L("Reset scratches", zh: "重置划痕")) {
                         var p = session.params
                         p.scratches = ScratchSettings()
                         session.params = p
                     },
                     note: settings.active ? nil : L(.edgeOff), toggle: bind(\.active),
                     toggleHelp: L("Fine wear on the film border", zh: "在片边添加细微磨损")) {
            RailRows {
                amount(L("Long lines", zh: "长划痕"), \.longLines, zero: 0.4)
                amount(L("Short scuffs", zh: "短擦痕"), \.shortScuffs, zero: 0.25)
                amount(L("Strength", zh: "强度"), \.strength, zero: 0.35)
                HStack(spacing: 0) {
                    RowLabel(L("Pattern", zh: "样式"))
                    DiceButton(title: L("Another", zh: "换一组"),
                               help: L("Change scratches without changing the film edge", zh: "只更换划痕分布"), fill: true) {
                        var p = session.params
                        p.scratches.seed = FilmEdgeSection.another(than: settings.seed, in: ScratchSettings.seedRange)
                        session.params = p
                    }
                }
                .frame(height: Theme.Metric.rowHeight)
            }
            .rowEnabled(settings.active && available,
                        because: available ? L("Switch Scratches on in its header.", zh: "先在标题栏开启划痕。")
                            : L("Enable 135 or half-frame Film Edge first.", zh: "需先开启 135 或半格片边。"))
            Text(available ? L("Film border only. Fine parallel lines and sparse scuffs; no dust. Thickness is fixed in film units.",
                   zh: "仅作用于片边：细长划痕与少量局部擦痕。粗细随胶片尺寸缩放，暂不包含灰尘。")
                : L("Enable 135 or half-frame Film Edge first.", zh: "需先开启 135 或半格片边，才能显示划痕。"))
                .font(Theme.Font.caption).foregroundStyle(Theme.Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private func amount(_ title: String, _ key: WritableKeyPath<ScratchSettings, Double>, zero: Double) -> some View {
        ScrubSlider(label: title, value: bind(key), range: ScratchSettings.amountRange,
                    zero: zero, snap: 0.01, format: { String(format: "%.0f%%", $0 * 100) })
    }
    private func bind<V>(_ key: WritableKeyPath<ScratchSettings, V>) -> Binding<V> {
        Binding(get: { session.params.scratches[keyPath: key] }, set: { value in
            var p = session.params; p.scratches[keyPath: key] = value; session.params = p
        })
    }
}
