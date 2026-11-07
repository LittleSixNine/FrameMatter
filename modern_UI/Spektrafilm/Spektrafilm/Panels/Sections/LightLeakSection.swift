// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
// Applies only to FrameMatter contributions; upstream notices are retained. See COPYRIGHT.txt.

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
                     toggleHelp: L("Perforation and wide light, independent of wear", zh: "齿孔和大范围漏光，独立于磨损")) {
            RailRows {
                groupToggle(L("Perforation light", zh: "齿孔漏光"), \.perforationActive)
                RailSubgroup { perforationControls }
                    .rowEnabled(settings.active && settings.perforationActive && available,
                        because: available ? L("Switch perforation light on first.", zh: "先开启漏光总开关和齿孔漏光。")
                        : L("Enable 135, half-frame or full-width Film Edge first.", zh: "需先开启135、半格或全宽片边。"))
                groupToggle(L("Wide light leaks", zh: "大范围漏光"), \.wideActive)
                RailSubgroup { wideControls }
                    .rowEnabled(settings.active && settings.wideActive && !session.params.digitalIntermediate,
                        because: session.params.digitalIntermediate ? L("Wide light is unavailable in Digital Intermediate.", zh: "数字中间片模式暂不支持大范围漏光。")
                        : L("Switch wide light leaks on first.", zh: "先开启漏光总开关和大范围漏光。"))
            }
            Text(settings.wideMaterial.available
                 ? L("Perforation and wide light can overlap. Each remembers its settings. Wide light is natural through 70%, then progressively washes the lit area to white.",
                     zh: "两组漏光可同时开启并分别保存参数。大范围漏光前70%保留自然叠加，超过70%逐渐增强冲白。")
                 : L("Local wide-light textures are missing; prepare and bundle your own assets first.", zh: "本地大范围漏光素材缺失，需先准备并同步素材。"))
                .font(Theme.Font.caption).foregroundStyle(Theme.Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var perforationControls: some View {
        Group {
            HStack(spacing: 0) {
                RowLabel(L("Style", zh: "样式"))
                Picker(L("Light leak style", zh: "漏光样式"), selection: bind(\.style)) {
                    ForEach(LightLeakStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }.labelsHidden().pickerStyle(.menu)
            }.frame(height: Theme.Metric.rowHeight)
            amount(L("Strength", zh: "强度"), \.strength, zero: 0)
            if settings.style == .rim {
                amount(L("Rim coverage", zh: "亮边覆盖"), \.rimCoverage, zero: 0)
                amount(L("Softness", zh: "柔化"), \.rimSoftness, zero: 0)
            }
            amount(L("Spread", zh: "扩散范围"), \.spread, zero: 0.5)
            patternRow {
                var p = session.params
                p.lightLeaks.seed = FilmEdgeSection.another(than: settings.seed, in: ScratchSettings.seedRange)
                session.params = p
            }
        }
    }
    private var wideControls: some View {
        Group {
            HStack(spacing: 0) {
                RowLabel(L("Material", zh: "素材"))
                Picker(L("Wide light material", zh: "大范围漏光素材"), selection: bind(\.wideMaterial)) {
                    ForEach(WideLeakGroup.allCases, id: \.self) { group in
                        Section(group.title) {
                            ForEach(group.materials, id: \.self) { Text($0.title).tag($0) }
                        }
                    }
                }.labelsHidden().pickerStyle(.menu)
            }.frame(height: Theme.Metric.rowHeight)
            amount(L("Strength", zh: "强度"), \.wideStrength, zero: 0.7)
            if settings.wideMaterial.isOnetake {
                HStack(spacing: 0) {
                    RowLabel(L("Flip", zh: "翻转方向"))
                    Picker(L("Texture flip", zh: "素材翻转"), selection: bind(\.wideFlip)) {
                        ForEach(WideLeakFlip.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.labelsHidden().pickerStyle(.menu)
                }.frame(height: Theme.Metric.rowHeight)
            } else {
                HStack(spacing: 0) {
                    RowLabel(L("Direction", zh: "方向"))
                    Picker(L("Entry direction", zh: "入光方向"), selection: bind(\.wideDirection)) {
                        ForEach(WideLeakDirection.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.labelsHidden().pickerStyle(.menu)
                }.frame(height: Theme.Metric.rowHeight)
                amount(L("Intrusion", zh: "侵入范围"), \.wideDepth, zero: 0.28)
                    .disabled(!settings.wideMaterial.usesIntrusion)
                ScrubSlider(label: L("Size", zh: "大小"), value: bind(\.wideScale), range: 0.5...3,
                            zero: 1.2, snap: 0.01, format: { String(format: "%.0f%%", $0*100) })
                amount(L("Softness", zh: "柔化"), \.wideSoftness, zero: 0)
            }
            patternRow {
                var p = session.params
                p.lightLeaks.randomizeWide()
                session.params = p
            }
        }
    }
    private func groupToggle(_ title: String, _ key: WritableKeyPath<LightLeakSettings, Bool>) -> some View {
        HStack {
            RailSubhead(title)
            Spacer()
            Toggle(title, isOn: bind(key)).labelsHidden().toggleStyle(.switch).controlSize(.mini)
        }.frame(height: Theme.Metric.rowHeight).disabled(!settings.active)
    }
    private func patternRow(_ action: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            RowLabel(L("Pattern", zh: "图案"))
            DiceButton(title: L("Another", zh: "换一组"), help: L("Change only this light group's pattern", zh: "只更换当前这组漏光图案"), fill: true, action: action)
        }.frame(height: Theme.Metric.rowHeight)
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
