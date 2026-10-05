import ChunUI
import SwiftUI

struct PiliFavoriteItemsView: View {
    @StateObject private var model: PiliFavoriteItemsModel
    @ObservedObject private var session: SessionStore
    let onChanged: () -> Void
    @State private var confirmRemove = false
    @State private var confirmClean = false
    @State private var targetMode: TargetMode?
    @State private var sortTarget: SortTarget?
    private enum TargetMode: String, Identifiable { case copy, move; var id: String { rawValue } }
    private struct SortTarget: Identifiable {
        let id = UUID()
        let items: [AccountVideoEntry]
        let version: Int
    }

    init(api: BiliAPIClient, folder: FavoriteFolder, onChanged: @escaping () -> Void) {
        _model = StateObject(wrappedValue: PiliFavoriteItemsModel(api: api, folder: folder))
        _session = ObservedObject(wrappedValue: api.sessionStore)
        self.onChanged = onChanged
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("显示顺序", selection: $model.order) {
                        ForEach(PiliFavoriteOrder.allCases) { Text($0.title).tag($0) }
                    }
                    HStack {
                        Button("全选已加载") { model.selectLoaded() }
                        Spacer()
                        Button("取消选择") { model.selected = [] }
                    }
                    Text("已选择 \(model.selected.count) 个视频").ccText(font: .cc.sm, color: .cc.mutedForeground)
                }
                if let error = model.errorMessage { Text(error).ccText(font: .cc.sm, color: .cc.destructive) }
                Section {
                    ForEach(model.items) { item in
                        if let aid = item.aid, aid > 0 {
                            Button { model.toggle(aid) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: model.selected.contains(aid) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(Color.cc.primary)
                                    LibraryVideoRow(item: item, timestampTitle: "收藏时间")
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                    if model.isLoading { ProgressView("加载收藏") }
                    else if model.hasMore { Button("加载更多") { Task { await model.load() } } }
                    else if model.items.isEmpty { Text("没有匹配的视频") }
                }
            }
            .disabled(model.isMutating)
            .searchable(text: $model.keyword, prompt: "在收藏夹中搜索")
            .onSubmit(of: .search) { Task { await model.load(reset: true) } }
            .onChange(of: model.order) { _, _ in Task { await model.load(reset: true) } }
            .navigationTitle(model.folder.displayTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { AppHelper.shared.dismissSheet() }.disabled(model.isMutating) }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("复制至其他收藏夹") { showTargets(.copy) }.disabled(model.selected.isEmpty)
                        Button("移动至其他收藏夹") { showTargets(.move) }.disabled(model.selected.isEmpty)
                        Button("移除所选视频", role: .destructive) { confirmRemove = true }.disabled(model.selected.isEmpty)
                        Divider()
                        Button("调整视频顺序") {
                            sortTarget = SortTarget(items: model.items, version: model.credentialVersion)
                        }.disabled(model.items.count < 2 || !model.keyword.isEmpty || model.order != .favoriteTime)
                        Button("清理失效收藏", role: .destructive) { confirmClean = true }
                    } label: { PikaIcon(PikaIcon.Name.more).frame(width: 44, height: 44) }
                    .disabled(model.isMutating || model.isLoading)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !model.selected.isEmpty {
                    HStack {
                        Button("复制") { showTargets(.copy) }
                        Button("移动") { showTargets(.move) }
                        Spacer()
                        Button("移除", role: .destructive) { confirmRemove = true }
                    }
                    .buttonStyle(.glass).padding(16).background(.ultraThinMaterial)
                    .disabled(model.isMutating)
                }
            }
            .task(id: session.interactionAccountCredentialVersion) {
                targetMode = nil; sortTarget = nil; confirmRemove = false; confirmClean = false
                await model.load(reset: true)
            }
            .refreshable { await model.load(reset: true) }
            .alert("移除所选的 \(model.selected.count) 个视频？", isPresented: $confirmRemove) {
                Button("取消", role: .cancel) {}
                Button("移除", role: .destructive) { Task { if await model.mutate(.remove) { onChanged() } } }
            } message: { Text("只从当前收藏夹移除，其他收藏夹中的记录不受影响。") }
            .alert("清理失效收藏？", isPresented: $confirmClean) {
                Button("取消", role: .cancel) {}
                Button("清理", role: .destructive) { Task { if await model.clean() { onChanged() } } }
            } message: { Text("删除当前收藏夹中已失效的视频收藏记录。") }
            .sheet(item: $targetMode) { mode in
                NavigationStack {
                    List {
                        ForEach(model.folders) { folder in
                            Button(folder.displayTitle) {
                                targetMode = nil
                                Task { if await model.mutate(mode == .copy ? .copy(to: folder.id) : .move(to: folder.id)) { onChanged() } }
                            }
                        }
                        if model.folders.isEmpty { Text("没有其他收藏夹，请先新建一个收藏夹") }
                    }
                    .navigationTitle(mode == .copy ? "复制到" : "移动到")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { targetMode = nil } } }
                }
            }
            .sheet(item: $sortTarget) { target in
                NavigationStack {
                    PiliFavoriteResourceSortView(api: model.api, folderID: model.folder.id, items: target.items,
                                                 credentialVersion: target.version) {
                        onChanged(); Task { await model.load(reset: true) }
                    }
                }
            }
        }
    }
    private func showTargets(_ mode: TargetMode) {
        Task { await model.loadTargets(); targetMode = mode }
    }
}

private struct PiliFavoriteResourceSortView: View {
    let api: BiliAPIClient
    let folderID: Int
    let credentialVersion: Int
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var items: [AccountVideoEntry]
    @State private var movements: [String] = []
    @State private var busy = false
    @State private var error: String?
    init(api: BiliAPIClient, folderID: Int, items: [AccountVideoEntry], credentialVersion: Int, onSaved: @escaping () -> Void) {
        self.api = api; self.folderID = folderID; self.credentialVersion = credentialVersion; self.onSaved = onSaved
        _items = State(initialValue: items.filter { ($0.aid ?? 0) > 0 })
    }
    var body: some View {
        List {
            Section { Text("拖动调整已加载的视频。需要整理更多内容时，请先返回加载更多。") }
            if let error { Text(error).foregroundStyle(Color.cc.destructive) }
            ForEach(items) { Text($0.videoItem.title).ccText(font: .cc.base, color: .cc.foreground) }
                .onMove { offsets, destination in
                    let moved = offsets.map { items[$0] }
                    items.move(fromOffsets: offsets, toOffset: destination)
                    for item in moved {
                        guard let aid = item.aid, let index = items.firstIndex(where: { $0.id == item.id }) else { continue }
                        let predecessor = index > 0 ? "\(items[index - 1].aid ?? 0):2" : "0:0"
                        movements.append("\(predecessor):\(aid):2")
                    }
                }
        }
        .environment(\.editMode, .constant(.active))
        .disabled(busy)
        .navigationTitle("调整视频顺序")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    busy = true
                    Task {
                        defer { busy = false }
                        do {
                            try await api.sortPiliFavoriteItems(folderID: folderID, movements: movements, credentialVersion: credentialVersion)
                            onSaved(); dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                }.disabled(busy || movements.isEmpty)
            }
        }
    }
}
