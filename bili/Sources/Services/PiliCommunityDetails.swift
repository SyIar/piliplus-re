import Foundation

extension BiliAPIClient {
    func piliMusic(_ id: String) async throws -> DynamicJSONValue {
        guard id.hasPrefix("MA"), id.count <= 128 else { throw BiliAPIError.missingPayload }
        return try await piliContentRead("/x/copyright-music-publicity/bgm/detail", query: ["music_id": id, "relation_from": "bgm_page"], signed: true)
    }
    func piliMusicRecommendations(_ id: String) async throws -> [DynamicJSONValue] {
        try await piliContentRead("/x/copyright-music-publicity/bgm/recommend_list", query: ["music_id": id])["list"].piliArray
    }
    func piliMusicWish(_ id: String, selected: Bool, identity: PiliAccountIdentity) async throws {
        try await piliContentWrite("/x/copyright-music-publicity/bgm/wish/update", fields: ["music_id": id, "state": selected ? "2" : "1"], identity: identity)
    }
    func piliBubble(id: String, category: String?, sort: Int?, page: Int) async throws -> DynamicJSONValue {
        guard Int64(id).map({ $0 > 0 }) == true, page > 0 else { throw BiliAPIError.missingPayload }
        var query = ["tribee_id": id, "page_size": "20", "page_num": String(page), "web_location": "333.40165", "x-bili-device-req-json": "{\"platform\":\"web\",\"device\":\"pc\",\"spmid\":\"333.40165\"}"]
        if let category, !category.isEmpty { query["category_id"] = category }
        if let sort { query["sort_type"] = String(sort) }
        return try await piliContentRead("/x/tribee/v1/dyn/all", query: query)
    }
    func piliMatch(_ id: Int) async throws -> DynamicJSONValue {
        guard id > 0 else { throw BiliAPIError.missingPayload }
        return try await piliContentRead("/x/esports/match/info", query: ["cid": String(id), "platform": "2"])["contest"]
    }
}
