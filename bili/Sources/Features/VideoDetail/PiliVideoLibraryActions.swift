import ChunUI
import SwiftUI

struct PiliVideoLibraryActions: View {
    let viewModel: VideoDetailViewModel
    @ObservedObject var descriptionStore: VideoDetailDescriptionRenderStore
    @State private var isAdding = false

    var body: some View {
        CCNeoButton("加入稍后再看", variant: .ghost, icon: "playlist-add", disabled: isAdding) {
            guard !isAdding else { return }
            isAdding = true
            defer { isAdding = false }
            let bvid = viewModel.detail.bvid
            do {
                try await viewModel.api.addToWatchLater(bvid: bvid)
                CCToastCenter.shared.show(.success, "已加入稍后再看")
            } catch {
                CCToastCenter.shared.show(.error, error.localizedDescription)
            }
        }
        .accessibilityLabel("将\(descriptionStore.titleText)加入稍后再看")
    }
}
