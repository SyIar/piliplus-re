import SwiftUI

struct SearchResultTabs: View {
    @ObservedObject var viewModel: SearchViewModel

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(SearchScope.resultTabs) { scope in
                    Button {
                        Task { await viewModel.selectScope(scope) }
                    } label: {
                        Text(scope.title)
                            .font(.subheadline.weight(viewModel.selectedScope == scope ? .semibold : .regular))
                            .foregroundStyle(viewModel.selectedScope == scope ? Color.accentColor : .secondary)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .background(viewModel.selectedScope == scope ? Color.accentColor.opacity(0.12) : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(viewModel.selectedScope == scope ? .isSelected : [])
                    .accessibilityIdentifier("search.tab.\(scope.rawValue)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .background(.bar)
    }
}
