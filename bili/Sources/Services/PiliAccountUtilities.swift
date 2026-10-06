import Foundation

nonisolated enum PiliAccountLog: String, CaseIterable, Identifiable, Sendable {
    case coins, experience, logins, devices
    var id: String { rawValue }
    var title: String { switch self { case .coins: "硬币记录"; case .experience: "经验记录"; case .logins: "登录记录"; case .devices: "登录设备" } }
    var path: String { switch self { case .coins: "/x/member/web/coin/log"; case .experience: "/x/member/web/exp/log"; case .logins: "/x/member/web/login/log"; case .devices: "/x/safecenter/user_login_devices" } }
}
nonisolated struct PiliSpacePrivacyField: Identifiable, Sendable {
    let id: String
    let title: String
    var reversed = false
    static let all: [Self] = [
        .init(id: "fav_video", title: "公开我的收藏"), .init(id: "bangumi", title: "公开我的追番追剧"),
        .init(id: "comic", title: "公开我的追漫"), .init(id: "coins_video", title: "公开最近投币的视频"),
        .init(id: "likes_video", title: "公开最近点赞的视频"), .init(id: "played_game", title: "公开最近玩过的游戏"),
        .init(id: "dress_up", title: "公开拥有的粉丝装扮"), .init(id: "disable_following", title: "公开关注列表", reversed: true),
        .init(id: "disable_show_fans", title: "公开粉丝列表", reversed: true), .init(id: "close_space_medal", title: "公开佩戴的粉丝勋章", reversed: true),
        .init(id: "only_show_wearing", title: "勋章墙显示全部勋章", reversed: true), .init(id: "disable_show_school", title: "公开学校信息", reversed: true),
        .init(id: "live_playback", title: "投稿中显示直播回放"), .init(id: "charge_video", title: "投稿中显示包月充电专属视频"),
        .init(id: "lesson_video", title: "投稿中显示课堂视频")]
    func isOn(_ value: Int) -> Bool { reversed ? value == 0 : value == 1 }
    func value(_ enabled: Bool) -> Int { enabled != reversed ? 1 : 0 }
}
extension BiliAPIClient {
    func piliAccountLog(_ kind: PiliAccountLog, identity: PiliAccountIdentity) async throws -> [DynamicJSONValue] {
        if kind != .devices {
            return try await piliContentRead(kind.path, query: ["jsonp": "jsonp", "web_location": "333.33"], identity: identity)["list"].piliArray
        }
        let context = requestSnapshot()
        guard identity.matches(context) else { throw PiliOfflineError.message("账号已切换") }
        guard let key = context.appAccessKey, !key.isEmpty else { throw PiliOfflineError.message("登录设备列表需要 App 短信登录凭据") }
        let profile = BiliAppSigner.Profile.androidHD
        let buvid = context.cookieHeader.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.first { $0.hasPrefix("buvid3=") }.map { String($0.dropFirst(7)) } ?? ""
        let query = BiliAppSigner.sign(["local_id": buvid, "buvid": buvid, "device_name": "android", "device_platform": "android",
                                       "csrf": context.csrfToken ?? "", "mobi_app": profile.mobiApp, "platform": profile.platform,
                                       "access_key": key, "statistics": profile.statistics], profile: profile)
        let response: BiliResponse<DynamicJSONValue> = try await get(base: URL(string: "https://passport.bilibili.com")!, path: kind.path,
            query: query, userAgent: profile.userAgent, cookieHeader: context.cookieHeader, cachePolicy: .reloadIgnoringLocalCacheData)
        guard identity.matches(requestSnapshot()) else { throw PiliOfflineError.message("账号已切换") }
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload?["devices"].piliArray ?? []
    }
    func piliSpacePrivacy(identity: PiliAccountIdentity) async throws -> [String: Int] {
        let data = try await piliContentRead("/x/space/setting/app", query: ["mid": String(identity.mid)], identity: identity)["privacy"]
        return Dictionary(uniqueKeysWithValues: PiliSpacePrivacyField.all.compactMap { field in
            guard let value = data[field.id].intValueForDynamicParsing, [0, 1].contains(value) else { return nil }
            return (field.id, value)
        })
    }
    func piliSaveSpacePrivacy(_ values: [String: Int], identity: PiliAccountIdentity) async throws {
        let allowed = Set(PiliSpacePrivacyField.all.map(\.id))
        guard !values.isEmpty, values.allSatisfy({ allowed.contains($0.key) && [0, 1].contains($0.value) }) else { throw BiliAPIError.missingPayload }
        try await piliContentWrite("/x/space/privacy/batch/modify", fields: values.mapValues(String.init), identity: identity)
    }
}
