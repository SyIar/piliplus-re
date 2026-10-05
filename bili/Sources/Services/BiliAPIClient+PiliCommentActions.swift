import Foundation

nonisolated enum PiliCommentMutation: Equatable, Sendable {
    case like(Bool), dislike(Bool), pin(Bool), delete
    case report(reason: Int, text: String)
}

nonisolated struct PiliCommentReportReason: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    var requiresDescription: Bool { id == 0 || id == 22 }
    static let all: [Self] = [
        .init(id: 1, title: "垃圾广告"), .init(id: 3, title: "刷屏"), .init(id: 7, title: "人身攻击"),
        .init(id: 15, title: "侵犯隐私"), .init(id: 4, title: "引战"), .init(id: 5, title: "剧透"),
        .init(id: 8, title: "与内容无关"), .init(id: 9, title: "违法违规"), .init(id: 2, title: "色情"),
        .init(id: 10, title: "低俗"), .init(id: 12, title: "赌博诈骗"), .init(id: 23, title: "违法信息外链"),
        .init(id: 19, title: "涉政谣言"), .init(id: 20, title: "涉社会事件谣言"),
        .init(id: 22, title: "虚假不实信息"), .init(id: 18, title: "违规抽奖"),
        .init(id: 17, title: "青少年不良信息"), .init(id: 0, title: "其他")
    ]
}

extension BiliAPIClient {
    func mutatePiliComment(_ action: PiliCommentMutation, oid: String, type: Int, rpid: Int,
                           identity: PiliAccountIdentity, referer: String) async throws {
        let context = await requestSnapshot(purpose: .interaction)
        guard identity.matches(context) else { throw PiliOfflineError.message("互动账号已切换，请重新打开评论菜单") }
        guard let csrf = context.csrfToken, !csrf.isEmpty else { throw BiliAPIError.missingCSRF }
        guard let numericOID = Int64(oid), numericOID > 0, type > 0, rpid > 0 else { throw BiliAPIError.missingPayload }
        var body = ["oid": oid, "type": String(type), "rpid": String(rpid), "csrf": csrf]
        let operation: String
        switch action {
        case .like(let enabled): operation = "action"; body["action"] = enabled ? "1" : "0"
        case .dislike(let enabled): operation = "hate"; body["action"] = enabled ? "1" : "0"
        case .pin(let enabled): operation = "top"; body["action"] = enabled ? "1" : "0"
        case .delete: operation = "del"
        case .report(let reasonID, let text):
            guard let reason = PiliCommentReportReason.all.first(where: { $0.id == reasonID }) else { throw BiliAPIError.missingPayload }
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reason.requiresDescription || !text.isEmpty else { throw PiliOfflineError.message("请补充举报理由") }
            guard text.count <= 1_000 else { throw PiliOfflineError.message("举报说明不能超过 1000 字") }
            operation = "report"
            body.merge(["reason": String(reasonID), "content": text, "add_blacklist": "false",
                        "gaia_source": "main_h5", "platform": "ios", "scene": "main"], uniquingKeysWith: { _, new in new })
        }
        // A timeout is ambiguous: never automatically repeat delete/report or change the acting account.
        let response: BiliResponse<EmptyBiliPayload> = try await postForm(
            base: baseURL, path: "/x/v2/reply/\(operation)", body: body,
            referer: referer, cookieHeader: context.cookieHeader,
            retryPolicy: .init(label: "commentMutation", attempts: 1, baseDelayNanoseconds: 0, maxDelayNanoseconds: 0, jitterNanoseconds: 0)
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
    }
}
