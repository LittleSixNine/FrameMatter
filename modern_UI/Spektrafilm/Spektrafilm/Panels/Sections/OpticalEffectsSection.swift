import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DiffusionSection: View {
    @Bindable var session: Session
    private func bind<T>(_ key: WritableKeyPath<DiffusionSettings, T>) -> Binding<T> {
        Binding(get: { session.params.diffusion[keyPath: key] }, set: {
            var p = session.params
            p.diffusion[keyPath: key] = $0
            session.params = p
        })
    }
    var body: some View {
        PanelSection(L("Diffusion Filter", zh: "柔光镜"), key: "diffusion", initiallyExpanded: false,
                     toggle: bind(\.active), toggleHelp: L("Enable diffusion filter", zh: "开启柔光镜")) {
            RailRows {
                HStack {
                    RowLabel(L("Filter", zh: "镜片"))
                    Picker(L("Filter", zh: "镜片"), selection: bind(\.family)) {
                        Text(L("Black Pro-Mist", zh: "黑柔")).tag("black_pro_mist")
                        Text(L("White Pro-Mist", zh: "白柔")).tag("pro_mist")
                        Text("Glimmerglass").tag("glimmerglass")
                        Text("CineBloom").tag("cinebloom")
                    }.labelsHidden().pickerStyle(.menu)
                }
                ScrubSlider(label: L("Strength", zh: "强度"), value: bind(\.strength), range: 0...1, zero: 0.5, snap: 0.01)
                ScrubSlider(label: L("Spread", zh: "扩散"), value: bind(\.scale), range: 0.25...4, zero: 1, snap: 0.05)
            }.disabled(!session.params.diffusion.active)
        }
    }
}

struct DoubleExposureSection: View {
    @Bindable var session: Session
    private func bind<T>(_ key: WritableKeyPath<DoubleExposureSettings, T>) -> Binding<T> {
        Binding(get: { session.params.doubleExposure[keyPath: key] }, set: {
            var p = session.params
            p.doubleExposure[keyPath: key] = $0
            session.params = p
        })
    }
    var body: some View {
        PanelSection(L("Double Exposure", zh: "双重曝光"), key: "doubleExposure", initiallyExpanded: false,
                     toggle: bind(\.active), toggleHelp: L("Enable double exposure", zh: "开启双重曝光")) {
            RailRows {
                Button {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.image]
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        var p = session.params
                        p.doubleExposure.path = url.path
                        p.doubleExposure.active = true
                        session.params = p
                    }
                } label: {
                    Text(session.params.doubleExposure.path.isEmpty
                         ? L("Choose second photo", zh: "选择第二张照片")
                         : URL(fileURLWithPath: session.params.doubleExposure.path).lastPathComponent)
                        .lineLimit(1).truncationMode(.middle)
                }
                ScrubSlider(label: L("Balance", zh: "第二次曝光占比"), value: bind(\.balance), range: 0.1...0.9, zero: 0.5, snap: 0.01)
                ScrubSlider(label: L("Scale", zh: "缩放"), value: bind(\.scale), range: 1...4, zero: 1, snap: 0.01)
                ScrubSlider(label: L("Horizontal", zh: "水平位置"), value: bind(\.x), range: -1...1, zero: 0, snap: 0.01)
                ScrubSlider(label: L("Vertical", zh: "垂直位置"), value: bind(\.y), range: -1...1, zero: 0, snap: 0.01)
                Button(L("Rotate 90°", zh: "旋转 90°")) {
                    var p = session.params
                    p.doubleExposure.turns = (p.doubleExposure.turns + 1) % 4
                    session.params = p
                }
                Toggle(L("Flip horizontally", zh: "水平翻转"), isOn: bind(\.flipped))
            }.disabled(session.pair != nil)
        }
    }
}
