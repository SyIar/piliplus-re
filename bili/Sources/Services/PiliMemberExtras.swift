import Foundation

nonisolated enum PiliMemberSection: String, CaseIterable, Identifiable, Sendable {
    case audio, coin, like, comic, bangumi, charging, courses, favorites, guardList, supporters, shop
    var id: String { rawValue }
    var title: String {
        switch self {
        case .audio: "音频"; case .coin: "投币视频"; case .like: "点赞视频"; case .comic: "漫画"; case .bangumi: "番剧投稿"
        case .charging: "充电专属"; case .courses: "课程投稿"; case .favorites: "公开收藏夹"; case .guardList: "大航海"; case .supporters: "充电榜"; case .shop: "小店"
        }
    }
}
nonisolated struct PiliMemberPage: Sendable {
    let items: [DynamicJSONValue]
    let more: Bool
    var levels: [DynamicJSONValue] = []
    var moreURL: URL? = nil
}
extension BiliAPIClient {
    func piliMemberExtras(_ section: PiliMemberSection, mid: Int, page: Int, privilege: Int? = nil) async throws -> PiliMemberPage {
        guard mid > 0, page > 0 else { throw BiliAPIError.missingPayload }
        let data: DynamicJSONValue, listKey: String, pageSize: Int
        switch section {
        case .audio:
            data = try await piliContentRead("/audio/music-service/web/song/upper", query: ["uid": String(mid), "pn": String(page), "ps": "20", "order": "1", "web_location": "333.1387"])
            listKey = "data"; pageSize = 20
        case .coin, .like, .comic, .bangumi, .charging:
            let suffix: String
            switch section { case .coin: suffix = "coinarc"; case .like: suffix = "likearc"; case .comic: suffix = "comic"; case .bangumi: suffix = "bangumi"; default: suffix = "archive/charging" }
            let response: BiliResponse<DynamicJSONValue> = try await get(base: appURL, path: "/x/v2/space/" + suffix,
                query: ["vmid": String(mid), "pn": String(page), "ps": "20", "build": "8430300", "version": "8.43.0", "c_locale": "zh_CN", "channel": "master", "mobi_app": "android", "platform": "android", "s_locale": "zh_CN", "qn": "32", "statistics": BiliAppSigner.Profile.androidLogin.statistics],
                userAgent: BiliAppSigner.Profile.androidLogin.userAgent, additionalHeaders: ["bili-http-engine": "cronet"])
            guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
            data = response.payload ?? .null; listKey = "item"; pageSize = 20
        case .courses:
            data = try await piliContentRead("/pugv/app/web/season/page", query: ["mid": String(mid), "pn": String(page), "ps": "30", "web_location": "333.1387"])
            listKey = "items"; pageSize = 30
        case .favorites:
            data = try await piliContentRead("/x/v3/fav/folder/created/list", query: ["up_mid": String(mid), "pn": String(page), "ps": "20"])
            listKey = "list"; pageSize = 20
        case .guardList:
            data = try await piliContentRead("/xlive/app-ucenter/v1/guard/MainGuardCardAll", query: ["ruid": String(mid), "page": String(page), "page_size": "20"], base: URL(string: "https://api.live.bilibili.com")!)
            return .init(items: data["guard_top_list"].piliArray, more: data["has_more"].piliInt == 1)
        case .supporters:
            var query = ["up_mid": String(mid), "pn": String(page), "ps": "100", "mobi_app": "web", "web_location": "333.1196"]
            if let privilege { query["privilege_type"] = String(privilege) }
            data = try await piliContentRead("/x/upower/up/member/rank/v2", query: query)
            return .init(items: data["rank_info"].piliArray, more: data["rank_info"].piliArray.count >= 100, levels: data["level_info"].piliArray)
        case .shop:
            data = try await piliMemberShop(mid: mid)
            let raw = data["clickUrl"].piliString
            let nested = URLComponents(string: raw)?.queryItems?.first(where: { $0.name == "url" })?.value
            return .init(items: data["data"].piliArray, more: false, moreURL: URL(string: nested ?? raw).flatMap { ["https", "http"].contains($0.scheme ?? "") ? $0 : nil })
        }
        // The audio service calls its array `data`; the app's course service uses `items`.
        let items = data[listKey].piliArray
        let total = max(data["count"].piliInt, max(data["totalSize"].piliInt, data["total"].piliInt))
        return .init(items: items, more: section == .courses ? data["page"]["next"].piliInt != 0 : items.count >= pageSize && (total == 0 || page * pageSize < total))
    }
    private func piliMemberShop(mid: Int) async throws -> DynamicJSONValue {
        let context = await requestSnapshot(), profile = BiliAppSigner.Profile.androidHD
        var query = ["actionKey": "appkey", "build": "8430300", "mVersion": "309", "mallVersion": "8430300", "statistics": BiliAppSigner.Profile.androidLogin.statistics]
        if let key = context.appAccessKey { query["access_key"] = key }
        query = BiliAppSigner.sign(query, profile: profile)
        var request = try await makeRequest(base: URL(string: "https://mall.bilibili.com")!, path: "/community-hub/small_shop/feed/tab/item", query: query,
            userAgent: profile.userAgent, cookieHeader: context.cookieHeader, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(PiliJSON.object(["from": .string("cps_productTab_\(mid)"), "searchAfter": .int(0), "msource": .string("cps_productTab_\(mid)"), "pageSize": .int(8), "upMid": .string(String(mid))]))
        let (bytes, _) = try await data(for: request, priority: URLSessionTask.highPriority, retryPolicy: .api)
        let response: BiliResponse<DynamicJSONValue> = try await Self.decode(bytes, priority: URLSessionTask.highPriority)
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload ?? .null
    }
}
