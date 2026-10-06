import SwiftUI
import ChunUI

struct VideoDetailSummaryCard: View {
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
                onShareTap: renderPack.actions.share
            )

            if showsNetworkDiagnosticsButton {
                VideoDetailNetworkDiagnosticsButton(action: onShowNetworkDiagnostics)
            }

            if !viewModel.detail.isPGCEpisode {
                PiliVideoLibraryActions(viewModel: viewModel, descriptionStore: renderPack.descriptionStore)
            }

            if let seasonID = viewModel.detail.piliUGCSeason?.id {
                PiliSeasonActionsView(api: viewModel.api, seasonID: seasonID, collectionBVID: viewModel.detail.bvid)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    tool("截图与动图", icon: "camera") { PiliMediaCaptureView.present(viewModel) }
                    tool("原声翻译", icon: "waveform") {
                        AppHelper.shared.presentSheet(.sheet) { NavigationStack { PiliAudioLanguageView(viewModel: viewModel) } }
                    }
                    tool("离线下载", icon: "arrow.down.circle") {
                        AppHelper.shared.presentSheet(.sheet) { PiliDownloadSheet(viewModel: viewModel) }
                    }
                    tool("投屏", icon: "tv") {
                        AppHelper.shared.presentSheet(.sheet) { PiliDLNAView(source: { try .online(viewModel) }) }
                    }
                    tool("字幕", icon: "captions.bubble") {
                        PiliSubtitleSettingsView.present(controller: viewModel.piliSubtitles) { seconds in
                            guard let player = viewModel.stablePlayerViewModel else { return }
                            player.seek(by: seconds - player.currentTime)
                        }
                    }
                    if viewModel.piliPlaybackQueue != nil || viewModel.detail.piliUGCSeason != nil {
                        tool("播放列表", icon: "list.bullet") {
                            AppHelper.shared.presentSheet(.sheet) { PiliCollectionQueueView(viewModel: viewModel) }
                        }
                    }
                    tool("互动分支", icon: "point.topleft.down.to.point.bottomright.curvepath") {
                        AppHelper.shared.presentSheet(.sheet) { PiliInteractiveHistoryView(controller: viewModel.piliInteractive) }
                    }
                    if let aid = viewModel.detail.aid {
                        tool("记笔记", icon: "square.and.pencil") {
                            AppHelper.shared.presentSheet(.sheet) {
                                NavigationStack {
                                    PiliNoteEditorView(api: viewModel.api, aid: aid, initialTitle: viewModel.detail.title,
                                                       noteID: nil, initialText: "", time: viewModel.stablePlayerViewModel?.currentTime)
                                }
                            }
                        }
                        tool("举报视频", icon: "exclamationmark.bubble") {
                            AppHelper.shared.presentSheet(.sheet) {
                                NavigationStack { PiliAccountWebView(api: viewModel.api, url: URL(string: "https://www.bilibili.com/appeal/?avid=\(aid)")!, title: "举报视频") }
                            }
                        }
                        tool("视频笔记", icon: "note.text") {
                            AppHelper.shared.presentSheet(.sheet) { PiliNotesLibraryView(api: viewModel.api, video: viewModel.detail) }
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            VideoDetailInteractionNotice(store: renderPack.interactionStore)
            VideoDetailPlayURLNotice(
                placeholderStore: renderPack.placeholderStore,
                retry: renderPack.actions.retryPlayURL
            )
        }
        .frame(width: contentWidth, alignment: .leading)
    }

    private func tool(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14).frame(height: 36)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .piliLiquidGlass(in: Capsule(), interactive: true)
    }

    private func showCoinPicker() {
        Haptics.medium()
        onShowCoinPicker()
    }
}
