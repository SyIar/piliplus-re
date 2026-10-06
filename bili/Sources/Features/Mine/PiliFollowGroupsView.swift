import ChunUI
import SwiftUI

struct PiliFollowGroupsView: View {
    @ObservedObject var model: PiliRelationsModel
    @PiliDismiss private var dismiss
    @State private var editor: Editor?
    @State private var deleting: PiliFollowGroup?
    @State private var order: [PiliFollowGroup] = []
    @State private var changedOrder = false
    private struct Editor: Identifiable { let id = UUID(); let group: PiliFollowGroup? }
    var body: some View {
        PiliList {
            if let message = model.errorMessage { Text(message).foregroundStyle(Color.cc.destructive) }
            Section("系统分组") {
                ForEach(model.groups.filter { !$0.isCustom }) { group in
                    PiliLabel("\(group.name)（\(group.count)）", systemImage: "lock").foregroundStyle(Color.cc.mutedForeground)
                }
            }
            Section("自定义分组") {
                ForEach(order) { group in
                    HStack {
                        Text(group.name)
                        Spacer()
                        Text("\(group.count)").foregroundStyle(Color.cc.mutedForeground)
                        Menu {
                            Button("重命名") { editor = Editor(group: group) }
                            Button("删除分组", role: .destructive) { deleting = group }
                        } label: { PiliIcon(systemName: "ellipsis") }.disabled(changedOrder)
                    }
                }.onMove { offsets, destination in
                    order.move(fromOffsets: offsets, toOffset: destination); changedOrder = true
                }
                if order.isEmpty { Text("还没有自定义分组").foregroundStyle(Color.cc.mutedForeground) }
            }
            Section {
                PiliIconButton("新建分组", systemImage: "plus") { editor = Editor(group: nil) }.disabled(changedOrder)
                if changedOrder {
                    Button("保存排序") {
                        let ids = order.map(\.id)
                        Task { if await model.perform(.sortGroups(ids)) { changedOrder = false; synchronize() } }
                    }
                    Button("放弃排序修改") { changedOrder = false; synchronize() }
                }
            }
        }
        .disabled(model.mutating || !model.isCurrent)
        .navigationTitle("关注分组")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() }.disabled(model.mutating || changedOrder) }
            ToolbarItem(placement: .primaryAction) { EditButton().disabled(model.mutating) }
        }
        .piliInteractiveDismissDisabled(model.mutating || changedOrder)
        .task { await model.refreshGroups(); synchronize() }
        .onChange(of: model.groups) { _, _ in synchronize() }
        .piliSheet(item: $editor) { value in NavigationStack { PiliFollowGroupEditor(model: model, group: value.group) } }
        .piliConfirmation("删除“\(deleting?.name ?? "")”？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            if let group = deleting { PiliAlertButton("删除", role: .destructive) { Task { await model.perform(.deleteGroup(group.id)) } } }
        } message: { "删除的是分组，关注关系会保留。" }
    }
    private func synchronize() { if !changedOrder { order = model.groups.filter(\.isCustom) } }
}

private struct PiliFollowGroupEditor: View {
    @ObservedObject var model: PiliRelationsModel
    let group: PiliFollowGroup?
    @PiliDismiss private var dismiss
    @State private var name = ""
    @State private var initialized = false
    var body: some View {
        PiliForm {
            TextField("分组名称", text: $name)
            Text("\(name.count)/16 字").foregroundStyle(Color.cc.mutedForeground)
            if let message = model.errorMessage { Text(message).foregroundStyle(Color.cc.destructive) }
        }
        .navigationTitle(group == nil ? "新建分组" : "重命名分组")
        .disabled(model.mutating || !model.isCurrent)
        .piliInteractiveDismissDisabled(model.mutating)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(model.mutating) }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let action: PiliRelationMutation = group.map { .renameGroup($0.id, value) } ?? .createGroup(value)
                    Task { if await model.perform(action) { dismiss() } }
                }.disabled(model.mutating || !model.isCurrent || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 16)
            }
        }
        .onAppear { if !initialized { name = group?.name ?? ""; initialized = true } }
    }
}

struct PiliUserGroupsView: View {
    @ObservedObject var model: PiliRelationsModel
    let user: PiliRelationUser
    @PiliDismiss private var dismiss
    @State private var selected = Set<Int>()
    @State private var loading = false
    @State private var loaded = false
    @State private var errorMessage: String?
    var body: some View {
        PiliList {
            Section {
                Text(user.name).ccText(font: .cc.lg, color: .cc.foreground)
                Text("可以选择多个分组。全部取消后保存至默认分组。").ccText(font: .cc.sm, color: .cc.mutedForeground)
            }
            if loading { ProgressView("读取当前分组") }
            if let message = errorMessage ?? model.errorMessage { Text(message).foregroundStyle(Color.cc.destructive) }
            if !loaded, !loading { Button("重试") { Task { await load() } } }
            if loaded {
                Section {
                    ForEach(model.groups.filter { $0.id != 0 }) { group in
                        Toggle(group.name, isOn: Binding(get: { selected.contains(group.id) }, set: { enabled in
                            if enabled { selected.insert(group.id) } else { selected.remove(group.id) }
                        }))
                    }
                    Button("全部取消，使用默认分组") { selected = [] }
                }
            }
        }
        .navigationTitle("设置关注分组")
        .disabled(model.mutating || !model.isCurrent)
        .piliInteractiveDismissDisabled(model.mutating)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(model.mutating) }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    let ids = selected.sorted()
                    Task { if await model.perform(.setGroups(mid: user.id, ids: ids)) { dismiss() } }
                }.disabled(loading || !loaded || model.mutating || !model.isCurrent)
            }
        }
        .task { await load() }
    }
    private func load() async {
        guard !loading else { return }
        loading = true; errorMessage = nil
        defer { loading = false }
        do {
            let values = try await model.api.fetchPiliRelationGroups(mid: user.id, identity: model.identity)
            guard !Task.isCancelled, model.isCurrent else { return }
            selected = values; loaded = true
        } catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
    }
}
