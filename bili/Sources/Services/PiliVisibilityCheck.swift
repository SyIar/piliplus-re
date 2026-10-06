import Combine
import Foundation
import ChunUI

nonisolated enum PiliVisibilityTarget: Sendable {
    case dynamic(String)
    case comment(oid: String, type: Int, id: Int, root: Int)
    var title: String { if case .dynamic = self { "动态" } else { "评论" } }
    var purpose: BiliAccountPurpose { if case .dynamic = self { .main } else { .interaction } }
    var key: String { if case .dynamic = self { "piliplus.visibility.dynamic" } else { "piliplus.visibility.comment" } }
}
nonisolated struct PiliVisibilityResult: Identifiable, Sendable {
    let id = UUID()
    let date = Date()
    let title: String
    let message: String
    let publicRead: Bool
}

extension BiliAPIClient {
    func piliCheckVisibility(_ target: PiliVisibilityTarget, identity: PiliAccountIdentity) async throws -> PiliVisibilityResult {
        let context = requestSnapshot(purpose: target.purpose)
        guard identity.matches(context) else { throw PiliOfflineError.message("账号已切换，请重新检查") }
        func read(_ path: String, query: [String: String], anonymous: Bool) async throws -> BiliResponse<DynamicJSONValue> {
            try await get(base: baseURL, path: path, query: query, cookieHeader: anonymous ? "" : context.cookieHeader,
                cachePolicy: .reloadIgnoringLocalCacheData)
        }
        let visible: Bool
        var note = ""
        switch target {
        case .dynamic(let id):
            let result = try await read("/x/polymer/web-dynamic/v1/detail", query: ["id": id], anonymous: true)
            visible = result.code == 0 && result.payload?["item"]["id_str"].piliString == id
            if result.code != 0 { note = "（接口状态 \(result.code)）" }
        case let .comment(oid, type, id, root):
            let rootID = root > 0 ? root : id
            var found = false, exhausted = false, seen = Set<Int>()
            for page in 1...50 {
                try Task.checkCancellation()
                let result = try await read("/x/v2/reply/reply", query: ["oid": oid, "type": String(type), "root": String(rootID),
                    "pn": String(page), "ps": "20", "sort": "1"], anonymous: true)
                if result.code != 0 { note = "（接口状态 \(result.code)）"; exhausted = true; break }
                let data = result.payload ?? .null
                if root == 0, data["root"]["rpid"].piliInt == id { found = true; break }
                let replies = data["replies"].piliArray
                if replies.contains(where: { $0["rpid"].piliInt == id }) { found = true; break }
                let added = replies.filter { seen.insert($0["rpid"].piliInt).inserted }
                if replies.isEmpty || added.isEmpty || replies.count < 20 { exhausted = true; break }
            }
            visible = found
            if !found, !exhausted { note = "（回复较多，已检查前 1000 条）" }
        }
        guard identity.matches(requestSnapshot(purpose: target.purpose)) else { throw PiliOfflineError.message("账号已切换，请重新检查") }
        return .init(title: "\(target.title)可见性检查", message: visible
            ? "未携带账号 Cookie 时可以读取此\(target.title)。此结果不代表所有推荐或列表都会展示。"
            : "目前未能以游客身份读取此\(target.title)\(note)。审核延迟、隐私设置、登录要求或平台限制都可能影响结果，可稍后重试或申诉。", publicRead: visible)
    }
}

@MainActor
final class PiliVisibilityCheckCenter: ObservableObject {
    static let shared = PiliVisibilityCheckCenter()
    @Published private(set) var results: [PiliVisibilityResult] = []
    private var tasks: [UUID: Task<Void, Never>] = [:]
    func schedule(_ target: PiliVisibilityTarget, api: BiliAPIClient, identity: PiliAccountIdentity) {
        guard UserDefaults.standard.bool(forKey: target.key) else { return }
        let id = UUID()
        tasks[id] = Task { [weak self] in
            defer { self?.tasks[id] = nil }
            do {
                try await Task.sleep(for: .seconds(8))
                let result = try await api.piliCheckVisibility(target, identity: identity)
                self?.results.insert(result, at: 0)
                if let self, self.results.count > 20 { self.results.removeLast(self.results.count - 20) }
                CCToastCenter.shared.show(.success, result.publicRead ? "\(target.title)检查：游客可读取" : "\(target.title)未确认对外可见，可在隐私设置查看详情")
            } catch {
                guard !Task.isCancelled, identity.matches(api.requestSnapshot(purpose: target.purpose)) else { return }
                if let self, self.results.count >= 20 { self.results.removeLast(self.results.count - 19) }
                self?.results.insert(.init(title: "\(target.title)检查未完成", message: error.localizedDescription, publicRead: false), at: 0)
            }
        }
    }
}
