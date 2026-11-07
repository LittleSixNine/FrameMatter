import SwiftUI

struct LightLeakSection: View {
    @Bindable var session: Session
    static let key = "light-leaks"
    private var settings: LightLeakSettings { session.params.lightLeaks }
    private var available: Bool { settings.available(on: session.params.filmEdge) }

    var body: some View {
        PanelSection(L("Light Leaks", zh: "漏光"), key: Self.key, initiallyExpanded: false,
                     action: SectionAction(help: L("Reset light leaks", zh: "重置漏光")) {
                         var p = session.params; p.lightLeaks = LightLeakSettings(); session.params = p
                     }, note: settings.active ? nil : L(.edgeOff), toggle: bind(\.active),
                     toggleHelp: L("Perforation light independent of scratches and dust", zh: "独立于划痕与灰尘的齿孔漏光")) {
            RailRows {
                HStack(spacing: 0) {
                    RowLabel(L("Style", zh: "样式"))
                    Picker(L("Light leak style", zh: "漏光样式"), selection: bind(\.style)) {
                        ForEach(LightLeakStyle.allCases, id: \.self) { style in
                            Text(style.title).tag(style)
                        }
                    }.labelsHidden().pickerStyle(.menu)
                }.frame(height: Theme.Metric.rowHeight)
                amount(L("Strength", zh: "强度"), \.strength, zero: 0)
                if settings.style == .rim {
                    amount(L("Rim coverage", zh: "亮边覆盖"), \.rimCoverage, zero: 0)
                        .help(L("0% keeps a one-sided rim; 100% extends around the hole.", zh: "0% 保留单侧亮边，100% 扩展至整圈。"))
                    amount(L("Softness", zh: "柔化"), \.rimSoftness, zero: 0)
                        .help(L("Retain the bright core while softening outward.", zh: "保留贴孔亮芯，同时向周围柔开。"))
                }
                amount(L("Spread", zh: "扩散范围"), \.spread, zero: 0.5)
                HStack(spacing: 0) {
                    RowLabel(L("Pattern", zh: "图案"))
                    DiceButton(title: L("Another", zh: "换一组"),
                               help: L("Change only this light leak style's direction and details", zh: "只更换当前漏光样式的主方向和局部细节"), fill: true) {
                        var p = session.params
                        p.lightLeaks.seed = FilmEdgeSection.another(than: settings.seed, in: ScratchSettings.seedRange)
                        session.params = p
                    }
                }.frame(height: Theme.Metric.rowHeight)
            }
            .rowEnabled(settings.active && available,
                        because: available ? L("Switch Light Leaks on in its header.", zh: "先在标题栏开启漏光。")
                        : L("Enable 135, half-frame or full-width Film Edge first.", zh: "需先开启 135、半格或全宽片边。"))
            Text(L("Each style remembers its settings and pattern. All holes share a light direction with small local variations. Wide light may reach the picture.",
                   zh: "两种样式分别记住参数与图案。各孔主方向一致，局部略有差异；宽柔光可进入画幅。"))
                .font(Theme.Font.caption).foregroundStyle(Theme.Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private func amount(_ title: String, _ key: WritableKeyPath<LightLeakSettings, Double>, zero: Double) -> some View {
        ScrubSlider(label: title, value: bind(key), range: ScratchSettings.amountRange,
                    zero: zero, snap: 0.01, format: { String(format: "%.0f%%", $0 * 100) })
    }
    private func bind<V>(_ key: WritableKeyPath<LightLeakSettings, V>) -> Binding<V> {
        Binding(get: { session.params.lightLeaks[keyPath: key] }, set: { value in
            var p = session.params; p.lightLeaks[keyPath: key] = value; session.params = p
        })
    }
}
