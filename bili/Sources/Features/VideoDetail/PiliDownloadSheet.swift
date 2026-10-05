import ChunUI
import PiliPlaybackCore
import SwiftUI

struct PiliDownloadSheet: View {
    @ObservedObject var viewModel: VideoDetailViewModel
    @State private var selectedCIDs: Set<Int>
    @State private var variantID: String
    @State private var mediaKind = OfflineMediaKind.video
    @State private var audioID = ""
    @AppStorage("piliplus.offline.cellular") private var allowsCellular = false

    init(viewModel: VideoDetailViewModel) {
        self.viewModel = viewModel
        _selectedCIDs = State(initialValue: Set([viewModel.selectedCID].compactMap { $0 }))
        _variantID = State(initialValue: viewModel.selectedPlayVariant?.id ?? "")
    }
    private var variants: [PlayVariant] { viewModel.playVariants.filter(\.isPlayable) }
    private var audios: [VideoListenAudioVariant] { viewModel.videoListenAudioVariants }
    private var pages: [VideoPage] {
        if let pages = viewModel.detail.pages, !pages.isEmpty { return pages }
        guard let cid = viewModel.selectedCID else { return [] }
        return [VideoPage(cid: cid, page: 1, part: viewModel.detail.title, duration: viewModel.detail.duration, dimension: viewModel.detail.dimension)]
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(viewModel.detail.title).ccText(font: .cc.baseBold, color: .cc.foreground)
                    Picker("下载内容", selection: $mediaKind) {
                        Text("视频与音频").tag(OfflineMediaKind.video)
                        Text("仅音频").tag(OfflineMediaKind.audio)
                    }.accessibilityIdentifier("download.mediaKind")
                    if mediaKind == .video {
                        Picker("下载画质", selection: $variantID) {
                            ForEach(variants) { variant in Text(variant.title).tag(variant.id) }
                        }
                    } else {
                        Picker("下载音质", selection: $audioID) {
                            ForEach(audios) { audio in Text(audio.title).tag(audio.id) }
                        }
                        Text(audios.isEmpty ? "当前视频没有可独立下载的音频流" : "只下载音频轨，离线打开后进入音频播放器")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Toggle("允许使用蜂窝网络下载", isOn: $allowsCellular)
                }
                Section("选择分集") {
                    if pages.count > 1 {
                        Button(selectedCIDs.count == pages.count ? "取消全选" : "全选") {
                            selectedCIDs = selectedCIDs.count == pages.count ? [] : Set(pages.map(\.cid))
                        }
                    }
                    ForEach(pages) { page in
                        Toggle(page.part ?? "P\(page.page ?? 1)", isOn: Binding(
                            get: { selectedCIDs.contains(page.cid) },
                            set: { if $0 { selectedCIDs.insert(page.cid) } else { selectedCIDs.remove(page.cid) } }
                        ))
                    }
                }
                Section {
                    CCNeoButton("加入下载队列", variant: .primary, icon: PikaIcon.Name.save, fullWidth: true,
                                disabled: selectedCIDs.isEmpty || (mediaKind == .audio ? audios.isEmpty : variants.isEmpty)) {
                        do {
                            let count: Int
                            let selectedPages = pages.filter { selectedCIDs.contains($0.cid) }
                            if mediaKind == .audio {
                                guard let audio = audios.first(where: { $0.id == audioID }) ?? audios.first else { return }
                                count = try PiliOfflineStore.shared.enqueueAudio(video: viewModel.detail, pages: selectedPages, audio: audio)
                            } else {
                                guard let variant = variants.first(where: { $0.id == variantID }) ?? variants.first else { return }
                                count = try PiliOfflineStore.shared.enqueue(video: viewModel.detail, pages: selectedPages, variant: variant)
                            }
                            CCToastCenter.shared.show(.success, count > 0 ? "已加入 \(count) 个下载任务" : "所选视频已在下载列表中")
                            AppHelper.shared.dismissSheet()
                        } catch { CCToastCenter.shared.show(.error, error.localizedDescription) }
                    }
                    Text("下载保留所选画质或音质。可在“我的 → 离线下载”查看进度、暂停或继续。")
                        .ccText(font: .cc.sm, color: .cc.mutedForeground)
                }
            }
            .navigationTitle("离线下载")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { AppHelper.shared.dismissSheet() } label: { PikaIcon(PikaIcon.Name.close) }
                        .accessibilityLabel("关闭")
                }
            }
        }
        .onAppear {
            if variantID.isEmpty { variantID = variants.first?.id ?? "" }
            if audioID.isEmpty { audioID = viewModel.resolvedVideoListenAudioVariant?.id ?? audios.first?.id ?? "" }
        }
    }
}
