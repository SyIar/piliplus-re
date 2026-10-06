import SwiftUI

struct PiliDanmakuRulesView: View {
    let api: BiliAPIClient
    @ObservedObject private var store = PiliDanmakuRulesStore.shared
    @ObservedObject private var session: SessionStore
    @State private var identity: PiliAccountIdentity?
    @State private var type = 0
    @State private var text = ""
    @State private var error: String?
    init(api: BiliAPIClient) { self.api = api; _session = ObservedObject(wrappedValue: api.sessionStore) }
    var body: some View {
        Form {
            if identity?.matches(api.requestSnapshot()) != true {
                Text("请先登录，再管理弹幕屏蔽规则")
            } else {
                Section("添加规则") {
                    Picker("规则类型", selection: $type) {
                        Text("关键词").tag(0); Text("正则表达式").tag(1); Text("用户 UID").tag(2)
                    }
                    TextField(type == 2 ? "用户 UID" : "屏蔽内容", text: $text)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("添加") { mutate { expected in try await store.add(text: text, type: type, api: api, identity: expected); text = "" } }
                        .disabled(store.busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ForEach(0..<3) { kind in
                    Section(["关键词", "正则表达式", "用户（UID 哈希）"][kind]) {
                        ForEach(store.rules.filter { $0.type == kind }) { rule in
                            HStack {
                                Text(rule.filter).textSelection(.enabled)
                                Spacer()
                                Button("删除", role: .destructive) { mutate { expected in try await store.remove(rule, api: api, identity: expected) } }
                                    .disabled(store.busy)
                            }
                        }
                    }
                }
                Section {
                    Button("同步云端规则") { Task { await store.refresh(api: api, force: true) } }.disabled(store.busy)
                } footer: { Text("规则随账号同步；离线时继续使用本机缓存。删除规则后，当前视频中的对应弹幕会恢复显示。") }
            }
            if store.busy { ProgressView() }
            if let message = error ?? store.error { Text(message).foregroundStyle(.secondary) }
        }
        .navigationTitle("视频弹幕屏蔽").navigationBarTitleDisplayMode(.inline)
        .task(id: session.playbackCredentialVersion) {
            identity = PiliAccountIdentity(api.requestSnapshot()); error = nil; text = ""
            await store.refresh(api: api)
        }
    }
    private func mutate(_ action: @escaping @MainActor (PiliAccountIdentity) async throws -> Void) {
        guard let identity else { return }
        error = nil
        Task { do { try await action(identity) } catch { self.error = error.localizedDescription } }
    }
}
