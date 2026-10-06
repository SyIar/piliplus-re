import SwiftUI
import ChunUI

struct UploaderDynamicsSection: View {
    let api: BiliAPIClient
    @ObservedObject var viewModel: UploaderViewModel
    let contentWidth: CGFloat

    private var lastItemID: String? {
        viewModel.dynamicItems.last?.id
    }

    private var cardWidth: CGFloat? {
        guard contentWidth > 32 else { return nil }
        return contentWidth - 32
    }

    var body: some View {
        LazyVStack(spacing: 0) {
            NavigationLink { PiliCoursesView(api: api, ownerMID: viewModel.seedOwner.mid) } label: { PiliLabel("用户课程", systemImage: "graduationcap").frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12) }
            NavigationLink {
                PiliUserArticlesView(api: api, mid: viewModel.seedOwner.mid)
            } label: { PiliLabel("用户图文", systemImage: "doc.richtext").frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12) }
            NavigationLink {
                PiliDynamicSearchView(api: api, mid: viewModel.seedOwner.mid)
            } label: { PiliLabel("搜索用户动态", systemImage: "magnifyingglass").frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12) }
            if viewModel.dynamicItems.isEmpty && viewModel.dynamicState.isLoading {
                DynamicFeedSkeletonList()
                    .padding(.horizontal, 16)
            } else if viewModel.dynamicItems.isEmpty {
                emptyOrErrorState
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            } else {
                ForEach(viewModel.dynamicItems) { item in
                    VStack(spacing: 0) {
                        DynamicFeedCard(
                            item: item,
                            api: api,
                            contentWidth: cardWidth
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .dynamicLoadMoreTask(if: item.id == lastItemID, id: item.id) {
                            await viewModel.loadMoreDynamicsIfNeeded(current: item)
                        }

                        if item.id != lastItemID {
                            Divider()
                                .padding(.leading, 66)
                        }
                    }
                }

                footer
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var emptyOrErrorState: some View {
        if case .failed(let message) = viewModel.dynamicState {
            ErrorStateView(title: "动态加载失败", message: message) {
                Task { await viewModel.refreshDynamics() }
            }
        } else {
            EmptyStateView(title: "暂无动态", systemImage: "sparkles", message: "这个 UP 主还没有可展示的动态。")
        }
    }

    @ViewBuilder
    private var footer: some View {
        if viewModel.dynamicState.isLoading {
            VStack(spacing: 0) {
                ForEach(0..<2, id: \.self) { index in
                    DynamicFeedSkeletonCard()
                        .allowsHitTesting(false)

                    if index != 1 {
                        Divider()
                            .padding(.leading, 66)
                    }
                }
            }
        } else if viewModel.hasMoreDynamicItems {
            Button {
                Task { await viewModel.loadMoreDynamics() }
            } label: {
                PiliLabel("加载更多", systemImage: "chevron.down")
                    .piliFont(.base).fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        } else {
            Text("没有更多动态了")
                .piliFont(.sm)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
    }
}
