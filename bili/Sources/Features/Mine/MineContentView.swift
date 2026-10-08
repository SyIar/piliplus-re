import SwiftUI
import ChunUI

struct MineContentView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var viewModel: MineViewModel
    @ObservedObject var accountMessageViewModel: AccountMessageCenterViewModel
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var libraryStore: LibraryStore
    let onQRCodeLogin: () -> Void
    let onSMSLogin: () -> Void
    let onWebLogin: () -> Void
    let onOpenRoute: (MineOverlayRoute) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                accountHeader
                if sessionStore.isLoggedIn { accountStatistics }
                shortcuts
                Divider()
                favorites
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 32)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .piliPageChrome()
        .toolbar { ToolbarItemGroup(placement: .topBarTrailing) {
            Button { onOpenRoute(.accountMessages) } label: { PiliIcon(systemName: "bubble.left.and.bubble.right") }
                .accessibilityLabel("\u{6d88}\u{606f}").disabled(!sessionStore.isLoggedIn)
                .accessibilityValue(accountMessageViewModel.totalUnreadBadgeText ?? "")
            Button { libraryStore.setIncognitoModeEnabled(!libraryStore.incognitoModeEnabled) } label: {
                PiliIcon(systemName: libraryStore.incognitoModeEnabled ? "eye.slash.fill" : "eye.slash")
            }.accessibilityLabel("\u{65e0}\u{75d5}\u{6a21}\u{5f0f}").accessibilityValue(libraryStore.incognitoModeEnabled ? "\u{5f00}\u{542f}" : "\u{5173}\u{95ed}")
            Menu { libraryMenu } label: { PiliIcon(systemName: "ellipsis") }.accessibilityLabel("\u{66f4}\u{591a}\u{8d26}\u{53f7}\u{5185}\u{5bb9}")
            Button { onOpenRoute(.settings) } label: { PiliIcon(systemName: "gearshape") }
                .accessibilityLabel("\u{8bbe}\u{7f6e}").accessibilityIdentifier("mine.settings")
        } }
    }

    @ViewBuilder private var accountHeader: some View {
        if sessionStore.isLoggedIn {
            Button { PiliPresentation.present(.sheet) { PiliProfileView(api: dependencies.api) } } label: {
                MineDashboardIdentity(user: sessionStore.user, isLoggedIn: true)
            }.buttonStyle(.plain).accessibilityIdentifier("mine.profile")
        } else {
            Menu {
                Button("\u{77ed}\u{4fe1}\u{9a8c}\u{8bc1}\u{7801}\u{767b}\u{5f55}", action: onSMSLogin)
                Button("\u{626b}\u{7801}\u{767b}\u{5f55}", action: onQRCodeLogin)
                Button("\u{7f51}\u{9875}\u{767b}\u{5f55}", action: onWebLogin)
            } label: { MineDashboardIdentity(user: nil, isLoggedIn: false) }
                .buttonStyle(.plain).accessibilityIdentifier("mine.login")
        }
    }

    private var accountStatistics: some View {
        HStack(spacing: 16) {
            NavigationLink {
                UploaderView(owner: .init(mid: sessionStore.user?.mid ?? 0, name: sessionStore.user?.uname ?? "", face: sessionStore.user?.face))
            } label: { MineDashboardStat(title: "\u{52a8}\u{6001}", count: viewModel.statistics?.dynamicCount) }
            Button { showRelations(.following) } label: { MineDashboardStat(title: "\u{5173}\u{6ce8}", count: viewModel.statistics?.following) }
            Button { showRelations(.fans) } label: { MineDashboardStat(title: "\u{7c89}\u{4e1d}", count: viewModel.statistics?.follower) }
        }.buttonStyle(.plain)
    }

    private var shortcuts: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: dynamicTypeSize.isAccessibilitySize ? 2 : 4), spacing: 20) {
            Button { showOffline() } label: { MineDashboardShortcut(title: "\u{79bb}\u{7ebf}\u{7f13}\u{5b58}", icon: "arrow.down.to.line") }
                .accessibilityIdentifier("mine.offline")
            Button { onOpenRoute(.history) } label: { MineDashboardShortcut(title: "\u{89c2}\u{770b}\u{8bb0}\u{5f55}", icon: "clock.arrow.circlepath") }
                .accessibilityIdentifier("mine.history")
            NavigationLink { PiliCollectedContentView() } label: { MineDashboardShortcut(title: "\u{6211}\u{7684}\u{8ba2}\u{9605}", icon: "rectangle.stack") }
                .accessibilityIdentifier("mine.subscriptions")
            Button { onOpenRoute(.watchLater) } label: { MineDashboardShortcut(title: "\u{7a0d}\u{540e}\u{518d}\u{770b}", icon: "clock") }
                .accessibilityIdentifier("mine.watchLater")
        }.buttonStyle(.plain)
    }

    private var favorites: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button { onOpenRoute(.favorites) } label: {
                    HStack(spacing: 8) {
                        Text("\u{6211}\u{7684}\u{6536}\u{85cf}").font(.headline)
                        Text("\(viewModel.favoriteFolders.count)").font(.subheadline).foregroundStyle(.secondary)
                        PiliIcon(systemName: "chevron.right", size: 14)
                    }.frame(minHeight: 44)
                }.buttonStyle(.plain)
                Spacer()
                Button { Task { await viewModel.refreshFavorites() } } label: {
                    if viewModel.favoriteState == .loading { ProgressView().frame(width: 22, height: 22) }
                    else { PiliIcon(systemName: "arrow.clockwise", size: 22) }
                }.frame(width: 44, height: 44).buttonStyle(.plain)
                    .disabled(!sessionStore.isLoggedIn || viewModel.favoriteState == .loading)
                    .accessibilityLabel("\u{5237}\u{65b0}\u{6536}\u{85cf}\u{5939}")
            }
            if !viewModel.favoriteFolders.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 24) {
                    ForEach(viewModel.favoriteFolders) { folder in
                        Button {
                            PiliPresentation.present(.sheet) {
                                PiliFavoriteItemsView(api: dependencies.api, folder: folder) { Task { await viewModel.refreshFavorites() } }
                            }
                        } label: { MineDashboardFolder(folder: folder) }.buttonStyle(.plain)
                    }
                }
            } else if case .failed(let message) = viewModel.favoriteState {
                Text(message).font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text(sessionStore.isLoggedIn ? "\u{6682}\u{65e0}\u{6536}\u{85cf}\u{5939}" : "\u{767b}\u{5f55}\u{540e}\u{67e5}\u{770b}\u{6536}\u{85cf}\u{5939}")
                    .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder private var libraryMenu: some View {
        Button("\u{8d26}\u{53f7}\u{5207}\u{6362}") { onOpenRoute(.multiAccountSettings) }
        Button("\u{5916}\u{89c2}\u{8bbe}\u{7f6e}") { onOpenRoute(.interfaceSettings) }
        Divider()
        NavigationLink { PiliCommentArchiveView() } label: { Text("\u{6211}\u{7684}\u{8bc4}\u{8bba}") }
        NavigationLink { PiliAccountUtilitiesView() } label: { Text("\u{8d26}\u{53f7}\u{8bb0}\u{5f55}\u{4e0e}\u{7a7a}\u{95f4}\u{9690}\u{79c1}") }
        NavigationLink { PiliCoursesView(api: dependencies.api) } label: { Text("\u{6536}\u{85cf}\u{7684}\u{8bfe}\u{7a0b}") }
        Button("\u{6211}\u{7684}\u{7b14}\u{8bb0}") { PiliPresentation.present(.sheet) { PiliNotesLibraryView(api: dependencies.api) } }
        Button("\u{6295}\u{5c4f}\u{9065}\u{63a7}") { PiliPresentation.present(.sheet) { PiliDLNAView() } }
    }

    private func showOffline() {
        PiliPresentation.present(.sheet) {
            NavigationStack { PiliOfflineLibraryView() }
                .environmentObject(dependencies).environmentObject(libraryStore)
        }
    }
    private func showRelations(_ kind: PiliRelationList) {
        PiliPresentation.present(.sheet) {
            PiliRelationsView(api: dependencies.api, kind: kind)
                .environmentObject(dependencies).environmentObject(libraryStore).environmentObject(sessionStore)
        }
    }
}
