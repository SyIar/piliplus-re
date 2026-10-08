import SwiftUI

struct MineDisplayDiagnosticsSection: View {
    @ObservedObject var libraryStore: LibraryStore
    var body: some View {
        Section("\u{754c}\u{9762}\u{8bca}\u{65ad}") {
            Toggle(isOn: Binding(
                get: { libraryStore.remoteImageDiagnosticsEnabled },
                set: { libraryStore.setRemoteImageDiagnosticsEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("\u{56fe}\u{7247}\u{8bca}\u{65ad}", systemImage: "chart.bar.xaxis")

                    Text("\u{8bb0}\u{5f55}\u{52a0}\u{8f7d}\u{7edf}\u{8ba1}，\u{4e0d}\u{542b}\u{56fe}\u{7247}、\u{94fe}\u{63a5}\u{6216}\u{8d26}\u{53f7}\u{4fe1}\u{606f}。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            NavigationLink {
                RemoteImageDiagnosticsView(libraryStore: libraryStore)
            } label: {
                MineSettingsLabel("\u{67e5}\u{770b}\u{56fe}\u{7247}\u{8bca}\u{65ad}", systemImage: "chart.bar.xaxis")
            }

            Toggle(isOn: Binding(
                get: { libraryStore.dynamicCommentHitAreaVisualizationExperimentEnabled },
                set: { libraryStore.setDynamicCommentHitAreaVisualizationExperimentEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("\u{663e}\u{793a}\u{8bc4}\u{8bba}\u{70b9}\u{51fb}\u{533a}\u{57df}", systemImage: "hand.tap")

                    Text("\u{6807}\u{8bb0}\u{56de}\u{590d}\u{4e0e}\u{64cd}\u{4f5c}\u{7684}\u{70b9}\u{51fb}\u{533a}\u{57df}。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
