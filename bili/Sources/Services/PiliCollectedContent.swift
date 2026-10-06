import Foundation

nonisolated enum PiliCollectedKind: String, CaseIterable, Identifiable, Sendable {
    case anime, cinema, subscriptions, articles, topics
    var id: String { rawValue }
    var title: String { switch self { case .anime: "追番"; case .cinema: "追剧"; case .subscriptions: "订阅的合集与收藏夹"; case .articles: "收藏图文"; case .topics: "收藏话题" } }
    var isPGC: Bool { self == .anime || self == .cinema }
}
nonisolated struct PiliCollectedPage: Sendable {
    let items: [DynamicJSONValue]
    let more: Bool
}
extension BiliAPIClient {
    func piliCollectedContent(_ kind: PiliCollectedKind, page: Int, status: Int = 0, identity: PiliAccountIdentity) async throws -> PiliCollectedPage {
        guard page > 0, (0...3).contains(status) else { throw BiliAPIError.missingPayload }
        let path: String, query: [String: String]
        switch kind {
        case .anime, .cinema:
            path = "/x/space/bangumi/follow/list"
            var values = ["vmid": String(identity.mid), "type": kind == .anime ? "1" : "2", "pn": String(page), "ps": "15"]
            if status > 0 { values["follow_status"] = String(status) }; query = values
        case .subscriptions: path = "/x/v3/fav/folder/collected/list"; query = ["up_mid": String(identity.mid), "pn": String(page), "ps": "20", "platform": "web"]
        case .articles: path = "/x/polymer/web-dynamic/v1/opus/feed/fav"; query = ["page": String(page), "page_size": "20"]
        case .topics: path = "/x/topic/web/fav/list"; query = ["page_num": String(page), "page_size": "24", "web_location": "333.1387"]
        }
        let data = try await piliContentRead(path, query: query, identity: identity)
        switch kind {
        case .anime, .cinema: return .init(items: data["list"].piliArray, more: page * 15 < data["total"].piliInt)
        case .subscriptions: return .init(items: data["list"].piliArray, more: data["has_more"].piliInt != 0)
        case .articles: return .init(items: data["items"].piliArray, more: data["has_more"].piliInt != 0)
        case .topics: return .init(items: data["topic_list"]["topic_items"].piliArray, more: page * 24 < data["topic_list"]["page_info"]["total"].piliInt)
        }
    }
    func piliOpusFavorite(id: String, add: Bool, identity: PiliAccountIdentity) async throws {
        guard Int64(id).map({ $0 > 0 }) == true else { throw BiliAPIError.missingPayload }
        try await piliContentWrite("/x/community/cosmo/interface/simple_action", body: .object([
            "entity": .object(["object_id_str": .string(id), "type": .object(["biz": .int(2)])]), "action": .int(add ? 3 : 4)
        ]), identity: identity)
    }
    func piliCollectedRemove(_ kind: PiliCollectedKind, item: DynamicJSONValue, identity: PiliAccountIdentity) async throws {
        let id = item["id"].piliInt
        switch kind {
        case .anime, .cinema: try await piliFollowSeason(seasonID: item["season_id"].piliInt, follow: false, identity: identity)
        case .subscriptions:
            guard id > 0 else { throw BiliAPIError.missingPayload }
            let folder = item["type"].piliInt == 11
            try await piliContentWrite(folder ? "/x/v3/fav/folder/unfav" : "/x/v3/fav/season/unfav", fields: folder ? ["media_id": String(id)] : ["season_id": String(id), "platform": "web"], identity: identity)
        case .articles: try await piliOpusFavorite(id: item["opus_id"].piliString, add: false, identity: identity)
        case .topics: try await piliTopicAction(id: id, favorite: false, identity: identity)
        }
    }
    func piliFollowStatus(ids: Set<Int>, status: Int, identity: PiliAccountIdentity) async throws {
        guard !ids.isEmpty, ids.count <= 100, ids.allSatisfy({ $0 > 0 }), (1...3).contains(status) else { throw BiliAPIError.missingPayload }
        try await piliContentWrite("/pgc/web/follow/status/update", fields: ["season_id": ids.sorted().map(String.init).joined(separator: ","), "status": String(status)], identity: identity)
    }
}
