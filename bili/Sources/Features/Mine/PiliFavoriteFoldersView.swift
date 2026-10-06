import ChunUI
import SwiftUI

struct PiliFavoriteFoldersView: View {
    let api: BiliAPIClient
    let onChanged: () -> Void
    @ObservedObject private var session: SessionStore
    @State private var folders: [FavoriteFolder] = []
    @State private var editor: EditorTarget?
    @State private var deleting: FavoriteFolder?
    @State private var isLoading = false
    @State private var isMutating = false
    @State private var sorting = false
    @State private var error: String?
    @State private var version = 0
    @State private var generation = UUID()
    private struct EditorTarget: Identifiable { let id = UUID(); let folder: FavoriteFolder?; let version: Int }

    init(api: BiliAPIClient, onChanged: @escaping () -> Void) {
        self.api = api; self.onChanged = onChanged; _session = ObservedObject(wrappedValue: api.sessionStore)
    }
    var body: some View {
        NavigationStack {
            PiliList {
                if isLoading || isMutating { ProgressView("加载中") }
                if let error { Text(error).ccText(font: .cc.sm, color: .cc.destructive) }
                Section {
                    ForEach(folders) { folder in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(folder.displayTitle).ccText(font: .cc.baseBold, color: .cc.foreground)
                                Text("\(folder.mediaCount ?? 0) 个内容 · \(folder.isPiliPublic ? "公开" : "私密")")
                                    .ccText(font: .cc.sm, color: .cc.mutedForeground)
                            }
                            Spacer()
                            if !sorting {
                                Menu {
                                    Button("编辑收藏夹") { editor = EditorTarget(folder: folder, version: version) }
                                    if !folder.isPiliDefault { Button("删除收藏夹", role: .destructive) { deleting = folder } }
                                } label: { PikaIcon(PikaIcon.Name.more).frame(width: 44, height: 44) }
                            }
                        }.moveDisabled(folder.isPiliDefault)
                    }.onMove(perform: move)
                }
                if folders.isEmpty, !isLoading { Text("暂无收藏夹，可点击右上角新建") }
            }
            .environment(\.editMode, .constant(sorting ? .active : .inactive))
            .disabled(isMutating)
            .navigationTitle("管理收藏夹")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sorting ? "取消排序" : "完成") {
                        if sorting { sorting = false; Task { await reload() } } else { AppHelper.shared.dismissSheet() }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if sorting { Button("保存顺序") { saveOrder() }.disabled(isMutating) }
                    else {
                        Menu {
                            Button("新建收藏夹") { editor = EditorTarget(folder: nil, version: version) }
                            Button("调整顺序") { sorting = true }.disabled(folders.count < 2)
                        } label: { PikaIcon(PikaIcon.Name.plus).frame(width: 44, height: 44) }
                    }
                }
            }
            .task(id: session.interactionAccountCredentialVersion) { await reload() }
            .refreshable { if !sorting { await reload() } }
            .piliSheet(item: $editor) { target in
                NavigationStack {
                    PiliFavoriteFolderEditor(api: api, folder: target.folder, credentialVersion: target.version) {
                        onChanged(); Task { await reload() }
                    }
                }
            }
            .piliAlert("删除收藏夹？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                PiliAlertButton("取消", role: .cancel) { deleting = nil }
                PiliAlertButton("删除", role: .destructive) { if let folder = deleting { remove(folder) }; deleting = nil }
            } message: { "“\(deleting?.displayTitle ?? "")”及其中的收藏记录将被移除，原视频不受影响。" }
        }
    }
    private func reload() async {
        generation = UUID(); let token = generation
        let currentVersion = api.requestSnapshot(purpose: .interaction).playbackCredentialVersion
        if currentVersion != version { folders = []; editor = nil; deleting = nil }
        version = currentVersion
        let identity = version
        sorting = false; isLoading = true; error = nil
        defer { if generation == token { isLoading = false } }
        do {
            let value = try await api.fetchFavoriteFolders()
            guard !Task.isCancelled, generation == token,
                  api.requestSnapshot(purpose: .interaction).playbackCredentialVersion == identity else { return }
            folders = value
        } catch { if !Task.isCancelled, generation == token { self.error = error.localizedDescription } }
    }
    private func move(_ indices: IndexSet, to destination: Int) {
        guard !indices.contains(0), destination != 0, !indices.contains(where: { folders[$0].isPiliDefault }) else { return }
        folders.move(fromOffsets: indices, toOffset: destination)
    }
    private func saveOrder() {
        guard !isMutating else { return }
        isMutating = true; error = nil
        let ids = folders.map(\.id), identity = version
        Task {
            defer { isMutating = false }
            do {
                try await api.sortPiliFavoriteFolders(ids: ids, credentialVersion: identity)
                sorting = false; onChanged(); await reload()
            } catch { self.error = error.localizedDescription }
        }
    }
    private func remove(_ folder: FavoriteFolder) {
        guard !isMutating else { return }
        isMutating = true; error = nil
        let identity = version
        Task {
            defer { isMutating = false }
            do {
                try await api.deletePiliFavoriteFolders([folder], credentialVersion: identity)
                onChanged(); await reload()
            } catch { self.error = error.localizedDescription }
        }
    }
}
