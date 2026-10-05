import SwiftUI
import ChunUI

struct MineAccountSection: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @ObservedObject var viewModel: MineViewModel
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var libraryStore: LibraryStore
    let onQRCodeLogin: () -> Void
    let onSMSLogin: () -> Void
    let onWebLogin: () -> Void
    let onOpenRoute: (MineOverlayRoute) -> Void

    var body: some View {
        Section {
            if sessionStore.isLoggedIn {
                MineLoggedInHeaderView(
                    avatarURLString: sessionStore.user?.face,
                    username: sessionStore.user?.uname ?? "Logged in",
                    uidText: "UID \(sessionStore.user?.mid ?? 0)"
                )

                Button {
                    AppHelper.shared.presentSheet(.sheet) { PiliProfileView(api: dependencies.api) }
                } label: { Label("编辑个人资料", systemImage: "person.crop.circle.badge.pencil") }

                Button {
                    AppHelper.shared.presentSheet(.sheet) {
                        PiliRelationsView(api: dependencies.api)
                            .environmentObject(dependencies)
                            .environmentObject(libraryStore)
                            .environmentObject(sessionStore)
                    }
                } label: { Label("关注、粉丝与黑名单", systemImage: "person.2") }

                if libraryStore.multiAccountExperimentEnabled {
                    MineOverlayNavigationButton {
                        onOpenRoute(.multiAccountSettings)
                    } label: {
                        Label("多账号与用途", systemImage: "person.2.badge.gearshape")
                    }
                }

                Button(role: .destructive) {
                    viewModel.logout()
                } label: {
                    Label(
                        libraryStore.multiAccountExperimentEnabled ? "退出所有账号" : "退出登录",
                        systemImage: "rectangle.portrait.and.arrow.right"
                    )
                }
            } else {
                MineLoginPanelView(
                    message: viewModel.loginMessage,
                    onQRCodeLogin: onQRCodeLogin,
                    onSMSLogin: onSMSLogin,
                    onWebLogin: onWebLogin
                )
            }
        }
    }

}
