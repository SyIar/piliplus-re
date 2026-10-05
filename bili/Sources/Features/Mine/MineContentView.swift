import SwiftUI
import ChunUI

struct MineContentView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @ObservedObject var viewModel: MineViewModel
    @ObservedObject var accountMessageViewModel: AccountMessageCenterViewModel
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var libraryStore: LibraryStore
    let onQRCodeLogin: () -> Void
    let onSMSLogin: () -> Void
    let onWebLogin: () -> Void
    let onOpenRoute: (MineOverlayRoute) -> Void

    var body: some View {
        Form {
            MineAccountSection(
                viewModel: viewModel,
                sessionStore: sessionStore,
                libraryStore: libraryStore,
                onQRCodeLogin: onQRCodeLogin,
                onSMSLogin: onSMSLogin,
                onWebLogin: onWebLogin,
                onOpenRoute: onOpenRoute
            )

            MineAccountLibrarySection(
                viewModel: viewModel,
                accountMessageViewModel: accountMessageViewModel,
                isLoggedIn: sessionStore.isLoggedIn,
                onOpenRoute: onOpenRoute
            )

            MineSettingsSection(
                libraryStore: libraryStore,
                onOpenRoute: onOpenRoute
            )
            Section("播放方式") {
                Button {
                    AppHelper.shared.presentSheet(.sheet) {
                        NavigationStack { PiliOfflineLibraryView() }
                            .environmentObject(dependencies)
                            .environmentObject(libraryStore)
                    }
                } label: {
                    Label { Text("离线下载") } icon: { PikaIcon(PikaIcon.Name.save) }
                }
                Button("自动连播与定时停止") {
                    PiliPlaybackToolsView.present()
                }
            }
            MineAboutSection()
        }
        .tint(libraryStore.appTintColor)
        .formStyle(.grouped)
        .contentMargins(.top, 0, for: .scrollContent)
        .nativeTopScrollEdgeEffect()
    }
}
