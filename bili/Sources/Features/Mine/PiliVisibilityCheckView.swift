import SwiftUI

struct PiliVisibilityCheckView: View {
    let api: BiliAPIClient
    let target: PiliVisibilityTarget
    @State private var result: PiliVisibilityResult?
    @State private var error: String?
    @State private var loading = true
    @State private var revision = UUID()
    var body: some View {
        Form {
            if loading { ProgressView("正在使用游客身份检查") }
            if let result { Label(result.message, systemImage: result.publicRead ? "checkmark.circle" : "questionmark.circle") }
            if let error { Text(error) }
            Button("重新检查") { revision = UUID() }.disabled(loading)
            NavigationLink("平台申诉") { PiliAccountWebView(api: api, url: URL(string: "https://www.bilibili.com/h5/comment/appeal")!, title: "申诉", purpose: target.purpose) }
        }.navigationTitle("\(target.title)可见性")
            .task(id: revision) {
                loading = true; error = nil; defer { loading = false }
                do { result = try await api.piliCheckVisibility(target, identity: .init(api.requestSnapshot(purpose: target.purpose))) }
                catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            }
    }
}

struct PiliVisibilitySettingsView: View {
    @AppStorage("piliplus.visibility.comment") private var comments = false
    @AppStorage("piliplus.visibility.dynamic") private var dynamics = false
    @ObservedObject private var center = PiliVisibilityCheckCenter.shared
    var body: some View {
        Form {
            Section {
                Toggle("评论发布后检查", isOn: $comments)
                Toggle("动态发布后检查", isOn: $dynamics)
                Text("对应原版“发评 / 动态反诈”：发布后稍等片刻，检查游客是否可读取内容。检查不使用账号 Cookie，也不会再次发布。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("本次启动的检查结果") {
                if center.results.isEmpty { Text("暂无检查记录") }
                ForEach(center.results) { value in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(value.title).font(.headline); Text(value.message).font(.subheadline)
                        Text(value.date, style: .time).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.navigationTitle("发布可见性检查")
    }
}
