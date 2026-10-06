import SwiftUI

struct PiliAccountUtilitiesView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    var body: some View {
        List {
            NavigationLink { PiliSpacePrivacyView(api: dependencies.api) } label: { Label("空间隐私设置", systemImage: "lock.shield") }
            ForEach(PiliAccountLog.allCases) { kind in NavigationLink(kind.title) { PiliAccountLogView(api: dependencies.api, kind: kind) } }
        }.navigationTitle("账号记录与隐私")
    }
}
private struct PiliAccountLogView: View {
    let api: BiliAPIClient
    let kind: PiliAccountLog
    @State private var items: [DynamicJSONValue] = []
    @State private var error: String?
    @State private var loading = false
    @State private var identity: PiliAccountIdentity?
    var body: some View {
        List {
            if loading { ProgressView() }
            if let error { Text(error); Button("重试") { Task { await load() } } }
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 6) {
                    switch kind {
                    case .devices:
                        Text(item["device_name"].piliString).font(.headline)
                        Text([item["source"].piliString, item["latest_login_at"].piliString].joined(separator: " · ")).font(.caption)
                        if item["is_current_device"].piliInt == 1 { Text("服务端标记的当前设备").font(.caption).foregroundStyle(.secondary) }
                    case .logins:
                        Text(item["time_at"].piliString).font(.headline)
                        Text(item["geo"].piliString); Text(item["ip"].piliString).font(.caption).foregroundStyle(.secondary)
                    default:
                        HStack { Text(item["reason"].piliString); Spacer(); Text(item["delta"].piliString).monospacedDigit() }
                        Text(item["time"].piliString).font(.caption).foregroundStyle(.secondary)
                    }
                }.textSelection(.enabled)
            }
            if !loading, error == nil, items.isEmpty { ContentUnavailableView("暂无记录", systemImage: "list.bullet.rectangle") }
        }.navigationTitle(kind.title).task { identity = .init(api.requestSnapshot()); await load() }.refreshable { await load() }
    }
    private func load() async {
        guard !loading, let identity else { return }; loading = true; error = nil
        defer { loading = false }
        do { let result = try await api.piliAccountLog(kind, identity: identity); if !Task.isCancelled { items = result } }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
private struct PiliSpacePrivacyView: View {
    let api: BiliAPIClient
    @State private var values: [String: Int] = [:]
    @State private var initial: [String: Int] = [:]
    @State private var identity: PiliAccountIdentity?
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        Form {
            if loading { ProgressView() }
            if let error { Text(error); if values.isEmpty { Button("重试") { Task { await load() } } } }
            ForEach(PiliSpacePrivacyField.all.filter { values[$0.id] != nil }) { field in
                Toggle(field.title, isOn: Binding(get: { field.isOn(values[field.id] ?? 0) }, set: { values[field.id] = field.value($0) }))
            }
            Button("保存设置") { Task { await save() } }.disabled(loading || values.isEmpty || values == initial)
        }.disabled(loading).navigationTitle("空间隐私").task { identity = .init(api.requestSnapshot()); await load() }
    }
    private func load() async {
        guard !loading, let identity else { return }; loading = true; error = nil
        defer { loading = false }
        do { let result = try await api.piliSpacePrivacy(identity: identity); guard !Task.isCancelled else { return }; values = result; initial = result }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func save() async {
        guard !loading, let identity else { return }; loading = true; error = nil
        let pending = values
        defer { loading = false }
        do { try await api.piliSaveSpacePrivacy(pending, identity: identity); guard identity.matches(api.requestSnapshot()) else { throw PiliOfflineError.message("账号已切换") }; initial = pending }
        catch { self.error = error.localizedDescription }
    }
}
