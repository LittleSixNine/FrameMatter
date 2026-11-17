//  The editor inspector. Section keys also own disclosure and resize preferences.
import SwiftUI

enum ParametersTab: String, CaseIterable, Identifiable {
    case presets, preDev, film, postDev, effects, crop
    var id: Self { self }

    @MainActor var title: String {
        switch self {
        case .presets: L("Presets", zh: "预设")
        case .preDev: L(.tabPreDev)
        case .film: L(.sectionFilm)
        case .postDev: L(.tabPostDev)
        case .effects: L("Effects", zh: "效果")
        case .crop: L("Crop", zh: "裁剪")
        }
    }
}

struct InspectorTabs: View {
    @Bindable var session: Session
    static let width: CGFloat = 66

    var body: some View {
        VStack(spacing: 4) {
            ForEach(ParametersTab.allCases) { tab in
                let selected = !session.rightCollapsed && session.inspectorTab == tab
                Button { session.toggleInspector(tab) } label: {
                    VStack(spacing: 4) {
                        InspectorGlyph(tab: tab).stroke(style: StrokeStyle(lineWidth: 1.45, lineCap: .round, lineJoin: .round))
                            .frame(width: 22, height: 22)
                            .accessibilityHidden(true)
                        Text(tab.title).font(Theme.Font.caption)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(selected ? Theme.accent : Theme.secondaryText)
                    .background(selected ? Theme.accent.opacity(0.12) : .clear,
                                in: RoundedRectangle(cornerRadius: 5))
                    .overlay(alignment: .leading) {
                        if selected { Capsule().fill(Theme.accent).frame(width: 2, height: 18) }
                    }
                    .overlay(alignment: .topTrailing) {
                        if tab == .postDev && session.layerAdjustments.enabled && !session.layerAdjustments.isNeutral {
                            Circle().fill(Theme.accent).frame(width: 5, height: 5).padding(5)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityIdentifier("inspector." + tab.rawValue)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(width: Self.width)
        .railCard()
        .overlay(alignment: .leading) { VerticalHairline().allowsHitTesting(false) }
    }
}

struct RightPanel: View {
    @Bindable var session: Session
    @State private var offsets: [ParametersTab: CGFloat] = [:]

    private func sections(for tab: ParametersTab) -> [(String, AnyView)] {
        var s: [(String, AnyView)] = []
        switch tab {
        case .presets:
            break
        case .preDev:
            s.append(("latitude", AnyView(LatitudeSection(session: session))))
            s.append(("camera", AnyView(CameraSection(session: session))))
            s.append(("perspective", AnyView(PerspectiveSection(session: session))))
            s.append(("filmFormat", AnyView(FilmFormatSection(session: session))))
            s.append(("scenePlacement", AnyView(ScenePlacementSection(session: session))))
            s.append(("sceneCurve", AnyView(SceneCurveSection(session: session))))
            if FeatureFlags.toneMask { s.append(("toneMask", AnyView(ToneMaskSection(session: session)))) }
        case .film:
            s.append(("film", AnyView(FilmSection(session: session))))
            s.append(("print", AnyView(PrintProfileSection(session: session))))
            s.append((GrainSection.key, AnyView(GrainSection(session: session))))
            s.append(("enlarger", AnyView(EnlargerSection(session: session))))
        case .postDev:
            s.append(("wb2", AnyView(WhiteBalanceSection(session: session))))
            s.append(("exposure2", AnyView(ExposureSection(session: session))))
            s.append(("hsl", AnyView(HSLSection(session: session))))
            s.append(("channelMixer", AnyView(ChannelMixerSection(session: session))))
            s.append(("curve", AnyView(CurveSection(session: session))))
            s.append(("colorbalance", AnyView(ColorBalanceSection(session: session))))
            if FeatureFlags.masks { s.append(("masks", AnyView(MasksSection(session: session)))) }
        case .effects:
            s.append(("diffusion", AnyView(DiffusionSection(session: session))))
            s.append(("doubleExposure", AnyView(DoubleExposureSection(session: session))))
            s.append((FilmEdgeSection.key, AnyView(FilmEdgeSection(session: session))))
            s.append((LightLeakSection.key, AnyView(LightLeakSection(session: session))))
            s.append((DateBackSection.key, AnyView(DateBackSection(session: session))))
            s.append((ScratchSection.key, AnyView(ScratchSection(session: session))))
        case .crop:
            if session.pair != nil {
                s.append((PairSection.key, AnyView(PairSection(session: session))))
            } else {
                s.append(("crop", AnyView(CropSection(session: session))))
            }
        }
        return s
    }

    var body: some View {
        VStack(spacing: 0) {
            if session.inspectorTab == .presets {
                DevelopPresetsSection(session: session)
            } else {
                HStack {
                    Text(session.inspectorTab.title).font(Theme.Font.railTitle)
                    Spacer()
                    Button { session.toggleInspector(session.inspectorTab) } label: {
                        Label(L("Collapse", zh: "收起"), systemImage: "sidebar.right")
                            .font(Theme.Font.caption)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("inspector.collapse")
                }
                .padding(.horizontal, Theme.Metric.rowInset)
                .frame(height: Theme.Metric.panelHeaderHeight)
                .background(WindowDragHandle())
                Hairline()
                let tab = session.inspectorTab
                InspectorPage(items: sections(for: tab), offset: Binding(
                    get: { offsets[tab, default: 0] },
                    set: { offsets[tab] = $0 }
                ))
                .id(tab)
            }
        }
        .disabled(session.rightCollapsed)
        .environment(\.railSliderMetrics, .parameters)
        .railCard()
    }
}

/// Only the current page is mounted, including its AppKit-backed controls.
private struct InspectorPage: View {
    let items: [(String, AnyView)]
    @Binding var offset: CGFloat
    @State private var position = ScrollPosition(edge: .top)
    @State private var restored = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.0) { index, entry in
                    if index > 0 { SectionDivider(above: items[index - 1].0) }
                    entry.1
                }
            }
        }
        .scrollPosition($position)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            max(0, geometry.contentOffset.y + geometry.contentInsets.top)
        } action: { _, y in
            if restored { offset = y }
        }
        .onAppear {
            if offset > 0 { position.scrollTo(y: offset) }
            restored = true
        }
    }
}

/// Six darkroom tools, drawn on the same 24-point grid.
private struct InspectorGlyph: Shape {
    let tab: ParametersTab

    func path(in rect: CGRect) -> Path {
        var p = Path()
        func line(_ points: CGPoint...) {
            guard let first = points.first else { return }
            p.move(to: first)
            for next in points.dropFirst() { p.addLine(to: next) }
        }
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, radius: CGFloat = 0) {
            p.addRoundedRect(in: CGRect(x: x, y: y, width: w, height: h),
                             cornerSize: CGSize(width: radius, height: radius))
        }
        switch tab {
        case .presets: // Two overlapping test prints, and a registration mark.
            line(pt(3, 16), pt(2, 4), pt(15, 3))
            box(6, 6, 15, 15, radius: 1)
            box(9, 9, 9, 6)
            line(pt(9, 18), pt(14, 18))
        case .preDev: // Iris blades around an open aperture.
            p.addEllipse(in: CGRect(x: 2, y: 2, width: 20, height: 20))
            for i in 0..<6 {
                let a = CGFloat(i) * .pi / 3
                func polar(_ r: CGFloat, _ angle: CGFloat) -> CGPoint {
                    pt(12 + r * cos(angle), 12 + r * sin(angle))
                }
                line(polar(9.9, a - 0.58), polar(4.4, a), polar(4.4, a + .pi / 3))
            }
        case .film: // 135 cartridge with the leader pulled out.
            box(3, 5, 10, 15, radius: 2)
            line(pt(5, 5), pt(5, 3), pt(11, 3), pt(11, 5))
            line(pt(13, 8), pt(21, 7), pt(21, 14), pt(18, 15), pt(18, 18), pt(13, 18))
            line(pt(6, 9), pt(10, 9)); line(pt(6, 16), pt(10, 16))
        case .postDev: // Enlarger on its column above a print easel.
            line(pt(4, 20), pt(4, 4), pt(14, 4), pt(14, 6))
            box(10, 6, 8, 4, radius: 1)
            line(pt(12, 10), pt(12, 12), pt(16, 12), pt(16, 10))
            line(pt(12, 15), pt(10, 18)); line(pt(16, 15), pt(18, 18))
            line(pt(2, 21), pt(21, 21))
        case .effects: // A light leak bleeding across the perforations.
            box(3, 3, 18, 18, radius: 1.5)
            for y in [5, 11, 17] { box(5, CGFloat(y), 2, 2, radius: 0.4) }
            p.move(to: pt(16, 3)); p.addQuadCurve(to: pt(12, 12), control: pt(9, 6))
            p.addQuadCurve(to: pt(14, 21), control: pt(16, 17))
            line(pt(17, 8), pt(16, 10))
        case .crop: // Opposing easel blades framing a composition guide.
            line(pt(2, 6), pt(18, 6), pt(18, 22))
            line(pt(6, 2), pt(6, 18), pt(22, 18))
            line(pt(10, 14), pt(15, 9)); line(pt(12, 9), pt(15, 9), pt(15, 12))
        }
        return p.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
    }
}
