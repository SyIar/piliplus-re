import SwiftUI

struct PiliQuickFavoriteSettingsView: View {
    let api: BiliAPIClient
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject private var session: SessionStore
    @State private var folders: [FavoriteFolder] = []
    @State private var identity: PiliAccountIdentity?
    @State private var loading = false
    @State private var error: String?
    init(api: BiliAPIClient, libraryStore: LibraryStore) {
        self.api = api; self.libraryStore = libraryStore; _session = ObservedObject(wrappedValue: api.sessionStore)
    }
    var body: some View {
        PiliList {
            Section {
                Button { choose(0) } label: { row("关闭快速收藏", id: 0) }
                ForEach(folders) { folder in
                    Button { choose(folder.id) } label: { row(folder.displayTitle, id: folder.id) }
                }
            } footer: { Text("点按收藏使用此文件夹，长按可更换。默认文件夹按账号保存。") }
            if loading { ProgressView() }
            if let error { Text(error); Button("重试") { Task { await load() } } }
        }
        .navigationTitle("快速收藏").navigationBarTitleDisplayMode(.inline)
        .task(id: PiliAccountIdentity(api.requestSnapshot(purpose: .interaction))) { await load() }
    }
    private func row(_ title: String, id: Int) -> some View {
        HStack {
            Text(title).foregroundStyle(.primary); Spacer()
            if libraryStore.quickFavoriteFolder(account: identity?.mid ?? 0) == id { PiliIcon(systemName: "checkmark") }
        }
    }
    private func choose(_ id: Int) {
        guard let identity, identity.matches(api.requestSnapshot(purpose: .interaction)) else { error = "请先登录互动账号"; return }
        libraryStore.setQuickFavoriteFolder(id, account: identity.mid)
    }
    private func load() async {
        let expected = PiliAccountIdentity(api.requestSnapshot(purpose: .interaction)); identity = expected
        folders = []; error = nil; loading = true
        defer { if identity == expected { loading = false } }
        guard expected.matches(api.requestSnapshot(purpose: .interaction)) else { error = "请先登录后选择默认收藏夹"; return }
        do {
            let values = try await api.fetchFavoriteFolders()
            guard !Task.isCancelled, expected.matches(api.requestSnapshot(purpose: .interaction)) else { return }
            folders = values
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
