// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
// Applies only to FrameMatter contributions; upstream notices are retained. See COPYRIGHT.txt.

import SwiftUI

struct AgingTextureSection: View {
    @Bindable var session: Session
    static let key = "agingTextures"
    private var settings: AgingTextureSettings { session.params.agingTextures }

    var body: some View {
        PanelSection(L("Aging Textures", zh: "做旧纹理"), key: Self.key, initiallyExpanded: false,
                     action: SectionAction(help: L("Reset aging texture", zh: "重置做旧纹理")) {
                         var p = session.params; p.agingTextures = AgingTextureSettings(); session.params = p
                     }, toggle: bind(\.active),
                     toggleHelp: L("Whole-frame scuffs, scratches and wear", zh: "整幅擦痕、划伤和磨损")) {
            RailRows {
                HStack(spacing: 0) {
                    RowLabel(L("Style", zh: "款式"))
                    Picker(L("Aging style", zh: "做旧款式"), selection: bind(\.material)) {
                        ForEach(AgingTextureMaterial.allCases, id: \.self) { material in
                            Text(material.title).tag(material)
                        }
                    }.labelsHidden().pickerStyle(.menu)
                }.frame(height: Theme.Metric.rowHeight)
                ScrubSlider(label: L("Strength", zh: "强度"), value: bind(\.strength), range: 0...1,
                            zero: 0.5, snap: 0.01, format: { String(format: "%.0f%%", $0 * 100) })
                HStack(spacing: 0) {
                    RowLabel(L("Mirror", zh: "镜像"))
                    Picker(L("Texture mirror", zh: "纹理镜像"), selection: bind(\.flip)) {
                        ForEach(WideLeakFlip.allCases, id: \.self) { flip in Text(flip.title).tag(flip) }
                    }.labelsHidden().pickerStyle(.menu)
                }.frame(height: Theme.Metric.rowHeight)
                HStack(spacing: 0) {
                    RowLabel(L("Rotation", zh: "旋转"))
                    Picker(L("Texture rotation", zh: "纹理旋转"), selection: bind(\.rotation)) {
                        ForEach(0..<4) { turn in Text("\(turn * 90)°").tag(turn) }
                    }.labelsHidden().pickerStyle(.menu)
                }.frame(height: Theme.Metric.rowHeight)
            }
            .rowEnabled(settings.active && !session.params.digitalIntermediate,
                        because: session.params.digitalIntermediate
                            ? L("Unavailable in Digital Intermediate.", zh: "数字中间片模式不应用做旧纹理。")
                            : L("Switch Aging Textures on in its header.", zh: "先在标题栏开启做旧纹理。"))
            Text(!settings.material.available
                 ? L("Texture unavailable. Restore the local research assets.", zh: "素材缺失，请恢复本地做旧素材。")
                 : L("Whole-frame wear; independent of dust and Film Edge. Portraits align automatically before rotation.",
                     zh: "整幅做旧，独立于灰尘和片边；竖图先自动转向，再应用旋转。"))
                .font(Theme.Font.caption).foregroundStyle(Theme.Ink.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func bind<V>(_ key: WritableKeyPath<AgingTextureSettings, V>) -> Binding<V> {
        Binding(get: { session.params.agingTextures[keyPath: key] }, set: { value in
            var p = session.params; p.agingTextures[keyPath: key] = value; session.params = p
        })
    }
}
