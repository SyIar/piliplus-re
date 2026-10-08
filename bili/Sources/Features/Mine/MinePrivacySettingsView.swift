import SwiftUI
import ChunUI

struct MinePrivacySettingsView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        PiliForm {
            Section {
                Button("\u{9ed1}\u{540d}\u{5355}\u{7ba1}\u{7406}") {
                    PiliPresentation.present(.sheet) { PiliRelationsView(api: dependencies.api, kind: .blocked) }
                }
            }
            Section {
                Toggle(isOn: Binding(
                    get: { libraryStore.incognitoModeEnabled },
                    set: { libraryStore.setIncognitoModeEnabled($0) }
                )) {
                    MineSettingsLabel("\u{65e0}\u{75d5}\u{6a21}\u{5f0f}", systemImage: "eye.slash")
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.guestModeEnabled },
                    set: { libraryStore.setGuestModeEnabled($0) }
                )) {
                    MineSettingsLabel("\u{6e38}\u{5ba2}\u{63a8}\u{8350}", systemImage: "person.crop.circle.badge.questionmark")
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.multiAccountExperimentEnabled },
                    set: { libraryStore.setMultiAccountExperimentEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        MineSettingsLabel("\u{591a}\u{8d26}\u{53f7}\u{5206}\u{5de5}（\u{5b9e}\u{9a8c}）", systemImage: "person.2.badge.gearshape")

                        Text("\u{4e3a}\u{64ad}\u{653e}、\u{52a8}\u{6001}、\u{4e92}\u{52a8}\u{548c}\u{5386}\u{53f2}\u{5206}\u{914d}\u{8d26}\u{53f7}。\u{5173}\u{95ed}\u{540e}\u{7edf}\u{4e00}\u{4f7f}\u{7528}\u{4e3b}\u{8d26}\u{53f7}，\u{5df2}\u{4fdd}\u{5b58}\u{8d26}\u{53f7}\u{4e0d}\u{4f1a}\u{5220}\u{9664}。")
                            .appTypography(.settingsSubtitle, fallback: .caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text("\u{65e0}\u{75d5}\u{6a21}\u{5f0f}\u{4e0b}\u{65b0}\u{53d1}\u{8d77}\u{7684}\u{64ad}\u{653e}\u{4f7f}\u{7528}\u{6e38}\u{5ba2}\u{8eab}\u{4efd}，\u{4e0d}\u{643a}\u{5e26}\u{767b}\u{5f55} Cookie \u{6216} App \u{51ed}\u{636e}，\u{4e5f}\u{4e0d}\u{8bb0}\u{5f55}\u{6216}\u{4e0a}\u{62a5}\u{89c2}\u{770b}\u{8fdb}\u{5ea6}；\u{9700}\u{8981}\u{767b}\u{5f55}\u{7684}\u{753b}\u{8d28}\u{548c}\u{4ed8}\u{8d39}\u{5185}\u{5bb9}\u{53ef}\u{80fd}\u{65e0}\u{6cd5}\u{64ad}\u{653e}。\u{5df2}\u{5f00}\u{59cb}\u{7684}\u{89c6}\u{9891}\u{9700}\u{91cd}\u{65b0}\u{6253}\u{5f00}\u{540e}\u{751f}\u{6548}。\u{6e38}\u{5ba2}\u{63a8}\u{8350}\u{53ea}\u{5f71}\u{54cd}\u{9996}\u{9875}\u{63a8}\u{8350}：\u{5f00}\u{542f}\u{540e}\u{6309}\u{672a}\u{767b}\u{5f55}\u{72b6}\u{6001}\u{8bf7}\u{6c42}，\u{4e0d}\u{4f7f}\u{7528}\u{8d26}\u{53f7}\u{753b}\u{50cf}；\u{5173}\u{95ed}\u{540e} App \u{7aef}\u{63a8}\u{8350}\u{4f1a}\u{5e26}\u{767b}\u{5f55}\u{72b6}\u{6001}\u{8bf7}\u{6c42}。\u{70b9}\u{8d5e}、\u{6295}\u{5e01}、\u{6536}\u{85cf}、\u{5173}\u{6ce8}\u{7b49}\u{8d26}\u{53f7}\u{64cd}\u{4f5c}\u{4e0d}\u{53d7}\u{5f71}\u{54cd}。")
                    .piliFont(.sm)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(libraryStore.appTintColor)
        .formStyle(.grouped)
        .nativeTopScrollEdgeEffect()
        .navigationTitle("\u{9690}\u{79c1}\u{8bbe}\u{7f6e}")
        .navigationBarTitleDisplayMode(.inline)
    }
}
