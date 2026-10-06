import Foundation

nonisolated struct PiliContentToken: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var text: String
    var type: Int = 1
    var businessID: String = ""
    var json: PiliJSON { .object(["raw_text": .string(text), "type": .int(type), "biz_id": .string(businessID)]) }
}

nonisolated struct PiliDynamicDraft: Codable, Equatable, Sendable {
    var title = ""
    var tokens: [PiliContentToken] = []
    var pictures: [PiliDraftPicture] = []
    var topicID: Int?
    var topicName = ""
    var privatePost = false
    var commentPolicy = 0 // 0: open; 1: close; 2: selected by author
    var scheduledAt: Date?
    var editingID: String?
    var repostID: String?
    var voteID: Int?
    var voteTitle = ""
    var reservation: PiliReservationDraft?
    var plainText: String { tokens.map(\.text).joined() }
    var hasContent: Bool { !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pictures.isEmpty || repostID != nil }

    func validate(now: Date = Date(), pendingImages: Int = 0) throws {
        guard hasContent || pendingImages > 0 || voteID != nil || reservation != nil else { throw PiliOfflineError.message("请输入动态内容或添加图片") }
        guard plainText.count <= 10_000, title.count <= 100, pictures.count + pendingImages <= 9 else { throw PiliOfflineError.message("正文最多 10000 字、标题最多 100 字、图片最多 9 张") }
        if let scheduledAt, scheduledAt <= now.addingTimeInterval(60) { throw PiliOfflineError.message("定时发布至少在一分钟之后") }
        guard tokens.allSatisfy({ [1, 2, 4, 9].contains($0.type) && ($0.type != 2 || Int($0.businessID) ?? 0 > 0) }) else {
            throw PiliOfflineError.message("提及用户信息无效，请重新选择")
        }
    }
    func payload(mid: Int, uploadID: String) throws -> PiliJSON {
        try validate()
        var contents = tokens.map(\.json)
        if let voteID { contents.append(.object(["raw_text": .string(voteTitle), "type": .int(4), "biz_id": .string(String(voteID))])) }
        var options: [String: PiliJSON] = ["private_pub": .int(privatePost ? 1 : 0)]
        if commentPolicy == 1 { options["close_comment"] = .int(1) }
        if commentPolicy == 2 { options["up_choose_comment"] = .int(1) }
        if let scheduledAt { options["timer_pub_time"] = .int(Int(scheduledAt.timeIntervalSince1970)) }
        var request: [String: PiliJSON] = [
            "content": .object(["title": .string(title), "contents": .array(contents)]),
            "scene": .int(repostID != nil ? 4 : pictures.isEmpty ? 1 : 2),
            "option": .object(options), "upload_id": .string(uploadID),
            "meta": .object(["app_meta": .object(["from": .string("create.dynamic.web"), "mobi_app": .string("web")])])]
        if let reservation {
            request["attach_card"] = .object(["common_card": .object(["type": .int(14), "biz_id": .int(reservation.id), "reserve_source": .int(0), "reserve_lottery": .int(0)])])
        }
        if !pictures.isEmpty { request["pics"] = .array(pictures.map(\.json)) }
        if let topicID { request["topic"] = .object(["id": .int(topicID), "name": .string(topicName), "from_source": .string("dyn.web.list"), "from_topic_id": .int(0)]) }
        var body: [String: PiliJSON] = ["dyn_req": .object(request)]
        if let editingID { body["dyn_id_str"] = .string(editingID) }
        if let repostID { body["web_repost_src"] = .object(["dyn_id_str": .string(repostID)]) }
        return .object(body)
    }
}

nonisolated struct PiliDraftPicture: Codable, Equatable, Identifiable, Sendable {
    var id: String { url }
    var url: String
    var width: Int
    var height: Int
    var json: PiliJSON { .object(["img_src": .string(url), "img_width": .int(width), "img_height": .int(height)]) }
}

nonisolated struct PiliNamedResource: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    var subtitle = ""
    var image: String?
}

nonisolated enum PiliDynamicCategory: String, CaseIterable, Identifiable, Sendable {
    case all, video, pgc, article
    var id: String { rawValue }
    var title: String { switch self { case .all: "全部"; case .video: "投稿"; case .pgc: "番剧"; case .article: "专栏" } }
}
