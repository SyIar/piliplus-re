import SwiftUI
import ChunUI

struct PiliChatSettingsView: View {
    let api: BiliAPIClient
    let talkerID: Int
    @ObservedObject private var sessionStore: SessionStore
    @State private var identity: PiliAccountIdentity
    @State private var settings: PiliChatSettings?
    @State private var loading = false
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var confirmsDisablePush = false

    init(api: BiliAPIClient, talkerID: Int) {
        self.api = api; self.talkerID = talkerID
        _sessionStore = ObservedObject(wrappedValue: api.sessionStore)
        // Keep the account that opened this screen even if its parent rebuilds.
        _identity = State(initialValue: PiliAccountIdentity(api.requestSnapshot(purpose: .main)))
    }

    private var isCurrent: Bool { identity.matches(api.requestSnapshot(purpose: .main)) }

    var body: some View {
        PiliForm {
            if !isCurrent {
                Text("账号已切换，请重新打开聊天设置").foregroundStyle(.secondary)
            } else if let settings {
                Section {
                    if settings.canConfigurePush {
                    Toggle("接收内容推送", isOn: Binding(get: { settings.receivesPush }, set: { enabled in
                        if enabled { save(push: true) } else { confirmsDisablePush = true }
                    }))
                    }
                    Toggle("消息免打扰", isOn: Binding(get: { settings.muted }, set: { save(muted: $0) }))
                } footer: {
                    if settings.canConfigurePush { Text("关闭内容推送后，不再接收此账号的图文消息与稿件推送；通知类消息不受影响。") }
                }
                .disabled(saving)
            }
            if loading || saving { ProgressView(loading ? "正在加载" : "正在保存") }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(Color.cc.destructive)
                    if settings == nil { Button("重试") { Task { await load() } }.disabled(loading) }
                }
            }
        }
        .navigationTitle("聊天设置").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .piliConfirmation("关闭这个账号的内容推送？", isPresented: $confirmsDisablePush, titleVisibility: .visible) {
            PiliAlertButton("关闭推送", role: .destructive) { save(push: false) }
            PiliAlertButton("取消", role: .cancel) {}
        }
    }

    private func load() async {
        guard isCurrent, !loading else { return }
        loading = true; errorMessage = nil
        defer { loading = false }
        do {
            let result = try await api.fetchPiliChatSettings(talkerID: talkerID, identity: identity)
            guard isCurrent, !Task.isCancelled else { return }
            settings = result
        } catch { if isCurrent { errorMessage = error.localizedDescription } }
    }

    private func save(push: Bool? = nil, muted: Bool? = nil) {
        guard isCurrent, !saving else { return }
        saving = true; errorMessage = nil
        Task {
            defer { saving = false }
            do {
                try await api.setPiliChatSetting(talkerID: talkerID, receivesPush: push, muted: muted, identity: identity)
                guard isCurrent else { return }
                if let push { settings?.receivesPush = push }
                if let muted { settings?.muted = muted }
            } catch { if isCurrent { errorMessage = error.localizedDescription } }
        }
    }
}
