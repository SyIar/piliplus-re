import Foundation

nonisolated struct PiliChatSettings: Equatable, Sendable {
    var receivesPush: Bool
    var muted: Bool
    let canConfigurePush: Bool
}

extension BiliAPIClient {
    func fetchPiliChatSettings(talkerID: Int, identity: PiliAccountIdentity) async throws -> PiliChatSettings {
        let context = await requestSnapshot(purpose: .main)
        guard identity.matches(context), talkerID > 0 else { throw PiliOfflineError.message("账号已切换，请重新打开聊天设置") }
        let base = URL(string: "https://api.vc.bilibili.com")!
        let common = ["build": "0", "mobi_app": "web", "csrf": context.csrfToken ?? "", "csrf_token": context.csrfToken ?? ""]
        let response: BiliResponse<DynamicJSONValue> = try await get(base: base, path: "/link_setting/v1/link_setting/get_session_ss",
            query: common.merging(["talker_uid": String(talkerID)]) { _, new in new }, referer: "https://message.bilibili.com/",
            cookieHeader: context.cookieHeader, cachePolicy: .reloadIgnoringLocalCacheData)
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let sessionSettings = response.payload?.objectValueForDynamicParsing else { throw BiliAPIError.missingPayload }
        let push = sessionSettings["push_setting"]?.intValueForDynamicParsing
        let canConfigurePush = sessionSettings["show_push_setting"]?.intValueForDynamicParsing == 1
        if canConfigurePush, push != 0 && push != 1 { throw BiliAPIError.missingPayload }
        let dnd: BiliResponse<DynamicJSONValue> = try await get(base: base, path: "/link_setting/v1/link_setting/get_msg_dnd",
            query: common.merging(["own_uid": String(identity.mid), "uids_str": String(talkerID)]) { _, new in new },
            referer: "https://message.bilibili.com/", cookieHeader: context.cookieHeader, cachePolicy: .reloadIgnoringLocalCacheData)
        guard dnd.code == 0 else { throw BiliAPIError.api(code: dnd.code, message: dnd.displayMessage) }
        guard let payload = dnd.payload?.objectValueForDynamicParsing else { throw BiliAPIError.missingPayload }
        var muted = false
        if case .array(let entries) = payload["uid_settings"] {
            muted = entries.contains { entry in
                let object = entry.objectValueForDynamicParsing
                let uid = object?["uid"]?.intValueForDynamicParsing
                return (uid == talkerID || (uid == nil && entries.count == 1)) && object?["setting"]?.intValueForDynamicParsing == 1
            }
        }
        return .init(receivesPush: push == 0, muted: muted, canConfigurePush: canConfigurePush)
    }

    func setPiliChatSetting(talkerID: Int, receivesPush: Bool? = nil, muted: Bool? = nil, identity: PiliAccountIdentity) async throws {
        let context = await requestSnapshot(purpose: .main)
        guard identity.matches(context), talkerID > 0 else { throw PiliOfflineError.message("账号已切换，请重新打开聊天设置") }
        guard (receivesPush != nil) != (muted != nil) else { throw BiliAPIError.missingPayload }
        guard let csrf = context.csrfToken, !csrf.isEmpty else { throw BiliAPIError.missingCSRF }
        var body = ["build": "0", "mobi_app": "web", "csrf": csrf, "csrf_token": csrf]
        let endpoint: String
        if let receivesPush {
            endpoint = "set_push_ss"
            body["talker_uid"] = String(talkerID); body["setting"] = receivesPush ? "0" : "1"
        } else {
            endpoint = "set_msg_dnd"
            body["uid"] = String(identity.mid); body["dnd_uid"] = String(talkerID); body["setting"] = muted == true ? "1" : "0"
        }
        let response: BiliResponse<EmptyBiliPayload> = try await postForm(base: URL(string: "https://api.vc.bilibili.com")!,
            path: "/link_setting/v1/link_setting/\(endpoint)", body: body, referer: "https://message.bilibili.com/", cookieHeader: context.cookieHeader,
            retryPolicy: .init(label: "chatSetting", attempts: 1, baseDelayNanoseconds: 0, maxDelayNanoseconds: 0, jitterNanoseconds: 0))
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
    }
}
