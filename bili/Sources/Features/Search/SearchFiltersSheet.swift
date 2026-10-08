import SwiftUI

/// Selections are staged so one Apply performs at most one search.
struct SearchFiltersSheet: View {
    @ObservedObject var viewModel: SearchViewModel
    @PiliDismiss private var dismiss
    @State private var scope: SearchScope
    @State private var order: SearchSortOrder
    @State private var duration: PiliSearchDuration

    init(viewModel: SearchViewModel) {
        self.viewModel = viewModel
        _scope = State(initialValue: viewModel.selectedScope)
        _order = State(initialValue: viewModel.selectedOrder)
        _duration = State(initialValue: viewModel.selectedDuration)
    }

    var body: some View {
        NavigationStack {
            PiliForm {
                Section("\u{5185}\u{5bb9}\u{7c7b}\u{578b}") {
                    Picker("\u{5185}\u{5bb9}\u{7c7b}\u{578b}", selection: $scope) {
                        ForEach(SearchScope.resultTabs) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .accessibilityIdentifier("search.filters.scope")
                }
                if scope.supportsOrder {
                    Section("\u{6392}\u{5e8f}\u{4e0e}\u{65f6}\u{957f}") {
                        Picker("\u{6392}\u{5e8f}\u{65b9}\u{5f0f}", selection: $order) {
                            ForEach(SearchSortOrder.allCases) { Text($0.title).tag($0) }
                        }
                        .accessibilityIdentifier("search.filters.order")
                        Picker("\u{89c6}\u{9891}\u{65f6}\u{957f}", selection: $duration) {
                            ForEach(PiliSearchDuration.allCases) { Text($0.title).tag($0) }
                        }
                        .accessibilityIdentifier("search.filters.duration")
                    }
                }
                Section {
                    Button("\u{6062}\u{590d}\u{9ed8}\u{8ba4}") {
                        scope = .video
                        order = .comprehensive
                        duration = .any
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("search.filters.reset")
                }
            }
            .navigationTitle("\u{641c}\u{7d22}\u{7b5b}\u{9009}")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        PiliIcon(systemName: "xmark", size: 20)
                    }
                    .accessibilityLabel("\u{53d6}\u{6d88}")
                    .accessibilityIdentifier("search.filters.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("\u{5e94}\u{7528}") {
                        let selection = (scope, order, duration)
                        dismiss()
                        Task {
                            await viewModel.applyFilters(scope: selection.0, order: selection.1, duration: selection.2)
                        }
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("search.filters.apply")
                }
            }
        }
        .piliPresentationDetents([.large])
    }
}
