import SwiftUI

struct PiliSettingsSearchView: View {
    let onOpenRoute: (MineOverlayRoute) -> Void
    @State private var query = ""
    var body: some View {
        PiliList {
            ForEach(PiliSettingsCategory.matching(query)) { category in
                NavigationLink { PiliSettingsCategoryView(category: category) } label: {
                    SettingsNavigationRow(title: category.title, subtitle: category.subtitle, systemImage: category.icon)
                }
            }
            if PiliSettingsCategory.matching(query).isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("\u{641c}\u{7d22}\u{8bbe}\u{7f6e}")
        .searchable(text: $query, prompt: "\u{641c}\u{7d22}\u{8bbe}\u{7f6e}\u{540d}\u{79f0}\u{6216}\u{5173}\u{952e}\u{8bcd}")
    }
}
