import SwiftUI
import ChunUI

struct PiliShareMenu<Label: View>: View {
    let url: URL
    let title: String
    var message = ""
    var repostID: String?
    @ViewBuilder let label: () -> Label
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var showsShare = false
    @State private var showsRepost = false
    var body: some View {
        Menu {
            ShareLink(item: url, subject: Text(title), message: Text(message)) { PiliLabel("系统分享", systemImage: "square.and.arrow.up") }
            PiliIconButton("分享至消息", systemImage: "paperplane") { showsShare = true }
            if repostID != nil { PiliIconButton("转发动态", systemImage: "arrowshape.turn.up.right") { showsRepost = true } }
        } label: { label() }
            .piliSheet(isPresented: $showsShare) { PiliShareSheet(api: dependencies.api, service: dependencies.accountMessageService, url: url, title: title) }
            .piliSheet(isPresented: $showsRepost) {
                let draft = { var d = PiliDynamicDraft(); d.repostID = repostID; return d }()
                PiliDynamicComposer(api: dependencies.api, initial: draft) { NotificationCenter.default.post(name: .piliDynamicChanged, object: nil) }
            }
    }
}

struct PiliShareSheet: View {
    let api: BiliAPIClient
    let service: AccountMessageService
    let url: URL
    let title: String
    @PiliDismiss private var dismiss
    @State private var card: PiliShareCard?
    @State private var identity: PiliAccountIdentity?
    @State private var contacts: [PiliNamedResource] = []
    @State private var selected: PiliNamedResource?
    @State private var search = false
    @State private var busy = false
    @State private var error: String?
    @State private var sent = false
    var body: some View {
        NavigationStack {
            PiliForm {
                Section("分享内容") { Text(title); Text(url.absoluteString).piliFont(.sm).foregroundStyle(.secondary) }
                Section("发送给") {
                    if let selected { PiliLabel(selected.name, systemImage: "person.crop.circle.fill") }
                    Button("搜索用户") { search = true }
                    ForEach(contacts) { item in Button(item.name) { selected = item } }
                }
                if let error { Text(error).foregroundStyle(Color.cc.destructive) }
                if card == nil && error == nil { ProgressView("准备卡片") }
                if sent { PiliLabel("已发送", systemImage: "checkmark.circle") }
            }.disabled(busy || sent).navigationTitle("分享至消息")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(sent ? "完成" : "关闭") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) { Button("发送") { send() }.disabled(busy || sent || selected == nil || card == nil) }
                }
                .piliSheet(isPresented: $search) { PiliResourcePicker(title: "选择收件人", load: { try await api.piliMentions(keyword: $0) }) { selected = $0 } }
                .task {
                    let captured = PiliAccountIdentity(api.requestSnapshot(purpose: .main)); identity = captured
                    do {
                        card = try await api.piliShareCard(url: url, title: title)
                        let sessions = (try? await service.fetchPrivateMessageSessions()) ?? []
                        guard captured.matches(api.requestSnapshot(purpose: .main)) else { throw PiliOfflineError.message("账号已切换") }
                        contacts = sessions.prefix(15).map { .init(id: $0.talkerID, name: $0.actor.name, image: $0.actor.avatarURLString) }
                    } catch { self.error = error.localizedDescription }
                }.piliInteractiveDismissDisabled(busy)
        }
    }
    private func send() {
        guard let card, let selected, let identity, !busy, !sent else { return }; busy = true
        Task {
            defer { busy = false }
            do { try await api.piliSendCard(card, recipient: selected.id, identity: identity); sent = true; error = nil }
            catch { self.error = error.localizedDescription }
        }
    }
}
