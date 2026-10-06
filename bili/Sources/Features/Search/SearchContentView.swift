import SwiftUI
import ChunUI

struct SearchContentView: View {
    @ObservedObject var viewModel: SearchViewModel
    let showsHotSearches: Bool
    @ObservedObject var accessoryStore: SearchBottomAccessoryStore

    var body: some View {
        SearchListView(
            viewModel: viewModel,
            showsHotSearches: showsHotSearches
        )
        .overlay {
            if case .failed(let message) = viewModel.state, viewModel.results.isEmpty {
                ErrorStateView(title: "搜索失败", message: message) {
                    Task { await viewModel.search() }
                }
            }
        }
        .task(id: viewModel.showsDiscovery) {
            accessoryStore.attach(viewModel)
            await loadDiscoveryStateIfNeeded()
        }
        .onDisappear {
            accessoryStore.isSearchFocused = false
            accessoryStore.isKeyboardVisible = false
        }
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                SearchFilterCapsule(viewModel: viewModel)
            }
        }
    }

    private func loadDiscoveryStateIfNeeded() async {
        await viewModel.restoreDiscoveryState(loadHotSearches: showsHotSearches)
    }
}

struct SearchTabBottomAccessory: View {
    @ObservedObject var store: SearchBottomAccessoryStore

    @ViewBuilder
    var body: some View {
        if let viewModel = store.viewModel {
            SearchFilterCapsule(viewModel: viewModel)
                .frame(maxWidth: .infinity, minHeight: 40)
                .padding(.horizontal, 16)
        }
    }
}

private struct SearchFilterCapsule: View {
    @ObservedObject var viewModel: SearchViewModel

    var body: some View {
        HStack(spacing: 0) {
            scopeMenu
            orderMenu
            if viewModel.selectedScope.supportsOrder { durationMenu }
        }
        .piliFont(.base).fontWeight(.medium)
        .lineLimit(1)
        .frame(maxWidth: .infinity, minHeight: 40)
        .foregroundStyle(.primary)
    }

    private var scopeMenu: some View {
        Menu {
            ForEach(SearchScope.allCases) { scope in
                Button {
                    Task {
                        await viewModel.selectScope(scope, animation: .smooth(duration: 0.28))
                    }
                } label: {
                    PiliLabel(
                        scope.title,
                        systemImage: scope == viewModel.selectedScope
                            ? "checkmark"
                            : scope.systemImage
                    )
                }
            }
        } label: {
            filterLabel(title: viewModel.selectedScope.title)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 40)
        .contentShape(Rectangle())
        .accessibilityLabel("搜索类型")
        .accessibilityValue(viewModel.selectedScope.title)
    }

    private var orderMenu: some View {
        Menu {
            ForEach(SearchSortOrder.allCases) { order in
                Button {
                    Task { await viewModel.selectOrder(order) }
                } label: {
                    PiliLabel(
                        order.title,
                        systemImage: order == viewModel.selectedOrder
                            ? "checkmark"
                            : "arrow.up.arrow.down"
                    )
                }
            }
        } label: {
            filterLabel(title: viewModel.selectedOrder.title)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 40)
        .contentShape(Rectangle())
        .disabled(!viewModel.selectedScope.supportsOrder)
        .foregroundStyle(viewModel.selectedScope.supportsOrder ? .primary : .secondary)
        .accessibilityLabel("排序方式")
        .accessibilityValue(viewModel.selectedOrder.title)
    }

    private var durationMenu: some View {
        Menu {
            ForEach(PiliSearchDuration.allCases) { duration in
                Button { Task { await viewModel.selectDuration(duration) } } label: {
                    PiliLabel(duration.title, systemImage: duration == viewModel.selectedDuration ? "checkmark" : "clock")
                }
            }
        } label: { filterLabel(title: viewModel.selectedDuration.title) }
            .frame(maxWidth: .infinity, minHeight: 40).buttonStyle(.plain)
            .accessibilityLabel("视频时长").accessibilityValue(viewModel.selectedDuration.title)
    }

    private func filterLabel(title: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
            PiliIcon(systemName: "chevron.down")
                .piliFont(.sm).fontWeight(.bold)
        }
        .fixedSize(horizontal: true, vertical: false)
        .contentShape(Rectangle())
    }
}
