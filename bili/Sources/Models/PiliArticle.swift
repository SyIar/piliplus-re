import Foundation

nonisolated struct PiliArticleRoute: Hashable, Identifiable, Sendable {
    enum Kind: String, Sendable { case read, opus }
    let id: String
    let kind: Kind
    init(id: String, kind: Kind) { self.id = id; self.kind = kind }
    init?(url: URL) {
        let parts = url.pathComponents.filter { $0 != "/" }, host = url.host?.lowercased() ?? ""
        if url.scheme == "bilibili", host == "article", let last = parts.last, Int64(last) != nil { id = last; kind = .read; return }
        guard host == "bilibili.com" || host.hasSuffix(".bilibili.com"), let last = parts.last else { return nil }
        if parts.contains("read"), last.hasPrefix("cv"), Int64(last.dropFirst(2)) != nil { id = String(last.dropFirst(2)); kind = .read }
        else if parts.contains("opus"), Int64(last) != nil { id = last; kind = .opus }
        else { return nil }
    }
    var url: URL { URL(string: kind == .read ? "https://www.bilibili.com/read/cv\(id)" : "https://www.bilibili.com/opus/\(id)")! }
}

nonisolated struct PiliArticleDocument: Sendable {
    let route: PiliArticleRoute
    let title: String
    let author: VideoOwner?
    let paragraphs: [DynamicJSONValue]
    let html: String
    let operations: [DynamicJSONValue]
    let commentID: Int
    let commentType: Int
    let dynamicID: String
    let cover: String
    let blockedText: String
    let liked: Bool
    let favorited: Bool
    init(route: PiliArticleRoute, body: DynamicJSONValue, info: DynamicJSONValue = .null) {
        self.route = route
        if route.kind == .read {
            title = body["title"].piliString.isEmpty ? info["title"].piliString : body["title"].piliString
            let owner = body["author"]
            author = owner["mid"].piliInt > 0 ? VideoOwner(mid: owner["mid"].piliInt, name: owner["name"].piliString, face: owner["face"].piliString) : nil
            paragraphs = body["opus"]["content"].piliArray; html = body["content"].piliString; operations = body["ops"].piliArray
            commentID = Int(route.id) ?? 0; commentType = 12; dynamicID = body["dyn_id_str"].piliString
            cover = info["origin_image_urls"].piliArray.first?.piliString ?? ""; blockedText = ""
            liked = info["like"].piliInt == 1; favorited = info["favorite"].piliInt == 1
        } else {
            let item = body["item"], modules = item["modules"].piliArray
            func module(_ name: String) -> DynamicJSONValue { modules.first { !$0[name].piliObject.isEmpty }?[name] ?? .null }
            title = module("module_title")["text"].piliString
            let owner = module("module_author")
            author = owner["mid"].piliInt > 0 ? VideoOwner(mid: owner["mid"].piliInt, name: owner["name"].piliString, face: owner["face"].piliString) : nil
            paragraphs = module("module_content")["paragraphs"].piliArray; html = ""; operations = []
            commentID = item["basic"]["comment_id_str"].piliInt; commentType = item["basic"]["comment_type"].piliInt
            dynamicID = item["id_str"].piliString; cover = ""
            let blocked = module("module_blocked")
            blockedText = blocked.piliObject.isEmpty ? "" : blocked["title"].piliString.isEmpty ? "正文暂不可查看，请查看原文中的访问条件" : blocked["title"].piliString
            liked = module("module_stat")["like"]["status"].piliInt == 1; favorited = module("module_stat")["favorite"]["status"].piliInt == 1
        }
    }
    func commentTarget() throws -> DynamicFeedItem {
        try DynamicJSONValue.object([
            "id_str": .string(dynamicID.isEmpty ? route.id : dynamicID), "type": .string("DYNAMIC_TYPE_WORD"),
            "basic": .object(["comment_id_str": .string(String(commentID)), "comment_type": .number(String(commentType))]),
            "modules": .object(["module_author": .object(["mid": .number(String(author?.mid ?? 0)), "name": .string(author?.name ?? "")])])
        ]).piliDecode(DynamicFeedItem.self)
    }
}

extension BiliAPIClient {
    func piliArticle(_ route: PiliArticleRoute) async throws -> PiliArticleDocument {
        if route.kind == .read {
            async let body = piliContentRead("/x/article/view", query: ["id": route.id, "gaia_source": "main_web", "web_location": "333.976"], signed: true)
            async let info = piliContentRead("/x/article/viewinfo", query: ["id": route.id, "mobi_app": "pc", "from": "web", "gaia_source": "main_web"], signed: true)
            let (b, i) = try await (body, info)
            return .init(route: route, body: b, info: i)
        }
        let body = try await piliContentRead("/x/polymer/web-dynamic/v1/opus/detail", query: ["id": route.id, "timezone_offset": "-480", "features": "htmlNewStyle"], signed: true)
        if body["fallback"]["id"].piliInt > 0 { return try await piliArticle(.init(id: body["fallback"]["id"].piliString, kind: .read)) }
        return .init(route: route, body: body)
    }
    func piliUserArticles(mid: Int, page: Int) async throws -> DynamicJSONValue {
        try await piliContentRead("/x/v2/space/article", query: ["vmid": String(mid), "pn": String(page), "ps": "10", "build": "8430300", "channel": "master", "version": "8.43.0", "c_locale": "zh_CN", "s_locale": "zh_CN", "mobi_app": "android", "platform": "android"], base: appURL)
    }
}
