// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
// Applies only to FrameMatter contributions; upstream notices are retained. See COPYRIGHT.txt.

// Grain controls expose Spektrafilm's existing density-stage model unchanged.
import SwiftUI

struct GrainSection: View {
    @Bindable var session: Session
    static let key = "grain"

    private var active: Binding<Bool> {
        Binding(get: { session.params.grainActive },
                set: { var p = session.params; p.grainActive = $0; session.params = p })
    }

    var body: some View {
        PanelSection(L(.filmGrain), key: Self.key, initiallyExpanded: false,
                     action: SectionAction(help: L("Reset grain parameters", zh: "重置颗粒参数")) {
                         var p = session.params
                         p.grainActive = true
                         p.effects.resetGrain()
                         session.params = p
                     },
                     menu: { AnyView(modelMenu) },
                     note: session.params.grainActive ? nil : L(.edgeOff),
                     toggle: active,
                     toggleHelp: L("Add grain to the negative", zh: "为负片添加颗粒")) {
            RailRows {
                ScrubSlider(label: L(.filmGrainStrength), value: effect(\.grain),
                            range: EffectStrengths.grainRange, zero: 1, snap: 0.25,
                            format: { String(format: "%.2f", $0) })
                ScrubSlider(label: L(.grainParticleArea), value: effect(\.grainParticleAreaUM2),
                            range: EffectStrengths.grainParticleAreaRange, zero: 0.2, snap: 0.05,
                            format: { String(format: "%.2f", $0) })
                    .help(L("Particle area in µm². Larger particles also change grain strength; film format stays unchanged.",
                            zh: "粒子面积，单位 µm²。面积变大也会改变颗粒强度；胶片画幅保持不变。"))
                ScrubSlider(label: L(.grainSoftness), value: effect(\.grainBlur),
                            range: EffectStrengths.grainBlurRange, zero: 0.65, snap: 0.05,
                            format: { String(format: "%.2f", $0) })
                    .help(L("Spektrafilm's grain-stage Gaussian sigma in pixels. Also softens image detail; preview and full resolution can look different.",
                            zh: "Spektrafilm 颗粒阶段的高斯模糊标准差，单位 px。也会柔化图像细节；预览与原始分辨率的观感可能不同。"))
            }
            .rowEnabled(session.params.grainActive,
                        because: L("Switch Grain on in its header.", zh: "先在标题栏开启颗粒。"))
        }
    }

    private var modelMenu: some View {
        Toggle(L(.helpSubLayerGrain), isOn: session.params.filmIsMonochrome ? .constant(false) : effect(\.grainLayered))
            .disabled(!session.params.grainActive || session.params.filmIsMonochrome)
    }

    private func effect<V>(_ kp: WritableKeyPath<EffectStrengths, V>) -> Binding<V> {
        Binding(get: { session.params.effects[keyPath: kp] },
                set: { var p = session.params; p.effects[keyPath: kp] = $0; session.params = p })
    }
}
