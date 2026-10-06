import Foundation

nonisolated struct PiliCourseRoute: Identifiable, Hashable, Sendable {
    let seasonID: Int?
    let episodeID: Int?
    var id: String { "\(seasonID ?? 0):\(episodeID ?? 0)" }
    init(seasonID: Int? = nil, episodeID: Int? = nil) { self.seasonID = seasonID; self.episodeID = episodeID }
    init?(url: URL) {
        let host = url.host?.lowercased() ?? "", parts = url.pathComponents.filter { $0 != "/" }
        guard host == "bilibili.com" || host.hasSuffix(".bilibili.com"), parts.contains("cheese"),
              let value = parts.last, let id = Int(value.dropFirst(2)), id > 0 else { return nil }
        if value.hasPrefix("ss") { self.init(seasonID: id) }
        else if value.hasPrefix("ep") { self.init(episodeID: id) }
        else { return nil }
    }
}

extension String {
    nonisolated var piliCourseEpisodeID: Int? {
        guard hasPrefix("pugv-ep") else { return nil }
        return Int(dropFirst(7)).flatMap { $0 > 0 ? $0 : nil }
    }
}
extension VideoItem {
    nonisolated var piliIsCourse: Bool { bvid.piliCourseEpisodeID != nil }
}

extension BiliAPIClient {
    func piliCourseSeason(seasonID: Int?, episodeID: Int?) async throws -> PgcSeasonInfo {
        var query: [String: String] = [:]
        if let seasonID { query["season_id"] = String(seasonID) }
        if let episodeID { query["ep_id"] = String(episodeID) }
        guard !query.isEmpty else { throw BiliAPIError.missingPayload }
        let value = try await piliContentRead("/pugv/view/web/season", query: query, purpose: .playback)
        return try Self.piliCourseSeason(value)
    }
    nonisolated static func piliCourseSeason(_ value: DynamicJSONValue) throws -> PgcSeasonInfo {
        func episodes(_ input: DynamicJSONValue) -> DynamicJSONValue {
            .array(input.piliArray.map { episode in
                var fields = episode.piliObject
                let id = max(episode["id"].piliInt, episode["ep_id"].piliInt)
                fields["bvid"] = .string("pugv-ep\(id)")
                return .object(fields)
            })
        }
        var body = value.piliObject
        body["episodes"] = episodes(value["episodes"])
        body["section"] = .array(value["section"].piliArray.map { section in
            var fields = section.piliObject; fields["episodes"] = episodes(section["episodes"]); return .object(fields)
        })
        // PUGV carries its lecturer under up_info too, but uses name/face on
        // some responses instead of the PGC uname/avatar spelling.
        var up = value["up_info"].piliObject
        if up["uname"] == nil { up["uname"] = up["name"] }
        if up["avatar"] == nil { up["avatar"] = up["face"] }
        body["up_info"] = .object(up)
        return try DynamicJSONValue.object(body).piliDecode(PgcSeasonInfo.self)
    }
    func piliCoursePlayURL(epID: Int, cid: Int, seasonID: Int?, quality: Int) async throws -> PlayURLData {
        let context = await playbackAPIRequestContext()
        var query = ["ep_id": String(epID), "cid": String(cid), "qn": String(quality), "fnval": "4048", "fnver": "0", "fourk": "1", "try_look": "1"]
        if let seasonID { query["season_id"] = String(seasonID) }
        let signed = try await signedWBIQuery(query)
        let response: BiliResponse<PlayURLData> = try await get(base: baseURL, path: "/pugv/player/web/playurl", query: signed,
            referer: "https://www.bilibili.com/cheese/play/ep\(epID)", cookieHeader: context.cookieHeader,
            cachePolicy: .reloadIgnoringLocalCacheData, priority: URLSessionTask.highPriority)
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let data = response.payload else { throw BiliAPIError.missingPayload }
        return await applyingConfiguredHistoryAccount(to: data, playbackUserMID: context.currentUserMID)
    }
    func piliCourseList(mid: Int, page: Int, favorites: Bool) async throws -> DynamicJSONValue {
        try await piliContentRead(favorites ? "/pugv/app/web/favorite/page" : "/pugv/app/web/season/page",
            query: ["mid": String(mid), "pn": String(page), "ps": "20", "web_location": "333.1387"])
    }
    func piliCourseFavorite(seasonID: Int, add: Bool, identity: PiliAccountIdentity) async throws {
        try await piliContentWrite(add ? "/pugv/app/web/favorite/add" : "/pugv/app/web/favorite/del", fields: ["season_id": String(seasonID)], identity: identity)
    }
    func piliFollowSeason(seasonID: Int, follow: Bool, identity: PiliAccountIdentity) async throws {
        try await piliContentWrite(follow ? "/pgc/web/follow/add" : "/pgc/web/follow/del", fields: ["season_id": String(seasonID)], identity: identity)
    }
    func piliSeasonStatus(seasonID: Int, status: Int, identity: PiliAccountIdentity) async throws {
        guard (1...3).contains(status) else { throw BiliAPIError.missingPayload }
        try await piliContentWrite("/pgc/web/follow/status/update", fields: ["season_id": String(seasonID), "status": String(status)], identity: identity)
    }
    func piliSubscribeCollection(seasonID: Int, add: Bool, identity: PiliAccountIdentity) async throws {
        try await piliContentWrite(add ? "/x/v3/fav/season/fav" : "/x/v3/fav/season/unfav", fields: ["season_id": String(seasonID), "platform": "web"], identity: identity)
    }
}
