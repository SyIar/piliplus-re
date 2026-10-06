import Foundation

nonisolated struct PiliPGCReview: Identifiable, Sendable {
    let id: Int
    let author: VideoOwner
    let title: String
    let text: String
    let date: String
    let score: Int
    let articleID: Int
    var likes: Int
    var liked: Bool
    var disliked: Bool
    init?(_ data: DynamicJSONValue) {
        id = data["review_id"].piliInt; guard id > 0 else { return nil }
        let user = data["author"]
        author = .init(mid: user["mid"].piliInt, name: user["uname"].piliString, face: user["avatar"].piliString)
        title = data["title"].piliString; text = data["content"].piliString; date = data["push_time_str"].piliString
        score = min(max(data["score"].piliInt, 0), 10); articleID = data["article_id"].piliInt
        likes = max(0, data["stat"]["likes"].piliInt); liked = data["stat"]["liked"].piliInt == 1; disliked = data["stat"]["disliked"].piliInt == 1
    }
}
nonisolated enum PiliPGCReviewMutation: Sendable {
    case like(Int), dislike(Int), delete(Int)
    case save(id: Int?, score: Int, text: String, share: Bool)
}
extension BiliAPIClient {
    func piliPGCReviews(mediaID: Int, long: Bool, latest: Bool, cursor: String?) async throws -> (items: [PiliPGCReview], next: String?, total: Int?) {
        var query = ["media_id": String(mediaID), "ps": "20", "sort": latest ? "1" : "0", "web_location": "666.19"]
        query["cursor"] = cursor
        let data = try await piliContentRead(long ? "/pgc/review/long/list" : "/pgc/review/short/list", query: query)
        let next = data["next"].piliString
        return (data["list"].piliArray.compactMap(PiliPGCReview.init), next.isEmpty ? nil : next, (long && latest) ? nil : (data["count"].intValueForDynamicParsing ?? data["total"].intValueForDynamicParsing))
    }
    func piliMutatePGCReview(mediaID: Int, action: PiliPGCReviewMutation, identity: PiliAccountIdentity) async throws {
        guard mediaID > 0 else { throw BiliAPIError.missingPayload }
        var fields = ["media_id": String(mediaID)]
        let path: String
        switch action {
        case .like(let id), .dislike(let id), .delete(let id):
            guard id > 0 else { throw BiliAPIError.missingPayload }; fields["review_id"] = String(id)
            switch action {
            case .like: path = "/pgc/review/action/like"; fields["review_type"] = "2"
            case .dislike: path = "/pgc/review/action/dislike"; fields["review_type"] = "2"
            default: path = "/pgc/review/short/del"
            }
        case .save(let id, let score, let text, let share):
            guard (2...10).contains(score), score % 2 == 0, text.count <= 100 else { throw PiliOfflineError.message("请设置评分，短评最多 100 字") }
            fields["score"] = String(score); fields["content"] = text
            if let id { guard id > 0 else { throw BiliAPIError.missingPayload }; fields["review_id"] = String(id); path = "/pgc/review/short/modify" }
            else { path = "/pgc/review/short/post"; if share { fields["share_feed"] = "1" } }
        }
        try await piliContentWrite(path, fields: fields, identity: identity)
    }
}
