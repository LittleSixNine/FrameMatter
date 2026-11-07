import SwiftUI
import AppKit

struct ExportRunStatus {
    var total = 0
    var processed = 0
    var written = 0
    var skipped = 0
    var failed = 0
    var currentFile = ""
    var files: [URL] = []
    var detail = ""
    var finished = false
    var cancelled = false
    var hasWarning = false

    enum Phase { case working, success, attention, failure, cancelled }
    var phase: Phase {
        if !finished { return .working }
        if cancelled { return .cancelled }
        if failed > 0 && written == 0 { return .failure }
        if failed > 0 || skipped > 0 || hasWarning || written == 0 { return .attention }
        return .success
    }
    @MainActor var title: String {
        switch phase {
        case .working: L("Exporting…", zh: "正在导出…")
        case .success: L("Export succeeded", zh: "导出成功")
        case .attention: written > 0 ? L("Export finished with notices", zh: "导出完成，请查看提示")
                                    : L("No new files exported", zh: "未导出新文件")
        case .failure: L("Export failed", zh: "导出失败")
        case .cancelled: L("Export stopped", zh: "导出已停止")
        }
    }
}

struct ExportProgressSheet: View {
    let status: ExportRunStatus
    let stop: () -> Void
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: glyph).font(.system(size: 28))
                    .foregroundStyle(status.phase == .success ? Color.green : Theme.exportAccent)
                Text(status.title).font(.title2.weight(.semibold))
            }
            if !status.finished {
                if status.total > 1 {
                    ProgressView(value: Double(status.processed), total: Double(status.total))
                        .progressViewStyle(.linear)
                } else {
                    // A frame's render/write has no measured percentage; animate rather than invent one.
                    ProgressView().progressViewStyle(.linear)
                }
                Text(L("\(status.processed) of \(status.total) images finished", zh: "已处理 \(status.processed) / \(status.total) 张"))
                    .font(Theme.Font.label)
                Text(status.currentFile).font(Theme.Font.caption).lineLimit(2).textSelection(.enabled)
                Text(L("Rendering and writing the file. Stop takes effect between images.",
                       zh: "正在处理并写入文件；停止会在当前图像处理完成后生效。"))
                    .font(Theme.Font.caption).foregroundStyle(Theme.Ink.secondary)
            } else {
                Text(L("Exported \(status.written) · Skipped \(status.skipped) · Failed \(status.failed)",
                       zh: "已导出 \(status.written) 张 · 跳过 \(status.skipped) 张 · 失败 \(status.failed) 张"))
                    .font(Theme.Font.label)
                ScrollView {
                    Text(status.detail).font(Theme.Font.caption).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 160)
                if let folder = status.files.first?.deletingLastPathComponent() {
                    Text(folder.path).font(Theme.Font.caption).foregroundStyle(Theme.Ink.secondary)
                        .textSelection(.enabled).lineLimit(3)
                }
            }
            HStack {
                Spacer()
                if !status.finished {
                    Button(L("Stop", zh: "停止"), action: stop)
                } else {
                    if !status.files.isEmpty {
                        Button(L("Show in Finder", zh: "在访达中显示")) {
                            NSWorkspace.shared.activateFileViewerSelecting(status.files)
                        }
                    }
                    Button(L("Done", zh: "完成"), action: done).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28).frame(width: 440).background(Theme.card)
        .interactiveDismissDisabled(!status.finished)
        .accessibilityIdentifier("exportProgressResult")
    }
    private var glyph: String {
        switch status.phase {
        case .working: "square.and.arrow.up"
        case .success: "checkmark.circle.fill"
        case .attention: "exclamationmark.triangle.fill"
        case .failure: "xmark.circle.fill"
        case .cancelled: "stop.circle"
        }
    }
}
