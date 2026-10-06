import ChunUI
import SwiftUI

struct PiliCollectionQueueView: View {
    @ObservedObject var viewModel: VideoDetailViewModel
    var body: some View {
        NavigationStack {
            PiliList {
                if let queue = viewModel.piliPlaybackQueue {
                    ForEach(Array(queue.bvids.enumerated()), id: \.element) { index, bvid in
                        Button {
                            viewModel.selectPiliQueueVideo(bvid: bvid)
                        } label: {
                            HStack(spacing: 12) {
                                Text("\(index + 1)").monospacedDigit().ccText(font: .cc.sm, color: .cc.mutedForeground)
                                Text(queue.titles[bvid] ?? (bvid == viewModel.detail.bvid ? viewModel.detail.title : bvid))
                                    .ccText(font: .cc.base, color: .cc.foreground)
                                Spacer()
                                if bvid == viewModel.detail.bvid { PiliIcon(systemName: "speaker.wave.2.fill").foregroundStyle(Color.cc.primary) }
                            }.padding(.vertical, 6)
                        }.disabled(viewModel.isAdvancingPiliQueue)
                    }
                    if queue.nextPage != nil {
                        Button("加载更多") { Task { await viewModel.loadMorePiliListenQueue() } }
                            .disabled(viewModel.isAdvancingPiliQueue)
                    }
                } else { Text("当前视频没有合集或播放列表") }
                if viewModel.isAdvancingPiliQueue { ProgressView("加载中") }
                if let error = viewModel.playbackFallbackMessage { Text(error).foregroundStyle(Color.cc.destructive) }
            }
            .navigationTitle(viewModel.piliPlaybackQueue?.title ?? "播放列表")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { AppHelper.shared.dismissSheet() } } }
            .onAppear { viewModel.seedPiliCollectionQueueIfNeeded() }
        }
    }
}
