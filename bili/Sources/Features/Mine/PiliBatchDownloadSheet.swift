import PiliPlaybackCore
import SwiftUI

struct PiliBatchDownloadSheet: View {
    @StateObject private var model: PiliBatchDownloadModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("piliplus.offline.cellular") private var allowsCellular = false
    init(api: BiliAPIClient, request: PiliBatchDownloadRequest) {
        _model = StateObject(wrappedValue: PiliBatchDownloadModel(api: api, request: request))
    }
    var body: some View {
        NavigationStack {
            List {
                Section(model.request.title) {
                    Picker("下载内容", selection: $model.mediaKind) {
                        Text("视频与音频").tag(OfflineMediaKind.video)
                        Text("仅音频").tag(OfflineMediaKind.audio)
                    }.accessibilityIdentifier("batchDownload.mediaKind")
                    if model.mediaKind == .video {
                        Picker("最高画质", selection: $model.maximumQuality) {
                            Text("4K").tag(120)
                            Text("1080P 60帧").tag(116)
                            Text("1080P 高码率").tag(112)
                            Text("1080P").tag(80)
                            Text("720P").tag(64)
                            Text("480P").tag(32)
                            Text("360P").tag(16)
                        }
                        Text("没有所选画质时使用可用的较低画质；无法下载的内容会列出原因。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Toggle("包含视频的所有分 P", isOn: $model.allParts)
                    Toggle("允许蜂窝网络下载", isOn: $allowsCellular)
                }.disabled(model.isRunning)
                Section {
                    Text(model.status)
                    if model.isRunning {
                        if model.total > 0 { ProgressView(value: Double(model.processed), total: Double(model.total)) }
                        else { ProgressView() }
                        Button("停止添加", role: .cancel) { model.cancel() }
                    } else {
                        Button(model.hasFinished ? "重新检查并添加" : "开始加入下载队列") { model.start() }
                            .accessibilityIdentifier("batchDownload.start")
                    }
                    if model.isRunning || model.hasFinished {
                        Text("已加入 \(model.addedCount) 项 · 已存在 \(model.duplicateCount) 项")
                            .font(.subheadline).accessibilityIdentifier("batchDownload.summary")
                    }
                }
                if !model.failures.isEmpty {
                    Section("未能加入的内容（\(model.failures.count)）") {
                        ForEach(Array(model.failures.enumerated()), id: \.offset) { _, failure in Text(failure).font(.footnote) }
                    }
                }
            }
            .navigationTitle("批量缓存")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { model.cancel(); dismiss() } } }
        }
        .onDisappear { model.cancel() }
    }
}
