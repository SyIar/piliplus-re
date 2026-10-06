import Foundation

extension BiliAPIClient {
    func piliEditingDraft(id: String, identity: PiliAccountIdentity) async throws -> PiliDynamicDraft {
        let data = try await piliContentRead("/x/polymer/web-dynamic/v1/detail", query: ["id": id, "features": "itemOpusStyle,onlyfansVote"], identity: identity)
        let item = data["item"]
        guard item["modules"]["module_author"]["mid"].piliInt == identity.mid else { throw PiliOfflineError.message("只能编辑自己的动态") }
        let decoded = try item.piliDecode(DynamicFeedItem.self)
        var draft = PiliDynamicDraft.editing(decoded)
        let module = item["modules"]["module_dynamic"], opus = module["major"]["opus"]
        draft.title = opus["title"].piliString
        let topic = module["topic"]
        if topic["id"].piliInt > 0 { draft.topicID = topic["id"].piliInt; draft.topicName = topic["name"].piliString }
        let desc = module["desc"].piliObject.isEmpty ? opus["summary"] : module["desc"]
        let nodes = desc["rich_text_nodes"].piliArray
        if !nodes.isEmpty {
            draft.tokens = nodes.compactMap { node in
                let text = node["orig_text"].piliString.isEmpty ? node["text"].piliString : node["orig_text"].piliString
                switch node["type"].piliString {
                case "RICH_TEXT_NODE_TYPE_VOTE":
                    draft.voteID = node["rid"].piliInt; draft.voteTitle = text; return nil
                case "RICH_TEXT_NODE_TYPE_AT": return .init(text: text, type: 2, businessID: node["rid"].piliString)
                case "RICH_TEXT_NODE_TYPE_EMOJI": return .init(text: text, type: 9)
                default: return .init(text: text)
                }
            }
        }
        let vote = module["additional"]["vote"]
        if draft.voteID == nil, vote["vote_id"].piliInt > 0 { draft.voteID = vote["vote_id"].piliInt; draft.voteTitle = vote["desc"].piliString }
        let option = item["option"]
        draft.privatePost = option["private_pub"].piliInt == 1 || !item["modules"]["module_author"]["badge_text"].piliString.isEmpty
        draft.commentPolicy = option["close_comment"].piliInt == 1 ? 1 : option["up_choose_comment"].piliInt == 1 ? 2 : 0
        return draft
    }
    func piliVote(id: Int) async throws -> DynamicJSONValue {
        let data = try await piliContentRead("/x/vote/vote_info", query: ["vote_id": String(id)])
        var info = data["vote_info"].piliObject
        guard info["vote_id"]?.piliInt == id else { throw BiliAPIError.missingPayload }
        info["my_votes"] = data["my_votes"]
        return .object(info)
    }
    func piliCastVote(id: Int, options: Set<Int>, anonymous: Bool, dynamicID: String?, identity: PiliAccountIdentity) async throws -> DynamicJSONValue {
        guard id > 0, !options.isEmpty else { throw BiliAPIError.missingPayload }
        let context = await requestSnapshot(purpose: .main)
        guard identity.matches(context), let csrf = context.csrfToken else { throw BiliAPIError.missingCSRF }
        return try await piliContentWrite("/x/vote/do_vote", body: .object([
            "vote_id": .int(id), "votes": .array(options.sorted().map(PiliJSON.int)), "voter_uid": .int(identity.mid),
            "status": .int(anonymous ? 1 : 0), "op_bit": .int(0), "dynamic_id": .int(Int(dynamicID ?? "") ?? 0),
            "csrf_token": .string(csrf), "csrf": .string(csrf)]), identity: identity)["vote_info"]
    }
    func piliTopic(id: Int, offset: String = "", sort: Int = 0, folded: Bool = false) async throws -> DynamicJSONValue {
        try await piliContentRead(folded ? "/x/topic/web/details/fold" : "/x/topic/web/details/cards",
            query: ["topic_id": String(id), "offset": offset, "sort_by": String(sort), "page_size": "20", "source": "Web", "features": "itemOpusStyle,onlyfansVote"])["topic_card_list"]
    }
    func piliTopicAction(id: Int, favorite: Bool? = nil, like: Bool? = nil, identity: PiliAccountIdentity) async throws {
        if let favorite {
            try await piliContentWrite(favorite ? "/x/topic/fav/sub/add" : "/x/topic/fav/sub/cancel", fields: ["topic_id": String(id)], identity: identity)
        } else if let like {
            try await piliContentWrite("/x/topic/like", fields: ["topic_id": String(id), "up_mid": String(identity.mid), "business": "topic", "action": like ? "like" : "cancel_like"], identity: identity)
        }
    }
}
