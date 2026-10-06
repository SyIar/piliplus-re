import Foundation

nonisolated struct PiliRankCategory: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let rid: Int?
    let seasonType: Int?
    static let all: [Self] = [
        .init(id: "all", title: "全站", rid: 0, seasonType: nil),
        .init(id: "anime", title: "番剧", rid: nil, seasonType: 1), .init(id: "guochuang", title: "国创", rid: nil, seasonType: 4)
    ] + [(1005,"动画"),(1003,"音乐"),(1004,"舞蹈"),(1008,"游戏"),(1010,"知识"),(1012,"科技"),(1018,"运动"),(1013,"汽车"),(1020,"美食"),(1024,"动物"),(1007,"鬼畜"),(1014,"时尚"),(1002,"娱乐"),(1001,"影视")].map { .init(id: "rid\($0.0)", title: $0.1, rid: $0.0, seasonType: nil) }
    + [(3,"纪录片"),(2,"电影"),(5,"剧集"),(7,"综艺")].map { .init(id: "season\($0.0)", title: $0.1, rid: nil, seasonType: $0.0) }
}
nonisolated struct PiliWeeklyIssue: Identifiable, Sendable {
    let id: Int
    let title: String
}
extension BiliAPIClient {
    func piliWeeklyIssues() async throws -> [PiliWeeklyIssue] {
        let data = try await piliContentRead("/x/web-interface/popular/series/list", query: ["web_location": "333.934"], signed: true, referer: "https://www.bilibili.com/v/popular/weekly")
        var seen = Set<Int>()
        return data["list"].piliArray.compactMap {
            let id = $0["number"].piliInt
            guard id > 0, seen.insert(id).inserted else { return nil }
            return .init(id: id, title: $0["name"].piliString)
        }
    }
    func piliDiscoveryVideos(weekly: Int? = nil, preciousPage: Int? = nil, rank: PiliRankCategory? = nil) async throws -> (videos: [VideoItem], media: [SearchMediaItem], more: Bool) {
        let path: String, query: [String: String], referer: String
        if let weekly {
            path = "/x/web-interface/popular/series/one"; query = ["number": String(weekly), "web_location": "333.934"]
            referer = "https://www.bilibili.com/v/popular/weekly?num=\(weekly)"
        } else if let page = preciousPage {
            path = "/x/web-interface/popular/precious"; query = ["page_size": "100", "page": String(page), "web_location": "333.934"]
            referer = "https://www.bilibili.com/v/popular/history"
        } else if let rank {
            if let rid = rank.rid { path = "/x/web-interface/ranking/v2"; query = ["rid": String(rid), "type": "all"] }
            else { path = rank.seasonType == 1 ? "/pgc/web/rank/list" : "/pgc/season/rank/web/list"; query = ["day": "3", "season_type": String(rank.seasonType ?? 1)] }
            referer = "https://www.bilibili.com/v/popular/rank/all"
        } else { throw BiliAPIError.missingPayload }
        let data = try await piliContentRead(path, query: query, signed: true, referer: referer)
        let raw = data["list"].piliArray
        if rank?.seasonType != nil { return ([], raw.compactMap { try? $0.piliDecode(SearchMediaItem.self) }.filter { ($0.seasonID ?? 0) > 0 }, false) }
        return (raw.compactMap { try? $0.piliDecode(VideoItem.self) }, [], preciousPage != nil && raw.count >= 100)
    }
}
