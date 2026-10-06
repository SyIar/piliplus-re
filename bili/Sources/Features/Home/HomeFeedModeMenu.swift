import SwiftUI
import ChunUI

struct HomeFeedModeMenu: View {
    let currentMode: HomeFeedMode
    let onSelectMode: (HomeFeedMode) -> Void

    var body: some View {
        Menu {
            ForEach(HomeFeedMode.allCases, id: \.self) { mode in
                Button {
                    onSelectMode(mode)
                } label: {
                    PiliLabel(mode.title, systemImage: currentMode == mode ? "checkmark" : mode.systemImage)
                }
            }
            Divider()
            NavigationLink { PiliDiscoveryView() } label: { PiliLabel("每周必看与排行榜", systemImage: "chart.bar.xaxis") }
            NavigationLink { PiliPGCCatalogueView() } label: { PiliLabel("番剧与影视", systemImage: "film") }
        } label: {
            HStack(spacing: 6) {
                Text(currentMode.title).piliFont(.lgBold)
                PiliIcon(systemName: "chevron.down", size: 10).piliFont(.smBold)
            }
            .foregroundStyle(.primary)
        }
        .tint(.primary)
        .accessibilityLabel("首页内容")
        .accessibilityValue(currentMode.title)
    }
}
