import Foundation

nonisolated struct PiliPGCFilter: Identifiable, Sendable {
    let id: String
    let title: String
    let values: [Option]
    nonisolated struct Option: Identifiable, Hashable, Sendable {
        let id: String
        let title: String
    }
    init?(_ json: DynamicJSONValue) {
        let field = json["field"].piliString
        guard !field.isEmpty else { return nil }
        id = field; title = json["name"].piliString
        var seen = Set<String>()
        values = json["values"].piliArray.compactMap {
            let key = $0["keyword"].piliString
            guard !key.isEmpty, seen.insert(key).inserted else { return nil }
            return Option(id: key, title: $0["name"].piliString)
        }
    }
}
nonisolated struct PiliPGCConditions: Sendable {
    let filters: [PiliPGCFilter]
    let order: [PiliPGCFilter.Option]
    init(_ data: DynamicJSONValue) {
        var fields = Set<String>()
        filters = data["filter"].piliArray.compactMap(PiliPGCFilter.init).filter { fields.insert($0.id).inserted }
        fields.removeAll()
        order = data["order"].piliArray.compactMap {
            let field = $0["field"].piliString
            guard !field.isEmpty, fields.insert(field).inserted else { return nil }
            return .init(id: field, title: $0["name"].piliString)
        }
    }
    var defaults: [String: String] {
        var value = Dictionary(uniqueKeysWithValues: filters.compactMap { field in field.values.first.map { (field.id, $0.id) } })
        value["order"] = order.first?.id ?? "3"; value["sort"] = "0"
        return value
    }
}
nonisolated struct PiliPGCTimelineDay: Identifiable, Sendable {
    let id: String
    let title: String
    let episodes: [Episode]
    nonisolated struct Episode: Identifiable, Sendable {
        let id: Int
        let title: String
        let cover: String
        let detail: String
    }
    init?(_ data: DynamicJSONValue) {
        id = data["date"].piliString
        guard !id.isEmpty else { return nil }
        title = id + (data["is_today"].piliInt == 1 ? " · 今天" : "")
        var seen = Set<Int>()
        episodes = data["episodes"].piliArray.compactMap {
            let id = $0["episode_id"].piliInt
            guard id > 0, seen.insert(id).inserted else { return nil }
            return Episode(id: id, title: $0["title"].piliString, cover: $0["cover"].piliString,
                           detail: [$0["pub_time"].piliString, $0["pub_index"].piliString].filter { !$0.isEmpty }.joined(separator: " · "))
        }
    }
}
extension BiliAPIClient {
    func piliPGCConditions(type: Int) async throws -> PiliPGCConditions {
        let data = try await piliContentRead("/pgc/season/index/condition", query: ["season_type": String(type), "type": "0"])
        return .init(data)
    }
    func piliPGCCatalogue(type: Int, page: Int, filters: [String: String]) async throws -> (items: [SearchMediaItem], more: Bool) {
        var query = filters
        query["season_type"] = String(type); query["type"] = "0"; query["page"] = String(max(page, 1)); query["pagesize"] = "21"
        let data = try await piliContentRead("/pgc/season/index/result", query: query)
        return (data["list"].piliArray.compactMap { try? $0.piliDecode(SearchMediaItem.self) }.filter { ($0.seasonID ?? 0) > 0 }, data["has_next"].piliInt == 1)
    }
    func piliPGCTimeline(type: Int) async throws -> [PiliPGCTimelineDay] {
        let data = try await piliContentRead("/pgc/web/timeline", query: ["types": String(type), "before": "6", "after": "6"])
        var seen = Set<String>()
        return data.piliArray.compactMap(PiliPGCTimelineDay.init).filter { seen.insert($0.id).inserted }
    }
}
