import ChunUI
import SwiftUI

struct PiliVideoLibraryActions: View {
    let viewModel: VideoDetailViewModel
    @ObservedObject var descriptionStore: VideoDetailDescriptionRenderStore
    @State private var isAdding = false
    @State private var wasAdded = false

    var body: some View {
        Button {
            guard !isAdding, !wasAdded else { return }
            isAdding = true
            Task { await addToWatchLater() }
        } label: {
            VideoDetailActionLabel(
                title: wasAdded ? "\u{5df2}\u{6dfb}\u{52a0}" : "\u{7a0d}\u{540e}\u{518d}\u{770b}",
                systemImage: wasAdded ? "checkmark" : "clock",
                isBusy: isAdding
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(wasAdded ? Color.cc.primary : .primary)
        .disabled(isAdding || wasAdded)
        .accessibilityLabel("\u{5c06}\(descriptionStore.titleText)\u{52a0}\u{5165}\u{7a0d}\u{540e}\u{518d}\u{770b}")
        .accessibilityIdentifier("video.tools.watchLater")
        .onChange(of: viewModel.detail.bvid) { _, _ in wasAdded = false }
    }

    private func addToWatchLater() async {
        defer { isAdding = false }
        let bvid = viewModel.detail.bvid
        do {
            try await viewModel.api.addToWatchLater(bvid: bvid)
            guard viewModel.detail.bvid == bvid else { return }
            wasAdded = true
            CCToastCenter.shared.show(.success, "\u{5df2}\u{52a0}\u{5165}\u{7a0d}\u{540e}\u{518d}\u{770b}")
        } catch {
            CCToastCenter.shared.show(.error, error.localizedDescription)
        }
    }
}
