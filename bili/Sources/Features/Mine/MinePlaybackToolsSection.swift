import SwiftUI
import ChunUI

struct MinePlaybackToolsSection: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        Section("\u{64ad}\u{653e}\u{5de5}\u{5177}") {
            NavigationLink { PiliDanmakuRulesView(api: dependencies.api) } label: { Text("\u{5f39}\u{5e55}\u{5c4f}\u{853d}") }
            Button("\u{81ea}\u{52a8}\u{8fde}\u{64ad}\u{4e0e}\u{5b9a}\u{65f6}\u{505c}\u{6b62}") { PiliPlaybackToolsView.present() }
            Toggle(
                isOn: Binding(
                    get: { libraryStore.sponsorBlockEnabled },
                    set: { libraryStore.setSponsorBlockEnabled($0) }
                )
            ) {
                MineSettingsLabel("\u{7a7a}\u{964d}\u{52a9}\u{624b}", systemImage: "forward.end")
            }

            NavigationLink { PiliSponsorSettingsView() } label: { PiliLabel("\u{7a7a}\u{964d}\u{5206}\u{7c7b}\u{7b56}\u{7565}", systemImage: "slider.horizontal.3") }
            Toggle(
                isOn: Binding(
                    get: { libraryStore.playerControlEdgeScrimEnabled },
                    set: { libraryStore.setPlayerControlEdgeScrimEnabled($0) }
                )
            ) {
                MineSettingsLabel("\u{64ad}\u{653e}\u{63a7}\u{4ef6}\u{8fb9}\u{7f18}\u{906e}\u{7f69}", systemImage: "rectangle.dashed")
            }

            Toggle(
                isOn: Binding(
                    get: { libraryStore.showsVideoDetailPinnedProgressBar },
                    set: { libraryStore.setShowsVideoDetailPinnedProgressBar($0) }
                )
            ) {
                MineSettingsLabel("\u{7a97}\u{53e3}\u{5e95}\u{90e8}\u{8fdb}\u{5ea6}\u{6761}", systemImage: "line.3.horizontal.decrease")
            }

            PiliSettingPicker(
                selection: Binding(
                    get: { libraryStore.videoListenPlaylistSortOrder },
                    set: { libraryStore.setVideoListenPlaylistSortOrder($0) }
                )
            ) {
                ForEach(VideoListenPlaylistSortOrder.allCases) { order in
                    MineSettingsLabel(order.title, systemImage: order.systemImage)
                        .tag(order)
                }
            } label: {
                MineSettingsLabel("\u{542c}\u{89c6}\u{9891}\u{5217}\u{8868}\u{6392}\u{5e8f}", systemImage: libraryStore.videoListenPlaylistSortOrder.systemImage)
            }
            .pickerStyle(.menu)

            NavigationLink {
                ResourceCacheManagementView()
            } label: {
                PlainSettingsNavigationRow(
                    title: "\u{8d44}\u{6e90}\u{7f13}\u{5b58}",
                    subtitle: "\u{56fe}\u{7247}、\u{63a5}\u{53e3}、\u{89c6}\u{9891}\u{5206}\u{7247}\u{7f13}\u{5b58}",
                )
            }
        }
    }
}
