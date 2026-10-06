import SwiftUI

struct ResourceLoadingExperimentSettingsView: View {
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        PiliForm {
            Section("实验功能") {
                featureToggle(
                    title: "断点续播预热",
                    systemImage: "goforward",
                    isOn: Binding(
                        get: { libraryStore.resourceLoadingResumePacketWarmupEnabled },
                        set: { libraryStore.setResourceLoadingResumePacketWarmupEnabled($0) }
                    ),
                    detail: "提前加载续播位置，减少等待。"
                )
            }

            Section {
                NavigationLink {
                    ResourceLoadingDiagnosticsView(libraryStore: libraryStore)
                } label: {
                    PlainSettingsNavigationRow(
                        title: "资源加载诊断",
                        subtitle: "加载次数、耗时与最近事件",
                    )
                }
            } footer: {
                Text("诊断仅记录加载统计与功能状态。")
            }
        }
        .tint(libraryStore.appTintColor)
        .formStyle(.grouped)
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
    }

    private func featureToggle(
        title: String,
        systemImage: String,
        isOn: Binding<Bool>,
        detail: String
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 4) {
                MineSettingsLabel(title, systemImage: systemImage)
                Text(detail)
                    .appTypography(.settingsSubtitle, fallback: .caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
