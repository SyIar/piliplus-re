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
        .piliSheet(isPresented: $showsMoreTools) {
            VideoDetailMoreToolsSheet(viewModel: viewModel, interactionStore: renderPack.interactionStore)
        }
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
