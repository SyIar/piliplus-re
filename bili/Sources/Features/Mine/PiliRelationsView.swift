import ChunUI
import SwiftUI

struct PiliRelationsView: View {
    @StateObject private var model: PiliRelationsModel
    @ObservedObject private var session: SessionStore
    @State private var managingGroups = false
    @State private var assigning: PiliRelationUser?
    @State private var pending: Confirmation?
    private struct Confirmation: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let action: PiliRelationMutation
    }
    init(api: BiliAPIClient, ownerMID: Int? = nil, kind: PiliRelationList = .following) {
        _model = StateObject(wrappedValue: PiliRelationsModel(api: api, ownerMID: ownerMID, kind: kind))
        _session = ObservedObject(wrappedValue: api.sessionStore)
    }
    var body: some View {
        NavigationStack {
            List {
                controls
                if let message = model.errorMessage {
                    Section {
                        Text(message).foregroundStyle(Color.cc.destructive)
                        if model.isCurrent { Button("重新加载") { Task { await model.start() } } }
                    }
                }
                Section {
                    ForEach(model.users) { user in userRow(user) }
                    if model.loading { ProgressView("加载中") }
                    else if model.hasMore { Button("加载更多") { Task { await model.load() } } }
                    else if model.users.isEmpty, model.errorMessage == nil {
                        ContentUnavailableView("暂无用户", systemImage: "person.2", description: Text("可尝试其他分组或搜索条件"))
                    }
                } header: {
                    if let total = model.total { Text("共 \(total) 人") }
                    else { Text("已加载 \(model.users.count) 人") }
                }
            }
            .navigationTitle(model.isOwn ? "关注与粉丝" : "用户关系")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { AppHelper.shared.dismissSheet() }.disabled(model.mutating) }
                if model.isOwn {
                    ToolbarItem(placement: .primaryAction) { Button("管理分组") { managingGroups = true }.disabled(!model.isCurrent || model.mutating) }
                }
            }
            .interactiveDismissDisabled(model.mutating)
            .task { await model.start() }
            .refreshable { await model.start() }
            .onChange(of: model.kind) { _, _ in model.groupID = nil; model.keyword = ""; reload() }
            .onChange(of: model.groupID) { _, _ in reload() }
            .onChange(of: model.frequent) { _, _ in reload() }
            .onChange(of: session.playbackCredentialVersion) { _, _ in
                if !model.isCurrent { pending = nil; assigning = nil; managingGroups = false; model.invalidate() }
            }
            .sheet(isPresented: $managingGroups) { NavigationStack { PiliFollowGroupsView(model: model) } }
            .sheet(item: $assigning) { user in NavigationStack { PiliUserGroupsView(model: model, user: user) } }
            .alert(item: $pending) { value in
                Alert(title: Text(value.title), message: Text(value.message),
                      primaryButton: .destructive(Text("确认")) { Task { await model.perform(value.action) } }, secondaryButton: .cancel(Text("取消")))
            }
            .videoDestinations()
        }
    }
    private var controls: some View {
        Section {
            Picker("列表", selection: $model.kind) {
                Text("关注").tag(PiliRelationList.following)
                Text("粉丝").tag(PiliRelationList.fans)
                if model.isOwn { Text("黑名单").tag(PiliRelationList.blocked) }
            }.pickerStyle(.segmented)
            if model.kind == .following {
                HStack {
                    TextField("搜索全部关注", text: $model.keyword).submitLabel(.search).onSubmit { reload() }
                    Button { reload() } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("搜索关注")
                    if !model.keyword.isEmpty { Button { model.keyword = ""; reload() } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("清除搜索") }
                }
                if model.isOwn {
                    Picker("分组", selection: $model.groupID) {
                        Text("全部关注").tag(Int?.none)
                        ForEach(model.groups) { group in Text("\(group.name)（\(group.count)）").tag(Optional(group.id)) }
                    }.disabled(!model.keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Picker("排序", selection: $model.frequent) { Text("最近关注").tag(false); Text("最常访问").tag(true) }
            }
            if model.isOwn { Text("当前主账号 UID \(model.identity.mid)").ccText(font: .cc.xs, color: .cc.mutedForeground) }
            if model.mutating { ProgressView("正在保存") }
        }.disabled(model.mutating || !model.isCurrent)
    }
    private func userRow(_ user: PiliRelationUser) -> some View {
        HStack(spacing: 12) {
            VideoOwnerRouteLink(owner: user.owner) {
                HStack(spacing: 12) {
                    AvatarRemoteImage(urlString: user.face, pixelSize: 100) { Image(systemName: "person.crop.circle").resizable() }
                        .frame(width: 46, height: 46).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.name).ccText(font: .cc.base, color: .cc.foreground)
                        Text(user.sign.isEmpty ? "UID \(user.id)" : user.sign).ccText(font: .cc.xs, color: .cc.mutedForeground).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }
            if model.isOwn, user.id != model.identity.mid {
                Menu { actions(user) } label: { Image(systemName: "ellipsis").frame(width: 36, height: 36) }
                    .buttonStyle(.glass).disabled(model.mutating || !model.isCurrent).accessibilityLabel("管理 \(user.name)")
            }
        }
    }
    @ViewBuilder private func actions(_ user: PiliRelationUser) -> some View {
        if model.kind == .blocked {
            Button("移出黑名单") { confirm("移出黑名单？", user: user, action: .unblock(user.id)) }
        } else {
            if model.kind == .following || user.isFollowing {
                Button("设置分组") { assigning = user }
                let special = user.special || model.isShowingSpecial
                Button(special ? "取消特别关注" : "设为特别关注") { Task { await model.perform(.special(user.id, !special)) } }
                Button("取消关注", role: .destructive) { confirm("取消关注？", user: user, action: .unfollow(user.id)) }
            } else { Button("关注") { Task { await model.perform(.follow(user.id)) } } }
            if model.kind == .fans {
                Button("移除粉丝", role: .destructive) { confirm("移除粉丝？", user: user, action: .removeFan(user.id)) }
            }
            Button("加入黑名单", role: .destructive) { confirm("加入黑名单？", user: user, action: .block(user.id)) }
        }
    }
    private func confirm(_ title: String, user: PiliRelationUser, action: PiliRelationMutation) {
        pending = Confirmation(title: title, message: user.name, action: action)
    }
    private func reload() { Task { await model.load(reset: true) } }
}
