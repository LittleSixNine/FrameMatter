//  DateBackSection.swift — RFC-031's date back: the camera's LEDs exposing a
//  date onto the negative, before the developer and before halation.
//
//  Its own section, under Film Edge, because it works without one: in the bare
//  frame, a date back needs only the camera. With a film edge it can also
//  print **between** the frames. The camera is the film edge's format (the
//  engine reads the film's direction from it, `DateBackSettings.wire`).
//
//  **Which faces a camera has** is `FilmEdgeFormat.draws(_:)`: 135, half
//  frame and 120 (645 to 6×9) carry all three, and nothing panoramic prints a
//  date (answer C7). A face the camera cannot draw is greyed with the reason
//  rather than offered and silently dropped.
//
//  **The date and the shooting data print together** (1.3.1): the face is the
//  date's, and "Shooting data" adds the data line beside the frame — between
//  frames on 135, in the margin on 120. They were one choice, so a frame had
//  its date or its data and never both. On 120 the date itself prints in the
//  margin (no medium-format back printed in the picture), so it has no
//  corner and needs the film edge.
//
//  LCD styles share the existing optical chain. Manual wall time overrides
//  EXIF; the diagonal margin belongs only to 135 in-picture imprints.

import SwiftUI

struct DateBackSection: View {
    @Bindable var session: Session

    static let key = "dateBack"
    private var date: DateBackSettings { session.params.dateBack }
    private var edge: FilmEdgeSettings { session.params.filmEdge }
    /// The camera the date back is on.
    /// The camera the date back is on: the film edge's format while it is
    /// on, Film Format's otherwise. Nil when Film Format is no camera that
    /// ever carried one.
    private var camera: FilmEdgeFormat? { session.dateBackCamera }
    /// A face the camera carries and that has somewhere to print: the data
    /// face goes between frames or in the margin, so it needs the film edge.
    private func draws(_ face: DateBackFace) -> Bool { date.prints(face, filmEdge: edge) }
    private func onCamera(_ face: DateBackFace) -> Bool { camera?.draws(face) ?? false }
    private var cameraHasBack: Bool { DateBackFace.allCases.contains(where: draws) }

    var body: some View {
        PanelSection(L(.sectionDateBack), key: Self.key, initiallyExpanded: false,
                     note: date.active ? nil : L(.edgeOff),
                     foldedNote: summary,
                     toggle: Binding(get: { date.active }, set: { setActive($0) }),
                     toggleHelp: L("Expose the date onto the negative, as a camera's date back did",
                                   zh: "像相机的日期后背一样，把日期曝光在底片上")) {
            RailRows {
                PillSwitchRow(label: L(.dateFace), options: DateBackFace.allCases,
                              selection: bind(\.face), title: { $0.key.map { L($0) } ?? "LCD" },
                              enabled: { draws($0) }, reason: { faceReason($0) })
                if !draws(date.face) {
                    Text(faceReason(date.face))
                        .font(Theme.Font.sublabel).foregroundStyle(Theme.Ink.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, Theme.Metric.sliderLabelWidth)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if date.face == .lcd {
                    PillMenu(label: L("LCD style", zh: "LCD 样式"), options: DateBackLCDStyle.allCases,
                             title: { $0.title },
                             selection: bind(\.lcdStyle))
                        .help(L("Style 1: DSEG7 Classic Mini Bold Italic. Style 2: original segments.",
                                zh: "样式 1：DSEG7 Classic Mini Bold Italic。样式 2：原有七段数字。"))
                }
                if date.face == .lcd, date.lcdStyle == .dseg {
                    ScrubSlider(label: L("Field spacing", zh: "字段间距"), value: bind(\.fieldGapH),
                                range: DateBackSettings.fieldGapRange, zero: 1.20, snap: 0.05,
                                format: { String(format: "%.2fH", $0) })
                        .help(L("H is the digit height. Spacing between date fields, including hour and minute; the colon stays centered. Extra spacing inside each number is fixed at 0.20H.",
                                zh: "H 为数字高度。调整日期字段及小时、分钟之间的间距，冒号保持居中；字段内数字额外字距固定为 0.20H。"))
                }
                textRow
                if date.face != .data { manualTimeRows }
                if date.face != .data {
                    ToggleRow(label: L(.dateWithData), isOn: bind(\.withData),
                              enabled: date.prints(.data, filmEdge: edge), reason: dataNeedsFilmEdge,
                              sublabel: date.withData && !date.dataText.isEmpty ? date.dataText : L(.dateWithDataWhere),
                              help: L("Print the shooting data beside the frame as well as the date",
                                      zh: "在日期之外，同时把拍摄数据印在画面旁"))
                }
                if date.face != .data, camera?.printsInMargin == true {
                    Text(L("On 120 the date prints in the film margin beside the frame.",
                           zh: "120 的日期印在画面旁的片边上。"))
                        .font(Theme.Font.sublabel).foregroundStyle(Theme.Ink.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, Theme.Metric.sliderLabelWidth)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if date.face != .data {
                    PillSwitchRow(label: L(.dateWhere), options: DateBackPlacement.allCases,
                                  selection: bind(\.placement), title: { L($0.key) },
                                  enabled: { $0 == .frame || edge.effective },
                                  reason: { _ in L(.reasonBetweenNeedsFilmEdge) })
                    if !edge.effective {
                        Text(L(.reasonBetweenNeedsFilmEdge))
                            .font(Theme.Font.sublabel).foregroundStyle(Theme.Ink.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, Theme.Metric.sliderLabelWidth)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    cornerRow
                }
                ScrubSlider(label: L(.dateSize), value: bind(\.size), range: sizeRange,
                            zero: DateBackSettings.default.size, snap: 0.1,
                            format: { String(format: "%.1f×", $0) })
                if date.face != .data, camera?.group == .film135 {
                    ScrubSlider(label: L("Margin", zh: "边距"),
                                value: Binding(get: { date.marginPercent ?? 20 }, set: { set(\.marginPercent, $0) }),
                                range: DateBackSettings.marginRange, zero: 20, snap: 1,
                                format: { String(format: "%.0f", $0) },
                                disabled: date.placement != .frame)
                        .help(L("135 only. 0 touches the picture corner; 100 centers the imprint. Film borders are excluded.",
                                zh: "仅限 135 胶片。0 贴近照片内容角落，100 文字居中，沿对角线移动；不包含片边。"))
                    if date.marginPercent == nil {
                        Text(L("Legacy inset retained; moving Margin enables diagonal placement.",
                               zh: "沿用旧版边距；调整后启用对角线定位。"))
                            .font(Theme.Font.caption).foregroundStyle(Theme.Ink.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                ScrubSlider(label: L(.dateBrightness), sublabel: L(.dateStops),
                            value: bind(\.brightnessEV), range: DateBackSettings.brightnessRange,
                            zero: DateBackSettings.default.brightnessEV, snap: 0.5,
                            format: { String(format: "%+.1f", $0) })
                Text(cameraNote)
                    .font(Theme.Font.caption).foregroundStyle(Theme.Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .rowEnabled(date.active && cameraHasBack,
                        because: cameraHasBack ? L("Switch Date Back on in its header.", zh: "先在标题栏开启日期后背。")
                                               : noBackReason)
        }
    }

    // MARK: rows

    /// The date as it will print, and the order it is written in. The text is
    /// the session's: the date from EXIF in the chosen order, or for the data
    /// face the shooting data.
    @ViewBuilder private var textRow: some View {
        HStack(spacing: 0) {
            RowLabel(date.face == .data ? L(.dateImprint) : L(.dateDate))
            if date.face == .data {
                Text(printed.isEmpty ? "—" : printed)
                    .font(Theme.Font.value).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Menu {
                    ForEach(DateBackOrder.allCases) { order in
                        Button { set(\.order, order) } label: {
                            let line = "\(example(order))  ·  \(L(order.key))"
                            if order == date.order { Label(line, systemImage: "checkmark") } else { Text(line) }
                        }
                    }
                } label: {
                    HStack(spacing: 0) {
                        Text(printed.isEmpty ? "—" : printed).font(Theme.Font.label).foregroundStyle(Theme.text)
                            .lineLimit(1).fixedSize()
                            .padding(.leading, 10)
                        Spacer(minLength: 4)
                        Triangle()
                            .stroke(Theme.text, style: StrokeStyle(lineWidth: 1, lineJoin: .round))
                            .frame(width: 8, height: 5)
                            .padding(.trailing, 9)
                    }
                    .frame(width: Theme.Metric.edgeFormatPillWidth, height: Theme.Metric.controlHeight)
                    .background(Theme.pill, in: Capsule())
                    .contentShape(Capsule())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L("The order the date is written in", zh: "日期的书写顺序"))
            }
            Spacer(minLength: 6)
            // Wraps rather than widens the rail: "no date in EXIF" is the
            // longer of the two and the pill before it is fixed.
            Text(date.customDateTime != nil ? L("Manual", zh: "手动")
                 : date.text.isEmpty ? L("no date/time in EXIF", zh: "EXIF 中无所需日期或时间") : L(.dateFromEXIF))
                .font(Theme.Font.caption).foregroundStyle(Theme.Ink.tertiary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: Theme.Metric.rowHeight)
    }

    /// The camera's corner, **held level**: the pad is the camera's back, so
    /// a turned frame keeps the corner it was shot with.
    private var cornerRow: some View {
        HStack(alignment: .center, spacing: 0) {
            RowLabel(L(.dateCorner))
            CornerPad(selection: bind(\.corner))
                .frame(width: Theme.Metric.dateCornerPad.width, height: Theme.Metric.dateCornerPad.height)
            Text(L("the camera's,\nheld level", zh: "相机的角，\n按横持计"))
                .font(Theme.Font.caption).foregroundStyle(Theme.Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 8)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var manualTimeRows: some View {
        ToggleRow(label: L("Manual time", zh: "手动时间"),
                  isOn: Binding(get: { date.customDateTime != nil }, set: { on in
                      var p = session.params
                      p.dateBack.customText = nil
                      if on {
                          let d = session.shootingData.captureDay
                          let components = DateComponents(calendar: Calendar(identifier: .gregorian),
                                                          year: d?.year, month: d?.month, day: d?.day,
                                                          hour: d?.hour, minute: d?.minute)
                          let value = d == nil ? Date() : components.date ?? Date()
                          p.dateBack.customDateTime = DateBackSettings.timeFormatter().string(from: value)
                      } else { p.dateBack.customDateTime = nil }
                      session.params = p
                  }))
        if date.customDateTime != nil {
            DatePicker(L("Imprint time", zh: "打印时间"),
                       selection: Binding(get: { DateBackSettings.timeFormatter().date(from: date.customDateTime ?? "") ?? Date() },
                                          set: { set(\.customDateTime, DateBackSettings.timeFormatter().string(from: $0)) }),
                       displayedComponents: [.date, .hourAndMinute])
                .labelsHidden().datePickerStyle(.field).controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: words

    private var printed: String { date.printedText }

    private var summary: String? {
        guard date.active else { return nil }
        let face = date.face.key.map { L($0) } ?? "LCD"
        return printed.isEmpty ? face : "\(face) · \(printed)"
    }

    /// On half frame the data face has only the 1 mm gap (answer B19).
    private var sizeRange: ClosedRange<Double> {
        let r = DateBackSettings.sizeRange
        guard date.face == .data, camera == .f135Half else { return r }
        return r.lowerBound...DateBackSettings.halfFrameDataSizeMax
    }

    /// Which camera it is, where that came from, and which way the date runs.
    /// The film runs down a picture that is taller than wide, so the back —
    /// and the date — turned with it.
    private var cameraNote: String {
        guard let camera else { return noBackReason }
        let name = camera.title
        let source = edge.effective ? L("from Film Edge", zh: "来自片边")
                                    : L("from Film Format", zh: "来自胶片画幅")
        let head = L("Camera: \(name), \(source).", zh: "相机：\(name)，\(source)。")
        guard let px = session.edgePicturePixels else { return head }
        // A half frame held level is the portrait one.
        let turned = (px.h > px.w) != (camera == .f135Half)
        return head + " " + (turned
            ? L("It turned for this frame, so the date runs down the picture.",
                zh: "这一格相机是竖持的，所以日期沿画面纵向排列。")
            : L("It was held level, so the date runs along the picture.",
                zh: "这一格相机是横持的，所以日期沿画面横向排列。"))
    }

    private var noBackReason: String {
        guard let camera else {
            return L("Film Format is no camera with a date back: 135, half frame or 645 has one; other 120 formats need Film Edge.",
                     zh: "当前胶片画幅的相机没有日期后背：135、半格和 645 才有；其他 120 画幅需要开启片边。")
        }
        // The camera has a back, but its only face prints on the film edge.
        if DateBackFace.allCases.contains(where: onCamera) { return dataNeedsFilmEdge }
        return camera.group == .panoramic
            ? L("No date back on the panoramic formats.", zh: "宽幅画幅没有日期后背。")
            : L("No \(camera.title) camera printed a date.", zh: "\(camera.title) 相机没有日期后背。")
    }

    private var dataNeedsFilmEdge: String {
        camera?.printsInMargin == true
            ? L("A 120 back prints beside the frame, on the film edge: it needs Film Edge.",
                zh: "120 的后背印在画面旁的片边上，需要开启片边。")
            : L("Data prints beside the frame, on the film edge: it needs Film Edge.",
                zh: "数据印在画面旁的片边上，需要开启片边。")
    }

    private func faceReason(_ face: DateBackFace) -> String {
        onCamera(face) ? dataNeedsFilmEdge : noFaceReason
    }

    private var noFaceReason: String {
        L("No \(camera?.title ?? "") camera printed a date.", zh: "\(camera?.title ?? "") 相机没有日期后背。")
    }

    /// The date in `order`, rebuilt from the printed one. The session writes
    /// it as `DateBackSettings.format` does — three fields, the year behind an
    /// apostrophe — so the fields can be moved without the date itself.
    private func example(_ order: DateBackOrder) -> String {
        let resolved = date.resolvedDateText(shooting: session.shootingData, order: order)
        return date.imprintText(resolved.isEmpty
            ? DateBackSettings.format(year: 2026, month: 9, day: 15, hour: 12, minute: 37, order: order)
            : resolved)
    }

    // MARK: writes

    private func setActive(_ on: Bool) {
        var p = session.params
        p.dateBack.active = on
        // A face the camera cannot draw would turn on to nothing: take the
        // first one it can.
        if on, !draws(p.dateBack.face), let face = DateBackFace.allCases.first(where: draws) {
            p.dateBack.face = face
        }
        session.params = p
        if on { UserDefaults.standard.set(true, forKey: Session.uiKey + "section.\(Self.key)") }
    }

    private func bind<V>(_ kp: WritableKeyPath<DateBackSettings, V>) -> Binding<V> {
        Binding(get: { session.params.dateBack[keyPath: kp] }, set: { set(kp, $0) })
    }

    private func set<V>(_ kp: WritableKeyPath<DateBackSettings, V>, _ value: V) {
        var p = session.params; p.dateBack[keyPath: kp] = value; session.params = p
    }
}

/// The four corners of the camera's back, as a pad: a ring per corner, the
/// chosen one filled.
private struct CornerPad: View {
    @Binding var selection: DateBackCorner

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.plot)
                RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Theme.pill, lineWidth: 1)
                ForEach(DateBackCorner.allCases) { corner in
                    let on = corner == selection
                    let x = corner == .bl || corner == .tl ? 8 : w - 8
                    let y = corner == .tl || corner == .tr ? 8 : h - 8
                    Circle()
                        .fill(on ? Theme.selection : Color.clear)
                        .overlay(Circle().stroke(on ? Theme.selection : Theme.Ink.tertiary, lineWidth: 1))
                        .frame(width: on ? 6.6 : 5.2, height: on ? 6.6 : 5.2)
                        // A target the size of the pad's quarter, not the dot.
                        .frame(width: w / 2, height: h / 2)
                        .contentShape(Rectangle())
                        .position(x: x < w / 2 ? w / 4 : 3 * w / 4, y: y < h / 2 ? h / 4 : 3 * h / 4)
                        .onTapGesture { selection = corner }
                        .accessibilityLabel(corner.rawValue)
                        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
    }
}
