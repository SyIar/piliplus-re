import ChunUI
import SwiftUI
import UIKit

struct PiliMediaCaptureView: View {
    let source: URL
    let duration: Double
    @State private var start: Double
    @State private var animated = false
    @State private var seconds = 3.0
    @State private var edge = 640
    @State private var output: URL?
    @State private var task: Task<Void, Never>?
    @State private var progress = 0.0
    @State private var message: String?
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    init(source: URL, time: Double, duration: Double) {
        self.source = source; self.duration = duration.isFinite ? max(0, duration) : 0
        _start = State(initialValue: time.isFinite ? max(0, time) : 0)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("截取格式", selection: $animated) { Text("截图 PNG").tag(false); Text("动图 GIF").tag(true) }
                        .pickerStyle(.segmented)
                    LabeledContent("起点", value: String(format: "%.1f 秒", start))
                    if duration > 0.1 { Slider(value: $start, in: 0...max(0.1, duration - 0.1)) }
                    if animated {
                        Stepper("时长：\(Int(seconds)) 秒", value: $seconds, in: 1...10)
                        Picker("尺寸", selection: $edge) { Text("轻巧 480p").tag(480); Text("标准 640p").tag(640); Text("清晰 960p").tag(960) }
                        Text("按视频剩余时长截取，最长边为所选尺寸。较长或较大动图会自动降低帧率。").font(.footnote).foregroundStyle(.secondary)
                    }
                }.disabled(task != nil || saving)
                Section {
                    if let output {
                        ShareLink(item: output) { Label("分享导出文件", systemImage: "square.and.arrow.up") }
                        Button("保存到相册", systemImage: "square.and.arrow.down") {
                            saving = true
                            Task {
                                defer { saving = false }
                                do { try await PiliMediaCapture.saveImage(output); message = "已保存到相册" }
                                catch { message = error.localizedDescription }
                            }
                        }.disabled(saving)
                    }
                    if task != nil {
                        ProgressView(value: progress)
                        Button("取消导出", role: .cancel) { task?.cancel() }
                    } else {
                        Button(output == nil ? "开始截取" : "重新截取", systemImage: "camera") { capture() }
                            .disabled(saving).accessibilityIdentifier("capture.start")
                    }
                    if let message { Text(message).foregroundStyle(.secondary) }
                }
            }.navigationTitle("截图与动图").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .onDisappear { task?.cancel(); PiliMediaCapture.remove(output) }
        }
    }
    private func capture() {
        guard task == nil else { return }
        PiliMediaCapture.remove(output); output = nil; progress = 0; message = nil
        let length = animated ? seconds : nil
        task = Task {
            defer { task = nil }
            do {
                let file = try await PiliMediaCapture.export(url: source, start: start, length: length, maximumSize: edge) { value in
                    await MainActor.run { progress = value }
                }
                if Task.isCancelled { PiliMediaCapture.remove(file); return }
                output = file; message = "截取完成"
            } catch { if !Task.isCancelled { message = error.localizedDescription } }
        }
    }
    static func present(_ detail: VideoDetailViewModel) {
        guard let source = detail.selectedPlayVariant?.videoURL, let player = detail.stablePlayerViewModel else { return }
        let time = player.currentTime, duration = player.duration ?? Double(detail.detail.duration ?? 0)
        AppHelper.shared.presentSheet(.sheet) { PiliMediaCaptureView(source: source, time: time, duration: duration) }
    }
}
