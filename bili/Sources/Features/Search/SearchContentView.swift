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
                SearchFilterButton(viewModel: viewModel)
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
            SearchFilterButton(viewModel: viewModel)
                .padding(.horizontal, 12)
        }
    }
}

struct SearchFilterButton: View {
    @ObservedObject var viewModel: SearchViewModel
    @State private var showsFilters = false

    var body: some View {
        Button {
            showsFilters = true
        } label: {
            HStack(spacing: 8) {
                PiliIcon(systemName: "slider.horizontal.3", size: 20)
                Text("\u{7b5b}\u{9009}")
                    .fontWeight(.semibold)
                    .fixedSize()
                Text(viewModel.selectedScope.title)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if activeFilterCount > 0 {
                    Text(activeFilterCount, format: .number)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.tint.opacity(0.12), in: Capsule())
                }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\u{641c}\u{7d22}\u{7b5b}\u{9009}")
        .accessibilityValue(selectionDescription)
        .accessibilityIdentifier("search.filters.open")
        .piliSheet(isPresented: $showsFilters) {
            SearchFiltersSheet(viewModel: viewModel)
        }
    }

    private var activeFilterCount: Int {
        (viewModel.selectedScope == .comprehensive ? 0 : 1)
            + (viewModel.selectedScope.supportsOrder && viewModel.selectedOrder != .comprehensive ? 1 : 0)
            + (viewModel.selectedScope.supportsOrder && viewModel.selectedDuration != .any ? 1 : 0)
    }

    private var selectionDescription: String {
        guard viewModel.selectedScope.supportsOrder else { return viewModel.selectedScope.title }
        return [viewModel.selectedScope.title, viewModel.selectedOrder.title, viewModel.selectedDuration.title]
            .joined(separator: ", ")
    }
}
