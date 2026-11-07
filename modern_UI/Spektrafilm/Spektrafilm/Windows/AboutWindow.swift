// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
// Applies only to FrameMatter contributions; upstream notices are retained. See COPYRIGHT.txt.

//  AboutWindow.swift — who made this, under what licence, and where the
//  source is.
//
//  **Not a nicety.** Two of the three licences the bundle carries require
//  something visible, and one of them names this screen: CC BY-SA 4.0, on the
//  film and paper profiles, says the attribution must survive "whether the LUT
//  is shipped inside a .cube header, an ICC profile field, an app's About
//  screen, a paid plugin … the form can vary; the information cannot
//  disappear." The GPL requires the licence text and an offer of the
//  corresponding source. So: the credit is on the front, the full texts are
//  one click away, and both are read out of the bundle rather than retyped
//  here — a licence text that drifts from the file beside it is worse than
//  none (HANDOFF-DISTRIBUTION §2.3).

import AppKit
import SwiftUI

struct AboutWindow: View {
    @State private var showing: Licence?

    /// One licence text in the bundle. `body` is read lazily: five files, of
    /// which the GPL alone is 35 kB, and the panel usually shows none of them.
    struct Licence: Identifiable, Hashable {
        let id: String       // the file name
        let title: String
        var chineseTitle = ""
        @MainActor var localizedTitle: String { L(title, zh: chineseTitle) }
        var url: URL? { AboutWindow.licenceDirectory?.appending(path: id) }
        var body: String {
            (url.flatMap { try? String(contentsOf: $0, encoding: .utf8) })
                ?? "\(id) is missing from this build. Run Tools/bundle-licenses.sh."
        }
    }

    /// Where the corresponding source is, and the **one** place that string
    /// lives in the app.
    ///
    /// This is the GPL's written offer, so it is not decoration: a binary
    /// distributed under GPL-3.0 has to tell the person holding it where to
    /// get the source *of that binary*. The shipped `Licenses/README.txt`
    /// carries the same sentence, written by `Tools/bundle-licenses.sh`, and
    /// `LicensingTests` asserts the two agree — they did not, for two product
    /// renames: the panel pointed here and the licence file still pointed at
    /// the upstream project, which is the source of the profiles and not of
    /// this application.
    ///
    /// **If the repository is renamed, change it here and in
    /// `bundle-licenses.sh`, then re-run that script.** GitHub redirects a
    /// renamed repository, so the old link keeps resolving and nothing breaks
    /// loudly — which is exactly why it needs saying.
    static let sourceURL = "https://github.com/LittleSixNine/FrameMatter"
    /// The same URL as the panel shows it, without the scheme.
    static var sourceLabel: String {
        sourceURL.replacingOccurrences(of: "https://", with: "")
    }

    /// The upstream project: the profiles, the print model and the engine's
    /// science. A different work under a different licence, and the reason
    /// two source links appear on this panel rather than one.
    static let photoTrailURL = "https://github.com/LittleSixNine/PhotoTrail"
    static let originalAppURL = "https://github.com/JamesQiu2005/SpektraLab"
    static let upstreamURL = "https://github.com/andreavolpato/spektrafilm"

    static let licences = [
        Licence(id: "PhotoTrail-Metadata-NOTICE.txt", title: "PhotoTrail — metadata code provenance and licence", chineseTitle: "PhotoTrail — 元数据代码来源与授权"),
        Licence(id: "FrameMatter-COPYRIGHT.txt", title: "FrameMatter contributions — LittleSixNine", chineseTitle: "FrameMatter 新增与修改贡献 — LittleSixNine"),
        Licence(id: "DSEG-OFL-1.1.txt", title: "SIL OFL 1.1 — DSEG fonts by Keshikan", chineseTitle: "SIL OFL 1.1 — Keshikan 的 DSEG 字体"),
        Licence(id: "FrameMatter-GPL-3.0.txt", title: "GNU GPL v3 — the application and the engine", chineseTitle: "GNU GPL v3 — 应用与引擎"),
        Licence(id: "Profiles-and-LUTs-CC-BY-SA-4.0.txt", title: "CC BY-SA 4.0 — the profiles and the print LUTs", chineseTitle: "CC BY-SA 4.0 — 配置数据与印相 LUT"),
        Licence(id: "Profiles-and-LUTs-CHANGELOG.txt", title: "What this build changed about the profiles and LUTs", chineseTitle: "此构建对配置数据及 LUT 的修改"),
        Licence(id: "FilmDamageSimulator-Data-CC-BY-4.0.txt", title: "CC BY 4.0 — FilmDamageSimulator dust and fiber scans", chineseTitle: "CC BY 4.0 — FilmDamageSimulator 灰尘与纤维扫描素材"),
        Licence(id: "FilmDamageSimulator-Dust-Attribution.txt", title: "Dust and fiber masks — attribution and changes", chineseTitle: "灰尘与纤维遮罩 — 署名与修改记录"),
        Licence(id: "FilmDamageSimulator-MIT.txt", title: "MIT — FilmDamageSimulator scratch-mask reference", chineseTitle: "MIT — FilmDamageSimulator 划痕算法参考"),
        Licence(id: "metal-cpp-Apache-2.0.txt", title: "Apache 2.0 — metal-cpp", chineseTitle: "Apache 2.0 — metal-cpp"),
    ]

    /// `Bundle(for:)`, not `Bundle.main`, for `EngineClient`'s reason: the
    /// unit-test target is standalone, so `Bundle.main` is Xcode's test agent
    /// and every lookup misses.
    static var licenceDirectory: URL? {
        Bundle(for: BundleToken.self).url(forResource: "Licenses", withExtension: nil,
                                          subdirectory: "Resources")
    }
    private final class BundleToken {}

    @MainActor private static var version: String {
        let info = Bundle(for: BundleToken.self).infoDictionary
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return L("Build \(build)", zh: "构建版本 \(build)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            credits
            Divider()
            licenceList
        }
        .frame(width: 460)
        .background(Theme.card)
        .sheet(item: $showing) { licence in
            LicenceSheet(licence: licence) { showing = nil }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text("FrameMatter").font(.system(size: 20, weight: .semibold))
                Text(AboutWindow.version).font(Theme.Font.sublabel).foregroundStyle(.secondary)
                Text(L("A spectral film and print simulation for macOS.", zh: "适用于 macOS 的光谱胶片与印相模拟。"))
                    .font(Theme.Font.sublabel).foregroundStyle(.secondary)
                link(AboutWindow.sourceLabel, AboutWindow.sourceURL)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private var credits: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("FrameMatter additions and modifications © 2026 LittleSixNine. GPL v3 or later; upstream copyrights retained.", zh: "FrameMatter 新增与修改贡献 © 2026 LittleSixNine，依 GPL v3 或后续版本授权；保留上游版权。"))
                .font(Theme.Font.sublabel).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // The one line that says which name belongs to which thing. This
            // app is FrameMatter; the engine, the profiles and the LUTs it uses
            // are spektrafilm's, and `SPEKTRAFILM_LICENSE.txt` asks that the
            // product branding be kept apart from the factual reference —
            // which it welcomes. Saying so on the About panel is where that
            // distinction is legible.
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Based on SpektraLab by Hanze Qiu", zh: "基于 Hanze Qiu 开发的 SpektraLab"))
                    .font(Theme.Font.groupHeader).foregroundStyle(Theme.text)
                Text(L("The original application, native engine port and black-and-white profiles are credited to Hanze Qiu.", zh: "原始应用、原生引擎移植和黑白胶片配置由 Hanze Qiu 完成。"))
                    .font(Theme.Font.sublabel).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                link("github.com/JamesQiu2005/SpektraLab", AboutWindow.originalAppURL)
            }
            Text(L("FrameMatter uses the spektrafilm engine, film and paper profiles, and the print-preview LUTs baked from them.", zh: "FrameMatter 使用 spektrafilm 引擎、胶片与相纸配置，以及由这些配置生成的印相预览 LUT。"))
                .font(Theme.Font.sublabel).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // The attribution the CC BY-SA licence requires, in the form it
            // suggests: author, canonical source, licence.
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Film simulation, measured profiles and print model", zh: "胶片模拟、实测配置与印相模型"))
                    .font(Theme.Font.groupHeader).foregroundStyle(Theme.text)
                Text(L("Andrea Volpato — licensed CC BY-SA 4.0", zh: "Andrea Volpato — 依 CC BY-SA 4.0 授权"))
                    .font(Theme.Font.sublabel).foregroundStyle(.secondary)
                link(AboutWindow.upstreamURL.replacingOccurrences(of: "https://", with: ""),
                     AboutWindow.upstreamURL)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(L("FrameMatter and its render engine", zh: "FrameMatter 及其渲染引擎"))
                    .font(Theme.Font.groupHeader).foregroundStyle(Theme.text)
                // The GPL's written offer, and the only form of it that is
                // any use: a place to get the code. It points at this
                // application's own repository, which is the work the GPL
                // covers — the upstream link above covers the profiles.
                Text(L("Free software under the GNU GPL v3 or later. You have the right to the corresponding source.", zh: "依 GNU GPL v3 或后续版本授权的自由软件。你有权获取相应源代码。"))
                    .font(Theme.Font.sublabel).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                link(AboutWindow.sourceLabel, AboutWindow.sourceURL)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Metadata handling adapted from PhotoTrail", zh: "部分元数据处理代码改编自 PhotoTrail"))
                    .font(Theme.Font.groupHeader).foregroundStyle(Theme.text)
                Text(L("LittleSixNine — the reused original code is separately licensed GPL v3 or later for FrameMatter.", zh: "LittleSixNine — 本项目复用的相关原创代码另行按 GPL v3 或后续版本授权。"))
                    .font(Theme.Font.sublabel).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                link("github.com/LittleSixNine/PhotoTrail", AboutWindow.photoTrailURL)
            }
            Text(L("The 8 baked print-preview LUTs are derivatives of the profiles and carry the same CC BY-SA 4.0 licence. What was changed, and what was not, is in the changelog below.", zh: "8 份预生成的印相预览 LUT 由配置数据衍生，沿用 CC BY-SA 4.0 许可。具体修改与保留内容见下方变更记录。"))
                .font(Theme.Font.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }

    private var licenceList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Licences", zh: "许可协议")).font(Theme.Font.groupHeader).foregroundStyle(Theme.text)
            ForEach(AboutWindow.licences) { licence in
                Button { showing = licence } label: {
                    HStack(spacing: 6) {
                        Text(licence.localizedTitle).font(Theme.Font.listItem).foregroundStyle(Theme.text)
                            .lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 9))
                            .foregroundStyle(Theme.dim)
                    }
                    .frame(height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let dir = AboutWindow.licenceDirectory {
                Button(L("Show the licence files in Finder", zh: "在访达中显示许可文件")) {
                    NSWorkspace.shared.activateFileViewerSelecting([dir])
                }
                .buttonStyle(.link).font(Theme.Font.caption)
            } else {
                // Said rather than hidden: a build with no licence texts is a
                // build that should not have been made.
                Text(L("This build carries no licence texts. Run Tools/bundle-licenses.sh and rebuild.", zh: "此构建缺少许可正文。请运行 Tools/bundle-licenses.sh 后重新构建。"))
                    .font(Theme.Font.caption).foregroundStyle(Theme.accent)
            }
        }
        .padding(20)
    }

    private func link(_ label: String, _ url: String) -> some View {
        Button(label) { if let u = URL(string: url) { NSWorkspace.shared.open(u) } }
            .buttonStyle(.link).font(Theme.Font.sublabel)
    }
}

/// One licence, in full, selectable and scrollable.
///
/// Rendered in the app rather than handed to TextEdit: a signed, notarised
/// bundle's resources are read-only and opening them in another app is one
/// more thing that can fail on a stranger's machine, when the obligation is
/// simply that the text be *available*.
private struct LicenceSheet: View {
    let licence: AboutWindow.Licence
    let dismiss: () -> Void
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(licence.localizedTitle).font(.system(size: 13, weight: .semibold))
            ScrollView {
                Text(text)
                    .font(.system(size: 10.5, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(Theme.well, in: RoundedRectangle(cornerRadius: 4))
            HStack {
                if let url = licence.url {
                    Button(L("Show in Finder", zh: "在访达中显示")) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .buttonStyle(.link).font(Theme.Font.caption)
                }
                Spacer()
                Button(L("Done", zh: "完成"), action: dismiss).keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 640, height: 520)
        .task { text = licence.body }
    }
}
