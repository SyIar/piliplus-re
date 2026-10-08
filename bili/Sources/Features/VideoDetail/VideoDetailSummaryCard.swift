import SwiftUI
import ChunUI

struct VideoDetailSummaryCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsMoreTools = false
    let viewModel: VideoDetailViewModel
    let contentWidth: CGFloat
    let showsNetworkDiagnosticsButton: Bool
    let showsVideoInfo: Bool
    let onShowNetworkDiagnostics: () -> Void
    let onShowCoinPicker: () -> Void
    let renderPack: VideoDetailSummaryCardRenderPack

    init(
        viewModel: VideoDetailViewModel,
        contentWidth: CGFloat,
        showsNetworkDiagnosticsButton: Bool,
        showsVideoInfo: Bool = true,
        onShowNetworkDiagnostics: @escaping () -> Void,
        onShowFavoriteFolders: @escaping () -> Void,
        onShowCoinPicker: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.contentWidth = contentWidth
        self.showsNetworkDiagnosticsButton = showsNetworkDiagnosticsButton
        self.showsVideoInfo = showsVideoInfo
        self.onShowNetworkDiagnostics = onShowNetworkDiagnostics
        self.onShowCoinPicker = onShowCoinPicker
        renderPack = VideoDetailSummaryCardRenderPack(
            viewModel: viewModel,
            showFavoriteFolders: onShowFavoriteFolders
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsVideoInfo {
                VideoDetailInfoBlock(
                    store: renderPack.descriptionStore
                )
            }

            VideoDetailActionStripContainer(
                descriptionStore: renderPack.descriptionStore,
                store: renderPack.interactionStore,
                contentWidth: contentWidth,
                onFollow: renderPack.actions.follow,
                onLike: renderPack.actions.like,
                onCoin: showCoinPicker,
                onFavorite: renderPack.actions.favorite,
                onShareTap: renderPack.actions.share,
                onChooseFavorite: renderPack.actions.showFavoriteFolders
            )

            if showsNetworkDiagnosticsButton {
                VideoDetailNetworkDiagnosticsButton(action: onShowNetworkDiagnostics)
            }

            quickTools
            VideoDetailInteractionNotice(store: renderPack.interactionStore)
            VideoDetailPlayURLNotice(
                placeholderStore: renderPack.placeholderStore,
                retry: renderPack.actions.retryPlayURL
            )
        }
        .frame(width: contentWidth, alignment: .leading)
        .piliSheet(isPresented: $showsMoreTools) { moreTools }
    }

    private var quickTools: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                 count: dynamicTypeSize.isAccessibilitySize ? 2 : 4), spacing: 8) {
            if !viewModel.detail.isPGCEpisode {
                PiliVideoLibraryActions(viewModel: viewModel, descriptionStore: renderPack.descriptionStore)
            }
            quickTool("\u{7ae0}\u{8282}", icon: "list.bullet.rectangle", id: "chapters") {
                PiliPresentation.present(.sheet) { PiliVideoToolsView(model: viewModel, store: viewModel.piliVideoTools) }
            }
            if !viewModel.detail.isPGCEpisode, !viewModel.detail.piliIsCourse {
                quickTool("AI \u{603b}\u{7ed3}", icon: "text.badge.star", id: "ai") {
                    PiliPresentation.present(.sheet) { PiliAIConclusionView(model: viewModel) }
                }
            }
            quickTool("\u{66f4}\u{591a}", icon: "ellipsis", id: "more") { showsMoreTools = true }
        }
    }

    private var moreTools: some View {
        NavigationStack {
            PiliForm {
                if !viewModel.detail.piliIsCourse || viewModel.detail.piliUGCSeason != nil {
                    Section("\u{4e92}\u{52a8}\u{4e0e}\u{6536}\u{85cf}") {
                        if !viewModel.detail.piliIsCourse {
                            PiliTripleButton(viewModel: viewModel, store: renderPack.interactionStore, grouped: true)
                                .frame(minHeight: 44)
                        }
                        if let seasonID = viewModel.detail.piliUGCSeason?.id {
                            PiliSeasonActionsView(api: viewModel.api, seasonID: seasonID, collectionBVID: viewModel.detail.bvid)
                        }
                    }
                }
                Section("\u{89c6}\u{9891}\u{5de5}\u{5177}") {
                    tool("章节与视频信息", icon: "list.bullet.rectangle") {
                        PiliPresentation.present(.sheet) { PiliVideoToolsView(model: viewModel, store: viewModel.piliVideoTools) }
                    }
                    if !viewModel.detail.isPGCEpisode, !viewModel.detail.piliIsCourse {
                        tool("AI 总结", icon: "text.badge.star") {
                            PiliPresentation.present(.sheet) { PiliAIConclusionView(model: viewModel) }
                        }
                        tool("视频点踩", icon: "hand.thumbsdown") {
                            let video = viewModel.detail
                            PiliPresentation.present(.sheet) {
                                PiliRecommendationFeedbackView(api: viewModel.api, video: video) {
                                    guard viewModel.detail.bvid == video.bvid else { return }
                                    viewModel.interactionState.isLiked = false
                                }
                            }
                        }
                    }
                    tool("截图与动图", icon: "camera") { PiliMediaCaptureView.present(viewModel) }
                    tool("原声翻译", icon: "waveform") {
                        PiliPresentation.present(.sheet) { NavigationStack { PiliAudioLanguageView(viewModel: viewModel) } }
                    }
                    tool("离线下载", icon: "arrow.down.circle") {
                        PiliPresentation.present(.sheet) { PiliDownloadSheet(viewModel: viewModel) }
                    }
                    tool("投屏", icon: "tv") {
                        PiliPresentation.present(.sheet) { PiliDLNAView(source: { try .online(viewModel) }) }
                    }
                    tool("空降助手", icon: "forward.end") {
                        PiliPresentation.present(.sheet) { PiliSponsorView(model: viewModel) }
                    }
                    tool("字幕", icon: "captions.bubble") {
                        PiliSubtitleSettingsView.present(controller: viewModel.piliSubtitles) { seconds in
                            guard let player = viewModel.stablePlayerViewModel else { return }
                            player.seek(by: seconds - player.currentTime)
                        }
                    }
                    if viewModel.piliPlaybackQueue != nil || viewModel.detail.piliUGCSeason != nil {
                        tool("播放列表", icon: "list.bullet") {
                            PiliPresentation.present(.sheet) { PiliCollectionQueueView(viewModel: viewModel) }
                        }
                    }
                    tool("互动分支", icon: "point.topleft.down.to.point.bottomright.curvepath") {
                        PiliPresentation.present(.sheet) { PiliInteractiveHistoryView(controller: viewModel.piliInteractive) }
                    }
                    if let aid = viewModel.detail.aid {
                        tool("记笔记", icon: "square.and.pencil") {
                            PiliPresentation.present(.sheet) {
                                NavigationStack {
                                    PiliNoteEditorView(api: viewModel.api, aid: aid, initialTitle: viewModel.detail.title,
                                                       noteID: nil, initialText: "", time: viewModel.stablePlayerViewModel?.currentTime)
                                }
                            }
                        }
                        tool("举报视频", icon: "exclamationmark.bubble") {
                            PiliPresentation.present(.sheet) {
                                NavigationStack { PiliAccountWebView(api: viewModel.api, url: URL(string: "https://www.bilibili.com/appeal/?avid=\(aid)")!, title: "举报视频") }
                            }
                        }
                        tool("视频笔记", icon: "note.text") {
                            PiliPresentation.present(.sheet) { PiliNotesLibraryView(api: viewModel.api, video: viewModel.detail) }
                        }
                    }
                }
            }
            .navigationTitle("\u{66f4}\u{591a}\u{64cd}\u{4f5c}")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("\u{5b8c}\u{6210}") { showsMoreTools = false }
                        .accessibilityIdentifier("video.tools.close")
                }
            }
        }
        .piliPresentationDetents([.large])
    }

    private func tool(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            PiliLabel(title, systemImage: icon)
                .font(.body)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private func quickTool(_ title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VideoDetailActionLabel(title: title, systemImage: icon)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityIdentifier("video.tools.\(id)")
    }

    private func showCoinPicker() {
        Haptics.medium()
        onShowCoinPicker()
    }
}
