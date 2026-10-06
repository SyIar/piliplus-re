import Foundation

extension BiliAPIClient {
    func publishPiliDynamic(_ draft: PiliDynamicDraft, identity: PiliAccountIdentity) async throws -> String {
        let uploadID = "\(identity.mid)_\(Int(Date().timeIntervalSince1970))_\(Int.random(in: 1000...9999))"
        var query = ["platform": "web", "x-bili-device-req-json": #"{"platform":"web","device":"pc","spmid":"333.1368"}"#]
        if draft.editingID != nil {
            query["w_dyn_req.upload_id"] = uploadID
            query["w_dyn_req.meta"] = #"{"app_meta":{"from":"create.dynamic.web","mobi_app":"web"}}"#
        }
        let result = try await piliContentWrite(draft.editingID == nil ? "/x/dynamic/feed/create/dyn" : "/x/dynamic/feed/edit/dyn",
            body: draft.payload(mid: identity.mid, uploadID: uploadID), query: query, signed: draft.editingID != nil, identity: identity)
        return result["dyn_id_str"].piliString
    }
    func managePiliDynamic(id: String, action: String, identity: PiliAccountIdentity) async throws {
        guard Int64(id) ?? 0 > 0, ["remove", "set_top", "rm_top"].contains(action) else { throw BiliAPIError.missingPayload }
        let path = action == "remove" ? "/x/dynamic/feed/operate/remove" : "/x/dynamic/feed/space/\(action)"
        try await piliContentWrite(path, body: .object([action == "remove" ? "dyn_id_str" : "dyn_str": .string(id)]), identity: identity)
    }
    func piliMentions(keyword: String) async throws -> [PiliNamedResource] {
        let data = try await piliContentRead("/x/polymer/web-dynamic/v1/mention/search", query: ["keyword": keyword, "web_location": "333.1365"])
        return data["groups"].piliArray.flatMap { $0["items"].piliArray }.compactMap { item in
            guard item["uid"].piliInt > 0 else { return nil }
            return PiliNamedResource(id: item["uid"].piliInt, name: item["name"].piliString, image: item["face"].piliString)
        }
    }
    func piliTopics(keyword: String = "", page: Int = 1) async throws -> [PiliNamedResource] {
        let data: DynamicJSONValue
        if keyword.isEmpty {
            data = try await piliContentRead("/x/topic/web/dynamic/rcmd", query: ["source": "Web", "page_size": "25"])
        } else {
            var query = ["keywords": keyword, "content": "", "web_location": "333.1365"]
            if page == 1 { query["page_num"] = "1"; query["page_size"] = "20" }
            else { query["offset"] = String(20 * (page - 1)) }
            data = try await piliContentRead("/x/topic/pub/search", query: query, base: appURL)
        }
        let values = data["topic_items"].piliArray.isEmpty ? data["topics"].piliArray : data["topic_items"].piliArray
        return values.compactMap { item in
            let id = max(item["id"].piliInt, item["topic_id"].piliInt)
            guard id > 0 else { return nil }
            return PiliNamedResource(id: id, name: item["name"].piliString.isEmpty ? item["topic_name"].piliString : item["name"].piliString,
                                     subtitle: item["description"].piliString)
        }
    }
    func createPiliVote(title: String, options: [String], multiple: Int, days: Int, identity: PiliAccountIdentity) async throws -> Int {
        let names = options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !title.isEmpty, title.count <= 80, (2...20).contains(names.count), Set(names).count == names.count,
              (1...names.count).contains(multiple), (1...365).contains(days) else { throw PiliOfflineError.message("请填写标题、至少两个不同选项以及有效的结束时间") }
        let result = try await piliContentWrite("/x/vote/create", body: .object(["vote_info": .object([
            "title": .string(title), "desc": .string(title), "type": .int(0), "choice_cnt": .int(multiple),
            "duration": .int(days * 86400), "vote_publisher": .int(identity.mid), "only_fans_level": .int(0),
            "options": .array(names.map { .object(["opt_desc": .string($0), "img_url": .string("")]) })])]), identity: identity)
        guard result["vote_id"].piliInt > 0 else { throw BiliAPIError.missingPayload }
        return result["vote_id"].piliInt
    }
    func fetchPiliDynamicSearch(mid: Int, keyword: String, offset: String = "", page: Int = 1) async throws -> DynamicFeedData {
        let context = await requestSnapshot(purpose: .dynamicFeed)
        let query = ["host_mid": String(mid), "keyword": keyword, "offset": offset, "page": String(page), "web_location": "333.1387", "features": "itemOpusStyle"]
        let response: BiliResponse<DynamicFeedData> = try await get(base: baseURL, path: "/x/polymer/web-dynamic/v1/feed/space/search", query: query,
            cookieHeader: context.isLoggedIn ? context.cookieHeader : context.anonymousCookieHeader, cachePolicy: .reloadIgnoringLocalCacheData)
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let page = response.payload else { throw BiliAPIError.missingPayload }; return page
    }
}
