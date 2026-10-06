import SwiftUI
import UIKit

struct PiliDanmakuActionsView: View {
    let api: BiliAPIClient
    let item: DanmakuItem
    private let identity: PiliAccountIdentity
    @State private var liked = false
    @State private var busy = false
    @State private var message: String?
    @State private var confirmsRecall = false
    @PiliDismiss private var dismiss
    init(api: BiliAPIClient, item: DanmakuItem) {
        self.api = api; self.item = item; identity = PiliAccountIdentity(api.requestSnapshot(purpose: .main))
    }
    var body: some View {
        NavigationStack {
            PiliForm {
                Text(item.displayText).textSelection(.enabled)
                PiliIconButton("复制", systemImage: "doc.on.doc") { UIPasteboard.general.string = item.displayText; message = "已复制" }
                if let id = item.serverID, let cid = item.cid {
                    PiliIconButton(liked ? "取消点赞" : "点赞", systemImage: liked ? "hand.thumbsup.fill" : "hand.thumbsup") { Task { await like(id: id, cid: cid) } }.disabled(busy)
                    NavigationLink("举报弹幕") { PiliContentReportView(api: api, target: .danmaku(id: id, cid: cid)) }
                    if identity.mid > 0, item.senderHash?.lowercased() == PiliDanmakuRule.userHash(identity.mid) {
                        Button("撤回我的弹幕", role: .destructive) { confirmsRecall = true }.disabled(busy)
                    }
                }
                NavigationLink("屏蔽规则") { PiliDanmakuRulesView(api: api) }
                if busy { ProgressView() }
                if let message { Text(message).foregroundStyle(.secondary) }
            }.navigationTitle("弹幕").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .piliConfirmation("撤回这条弹幕？", isPresented: $confirmsRecall, titleVisibility: .visible) {
                    PiliAlertButton("撤回", role: .destructive) { Task { await recall() } }
                }
                .task {
                    guard let id = item.serverID, let cid = item.cid else { return }
                    if let result = try? await api.piliContentRead("/x/v2/dm/thumbup/stats", query: ["oid": String(cid), "ids": id], identity: identity) {
                        liked = result[id]["user_like"].piliInt == 1
                    }
                }
        }
    }
    private func recall() async {
        guard !busy else { return }; busy = true; message = nil; defer { busy = false }
        do {
            try await api.recallPiliDanmaku(item, identity: identity)
            guard identity.matches(api.requestSnapshot()) else { message = "账号已切换，请重新打开视频"; return }
            PiliDanmakuRulesStore.shared.didRecall(item, identity: identity)
            dismiss()
        } catch { message = error.localizedDescription }
    }
    private func like(id: String, cid: Int) async {
        guard !busy else { return }; busy = true; message = nil; defer { busy = false }
        do {
            try await api.piliContentWrite("/x/v2/dm/thumbup/add", fields: ["op": liked ? "2" : "1", "dmid": id, "oid": String(cid), "platform": "web_player", "polaris_app_id": "100", "polaris_platform": "5", "spmid": "333.788.0.0", "from_spmid": "333.788.0.0", "statistics": "{\"appId\":100,\"platform\":5,\"abtest\":\"\",\"version\":\"\"}"], identity: identity)
            liked.toggle()
        } catch { message = error.localizedDescription }
    }
}
