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

            CCNeoButton("离线下载", variant: .ghost, icon: PikaIcon.Name.save) {
                AppHelper.shared.presentSheet(.sheet) { PiliDownloadSheet(viewModel: viewModel) }
            }

            CCNeoButton("字幕", variant: .ghost, icon: PikaIcon.Name.fileText) {
                PiliSubtitleSettingsView.present(controller: viewModel.piliSubtitles) { viewModel.stablePlayerViewModel?.seek(to: $0) }
            }

            CCNeoButton("互动分支", variant: .ghost, icon: PikaIcon.Name.folder) {
                AppHelper.shared.presentSheet(.sheet) { PiliInteractiveHistoryView(controller: viewModel.piliInteractive) }
            }

            if let aid = viewModel.detail.aid {
                HStack {
                    CCNeoButton("记笔记", variant: .ghost, icon: PikaIcon.Name.edit) {
                        AppHelper.shared.presentSheet(.sheet) {
                            NavigationStack {
                                PiliNoteEditorView(api: viewModel.api, aid: aid, initialTitle: viewModel.detail.title,
                                                   noteID: nil, initialText: "", time: viewModel.stablePlayerViewModel?.currentTime)
                            }
                        }
                    }
                    CCNeoButton("视频笔记", variant: .ghost, icon: PikaIcon.Name.note) {
                        AppHelper.shared.presentSheet(.sheet) { PiliNotesLibraryView(api: viewModel.api, video: viewModel.detail) }
                    }
                }
            }

            VideoDetailInteractionNotice(store: renderPack.interactionStore)
            VideoDetailPlayURLNotice(
                placeholderStore: renderPack.placeholderStore,
                retry: renderPack.actions.retryPlayURL
            )
        }
        .frame(width: contentWidth, alignment: .leading)
    }

    private func showCoinPicker() {
        Haptics.medium()
        onShowCoinPicker()
    }
}
