import SwiftUI

struct HomeFeedModeMenu: View {
    let currentMode: HomeFeedMode
    let onSelectMode: (HomeFeedMode) -> Void

    var body: some View {
        Menu {
            ForEach(HomeFeedMode.allCases, id: \.self) { mode in
                Button {
                    onSelectMode(mode)
                } label: {
                    Label(mode.title, systemImage: currentMode == mode ? "checkmark" : mode.systemImage)
                }
            }
            Divider()
            NavigationLink { PiliPGCCatalogueView() } label: { Label("番剧与影视", systemImage: "film") }
        } label: {
            HStack(spacing: 6) {
                Text(currentMode.title).font(.system(size: 22, weight: .bold))
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.primary)
        }
        .tint(.primary)
        .accessibilityLabel("首页内容")
        .accessibilityValue(currentMode.title)
    }
}
