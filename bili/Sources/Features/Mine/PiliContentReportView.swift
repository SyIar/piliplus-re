import SwiftUI

nonisolated enum PiliContentReportTarget: Sendable {
    case dynamic(id: String, author: Int)
    case danmaku(id: String, cid: Int)
    var reasons: [(Int, String)] {
        switch self {
        case .dynamic: [(4, "垃圾广告"), (8, "引战"), (1, "色情"), (5, "人身攻击"), (3, "违法信息"), (9, "涉政谣言"), (10, "涉社会事件谣言"), (12, "虚假不实信息"), (13, "违法信息外链"), (0, "其他")]
        case .danmaku: [(1, "违法违禁"), (2, "色情低俗"), (3, "赌博诈骗"), (4, "人身攻击"), (5, "侵犯隐私"), (6, "垃圾广告"), (7, "引战"), (8, "剧透"), (9, "恶意刷屏"), (10, "视频无关"), (12, "青少年不良信息"), (13, "违法信息外链"), (11, "其他")]
        }
    }
    var otherReason: Int { if case .dynamic = self { 0 } else { 11 } }
}

struct PiliContentReportView: View {
    let api: BiliAPIClient
    let target: PiliContentReportTarget
    private let identity: PiliAccountIdentity
    @State private var reason: Int?
    @State private var description = ""
    @State private var busy = false
    @State private var message: String?
    @State private var submitted = false
    init(api: BiliAPIClient, target: PiliContentReportTarget) {
        self.api = api; self.target = target; identity = PiliAccountIdentity(api.requestSnapshot(purpose: .main))
    }
    var body: some View {
        PiliForm {
            Picker("举报原因", selection: $reason) {
                Text("请选择").tag(Optional<Int>.none)
                ForEach(target.reasons, id: \.0) { value in Text(value.1).tag(Optional(value.0)) }
            }
            Section("补充说明") { TextEditor(text: $description).frame(minHeight: 120) }
            Button(submitted ? "已提交" : "提交举报", role: .destructive) { Task { await submit() } }
                .disabled(busy || submitted || reason == nil || (reason == target.otherReason && description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            if busy { ProgressView() }
            if let message { Text(message) }
        }.navigationTitle("举报").navigationBarTitleDisplayMode(.inline)
    }
    private func submit() async {
        guard !busy, !submitted, let reason, target.reasons.contains(where: { $0.0 == reason }) else { return }
        busy = true; message = nil; defer { busy = false }
        do {
            switch target {
            case let .dynamic(id, author):
                try await api.piliContentWrite("/x/dynamic/feed/dynamic_report/add", fields: ["accused_uid": String(author), "dynamic_id": id, "reason_type": String(reason), "reason_desc": description], identity: identity)
            case let .danmaku(id, cid):
                try await api.piliContentWrite("/x/dm/report/add", fields: ["cid": String(cid), "dmid": id, "reason": String(reason), "block": "false", "originCid": String(cid), "content": description, "polaris_app_id": "100", "polaris_platform": "5", "spmid": "333.788.0.0", "from_spmid": "333.788.0.0", "statistics": "{\"appId\":100,\"platform\":5,\"abtest\":\"\",\"version\":\"\"}"], identity: identity)
            }
            submitted = true; message = "举报已提交"
        } catch { message = error.localizedDescription }
    }
}
