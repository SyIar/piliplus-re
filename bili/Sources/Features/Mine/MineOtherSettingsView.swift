import SwiftUI
import ChunUI

struct MineOtherSettingsView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @ObservedObject var libraryStore: LibraryStore
    @AppStorage("piliplus.comments.record") private var recordsComments = true
    var body: some View {
        PiliForm {
            MineSearchSettingsSection(libraryStore: libraryStore)
            Section("\u{4ea4}\u{4e92}\u{4e0e}\u{5185}\u{5bb9}") {
                NavigationLink { PiliQuickFavoriteSettingsView(api: dependencies.api, libraryStore: libraryStore) } label: { Text("\u{5feb}\u{901f}\u{6536}\u{85cf}") }
                NavigationLink { MineContentFilterSettingsView(scope: .community, libraryStore: libraryStore) } label: { Text("\u{52a8}\u{6001}\u{4e0e}\u{8bc4}\u{8bba}") }
                Toggle("\u{4fdd}\u{5b58}\u{5df2}\u{53d1}\u{9001}\u{8bc4}\u{8bba}", isOn: $recordsComments)
                NavigationLink { PiliVisibilitySettingsView() } label: { Text("\u{53d1}\u{5e03}\u{53ef}\u{89c1}\u{6027}\u{68c0}\u{67e5}") }
            }
            Section("\u{5b58}\u{50a8}") {
                NavigationLink { ResourceCacheManagementView() } label: { Text("\u{8d44}\u{6e90}\u{7f13}\u{5b58}") }
            }
            Section {
                NavigationLink {
                    PiliForm {
                        MinePlaybackDiagnosticsSection(libraryStore: libraryStore)
                        MineDisplayDiagnosticsSection(libraryStore: libraryStore)
                        Section { NavigationLink { MineHomeRecommendDiagnosticsView() } label: { Text("\u{63a8}\u{8350}\u{8bca}\u{65ad}") } }
                    }.navigationTitle("\u{9ad8}\u{7ea7}\u{4e0e}\u{8bca}\u{65ad}")
                } label: { Text("\u{9ad8}\u{7ea7}\u{4e0e}\u{8bca}\u{65ad}") }
            }
        }
    }
}
