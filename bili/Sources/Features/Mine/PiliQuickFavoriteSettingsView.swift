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
        List {
            Section {
                Button { choose(0) } label: { row("关闭快速收藏", id: 0) }
                ForEach(folders) { folder in
                    Button { choose(folder.id) } label: { row(folder.displayTitle, id: folder.id) }
                }
            } footer: { Text("点按收藏会切换当前视频在所选文件夹中的收藏状态；长按收藏按钮可选择其他文件夹。默认文件夹按互动账号分别保存。") }
            if loading { ProgressView() }
            if let error { Text(error); Button("重试") { Task { await load() } } }
        }
        .navigationTitle("快速收藏").navigationBarTitleDisplayMode(.inline)
        .task(id: session.playbackCredentialVersion) { await load() }
    }
    private func row(_ title: String, id: Int) -> some View {
        HStack {
            Text(title).foregroundStyle(.primary); Spacer()
            if libraryStore.quickFavoriteFolder(account: identity?.mid ?? 0) == id { Image(systemName: "checkmark") }
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
