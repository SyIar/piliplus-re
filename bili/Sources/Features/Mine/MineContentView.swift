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
        PiliForm {
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
                    PiliPresentation.present(.sheet) {
                        NavigationStack { PiliOfflineLibraryView() }
                            .environmentObject(dependencies)
                            .environmentObject(libraryStore)
                    }
                } label: {
                    Label { Text("离线下载") } icon: { PikaIcon(PikaIcon.Name.save) }
                }
                Button {
                    PiliPresentation.present(.sheet) { PiliDLNAView() }
                } label: { Label { Text("投屏遥控") } icon: { PikaIcon("screen-check") } }
                Button("自动连播与定时停止") {
                    PiliPlaybackToolsView.present()
                }
            }
            Section("数据") {
                NavigationLink { PiliCollectedContentView() } label: { PiliLabel("追番与其他收藏", systemImage: "star.rectangle.on.rectangle") }
                NavigationLink { PiliCommentArchiveView() } label: { PiliLabel("我的评论", systemImage: "text.bubble") }
                NavigationLink { PiliAccountUtilitiesView() } label: { PiliLabel("账号记录与空间隐私", systemImage: "person.text.rectangle") }
                NavigationLink { PiliCoursesView(api: dependencies.api) } label: { PiliLabel("收藏的课程", systemImage: "graduationcap") }
                Button {
                    PiliPresentation.present(.sheet) { PiliNotesLibraryView(api: dependencies.api) }
                } label: { Label { Text("我的笔记") } icon: { PikaIcon(PikaIcon.Name.note) } }

                Button {
                    PiliPresentation.present(.sheet) { PiliBackupSettingsView(libraryStore: libraryStore) }
                } label: {
                    Label { Text("设置备份与 WebDAV") } icon: { PikaIcon(PikaIcon.Name.folder) }
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
