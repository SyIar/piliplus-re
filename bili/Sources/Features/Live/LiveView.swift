import SwiftUI

struct LiveView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @StateObject private var holder = LiveViewModelHolder()
    @StateObject private var pullRefreshSettings = PullRefreshRuntimeSettingsStore()

    var body: some View {
        Group {
            if let viewModel = holder.viewModel {
                LiveFeedView(
                    viewModel: viewModel,
                    pullRefreshTriggerDistance: CGFloat(pullRefreshSettings.triggerDistance)
                )
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        LiveFeedSkeletonList(horizontalPadding: 12, topPadding: 18)
                    }
                }
                .nativeTopScrollEdgeEffect()
                .background(Color(.systemBackground))
                .task {
                    holder.configure(api: dependencies.api)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { PiliLiveExploreView(api: dependencies.api) } label: { Label("分区与关注", systemImage: "square.grid.2x2") }
            }
        }
        .task {
            pullRefreshSettings.bind(dependencies.libraryStore)
        }
    }
}
