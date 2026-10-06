import SwiftUI
import ChunUI

struct AccountLibraryListPage: View {
    let kind: AccountLibraryKind
    @ObservedObject var viewModel: MineViewModel
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var sessionStore: SessionStore

    var body: some View {
        PiliList {
            if kind == .watchLater, sessionStore.isLoggedIn {
                Section {
                    Picker("查看范围", selection: $viewModel.watchLaterFilter.unfinished) {
                        Text("全部").tag(false); Text("未看完").tag(true)
                    }.pickerStyle(.segmented)
                    Picker("添加时间", selection: $viewModel.watchLaterFilter.ascending) {
                        Text("最近添加").tag(false); Text("最早添加").tag(true)
                    }
                    TextField("搜索稍后再看", text: $viewModel.watchLaterFilter.keyword)
                        .submitLabel(.search).onSubmit { Task { await viewModel.refreshWatchLater() } }
                }
            }
            Section {
                content
            }
        }
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
        .toolbar {
            if kind == .favorites, sessionStore.isLoggedIn {
                ToolbarItem(placement: .topBarLeading) {
                    Button("管理收藏夹") {
                        PiliPresentation.present(.sheet) {
                            PiliFavoriteFoldersView(api: dependencies.api) { Task { await viewModel.refreshFavorites() } }
                        }
                    }
                }
            }
            if kind == .watchLater, sessionStore.isLoggedIn {
                ToolbarItem(placement: .topBarLeading) {
                    Button("管理") {
                        PiliPresentation.present(.sheet) { PiliWatchLaterToolsView(viewModel: viewModel) }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await reload() }
                } label: {
                    PiliIcon(systemName: "arrow.clockwise")
                }
                .disabled(!sessionStore.isLoggedIn || state.isLoading)
            }
        }
        .task(id: kind == .watchLater ? sessionStore.historyAccountCredentialVersion : sessionStore.interactionAccountCredentialVersion) {
            if kind == .watchLater { await reload() } else { await loadIfNeeded() }
        }
        .onChange(of: viewModel.watchLaterFilter.unfinished) { _, _ in if kind == .watchLater { Task { await reload() } } }
        .onChange(of: viewModel.watchLaterFilter.ascending) { _, _ in if kind == .watchLater { Task { await reload() } } }
        .refreshable {
            await reload()
        }
    }

    @ViewBuilder
    private var content: some View {
        if !sessionStore.isLoggedIn {
            LibraryEmptyRow(title: kind.loggedOutTitle, systemImage: kind.systemImage)
        } else if items.isEmpty && state.isLoading {
            LibraryLoadingRow(title: kind.loadingTitle)
        } else if items.isEmpty, case .failed(let message) = state {
            LibraryErrorRow(title: kind.errorTitle, message: message) {
                Task { await reload() }
            }
        } else if kind == .favorites {
            favoriteFolderContent
        } else if items.isEmpty {
            LibraryEmptyRow(title: kind.emptyTitle, systemImage: kind.systemImage)
        } else {
            ForEach(items) { item in
                VideoRouteLink(item.videoItem.withPiliPlaybackQueue(kind == .watchLater ? viewModel.watchLaterPlaybackQueue : nil)) {
                    LibraryVideoRow(item: item, timestampTitle: kind.timestampTitle)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if kind == .watchLater, item.aid != nil {
                        Button("移除", role: .destructive) {
                            Task {
                                do {
                                    try await viewModel.removeWatchLater(item)
                                } catch {
                                    CCToastCenter.shared.show(.error, error.localizedDescription)
                                }
                            }
                        }
                        .disabled(viewModel.isMutatingWatchLater)
                    }
                }
                .task {
                    await loadMoreIfNeeded(current: item)
                }
            }

            if state.isLoading {
                LibraryLoadingRow(title: kind.loadingTitle)
            } else if loadMoreState.isLoading {
                LibraryLoadingRow(title: kind.loadMoreTitle)
            } else if case .failed(let message) = state {
                LibraryErrorRow(title: kind.errorTitle, message: message) {
                    Task { await reload() }
                }
            } else if case .failed(let message) = loadMoreState {
                LibraryErrorRow(title: kind.loadMoreErrorTitle, message: message) {
                    Task { await loadMore() }
                }
            } else if hasMore {
                LibraryLoadMoreTriggerRow(title: kind.loadMoreTitle) {
                    Task { await loadMore() }
                }
            }
        }
    }

    @ViewBuilder
    private var favoriteFolderContent: some View {
        if favoriteFolders.isEmpty {
            LibraryEmptyRow(title: kind.emptyTitle, systemImage: kind.systemImage)
        } else {
            ForEach(favoriteFolders) { folder in
                NavigationLink {
                    FavoriteFolderContentPage(folder: folder, viewModel: viewModel)
                } label: {
                    FavoriteFolderRow(folder: folder)
                }
            }
        }
    }

    private var items: [AccountVideoEntry] {
        switch kind {
        case .history:
            return viewModel.accountHistory
        case .favorites:
            return viewModel.accountFavorites
        case .watchLater:
            return viewModel.accountWatchLater
        }
    }

    private var state: LoadingState {
        switch kind {
        case .history:
            return viewModel.historyState
        case .favorites:
            return viewModel.favoriteState
        case .watchLater:
            return viewModel.watchLaterState
        }
    }

    private var favoriteFolders: [FavoriteFolder] {
        viewModel.favoriteFolders
    }

    private var loadMoreState: LoadingState {
        switch kind {
        case .history:
            return viewModel.historyLoadMoreState
        case .favorites: return .idle
        case .watchLater: return viewModel.watchLaterLoadMoreState
        }
    }

    private var hasMore: Bool {
        switch kind {
        case .history:
            return viewModel.historyHasMore
        case .favorites: return false
        case .watchLater: return viewModel.watchLaterHasMore
        }
    }

    private func loadIfNeeded() async {
        guard sessionStore.isLoggedIn, items.isEmpty, !state.isLoading else { return }
        await reload()
    }

    private func reload() async {
        switch kind {
        case .history:
            await viewModel.refreshHistory()
        case .favorites:
            await viewModel.refreshFavorites()
        case .watchLater:
            await viewModel.refreshWatchLater()
        }
    }

    private func loadMoreIfNeeded(current item: AccountVideoEntry) async {
        switch kind {
        case .history:
            await viewModel.loadMoreHistoryIfNeeded(current: item)
        case .watchLater:
            if viewModel.accountWatchLater.last?.id == item.id { await viewModel.loadMoreWatchLater() }
        case .favorites: break
        }
    }

    private func loadMore() async {
        switch kind {
        case .history:
            await viewModel.loadMoreHistory()
        case .watchLater: await viewModel.loadMoreWatchLater()
        case .favorites: break
        }
    }
}
