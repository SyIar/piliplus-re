import SwiftUI

struct PiliFullscreenVideoReactions: View {
    let viewModel: VideoDetailViewModel
    @ObservedObject var store: VideoDetailInteractionRenderStore
    let markInteraction: () -> Void
    @State private var errorMessage: String?

    var body: some View {
        HStack(spacing: 0) {
            if !viewModel.detail.piliIsCourse { PiliTripleButton(viewModel: viewModel, store: store) }
            PiliGlassPlayerButton(symbol: store.interactionState.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                                  title: store.interactionState.isLiked ? "取消点赞" : "点赞", grouped: true) {
                markInteraction()
                Task { if !(await viewModel.toggleLike()) { errorMessage = store.interactionMessage ?? "点赞失败，请重试" } }
            }
            .disabled(store.isMutatingLike)
            PiliGlassPlayerButton(symbol: store.interactionState.isFavorited ? "bookmark.fill" : "bookmark",
                                  title: store.interactionState.isFavorited ? "取消收藏" : "收藏", grouped: true) {
                markInteraction()
                Task { if !(await viewModel.toggleFavorite()) { errorMessage = store.interactionMessage ?? "收藏失败，请重试" } }
            }
            .disabled(store.isMutatingFavorite)
        }
        .piliLiquidGlass(in: Capsule(), overVideo: true, interactive: true)
        .piliAlert("操作失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            PiliAlertButton("好", role: .cancel) { errorMessage = nil }
        } message: { errorMessage ?? "" }
    }
}
