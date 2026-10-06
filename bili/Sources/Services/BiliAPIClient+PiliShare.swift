import Foundation

nonisolated struct PiliShareCard: Sendable {
    let title: String
    let url: URL
    let messageType: Int
    let body: PiliJSON
}

extension BiliAPIClient {
    func piliShareCard(url: URL, title: String) async throws -> PiliShareCard {
        let components = url.pathComponents.filter { $0 != "/" }, last = components.last ?? ""
        var fields: [String: PiliJSON] = ["title": .string(title), "headline": .string(title), "url": .string(url.absoluteString)]
        var type = 7
        if url.host == "live.bilibili.com", let id = Int(last) {
            let data = try await piliContentRead("/xlive/web-room/v1/index/getInfoByRoom", query: ["room_id": String(id)], base: URL(string: "https://api.live.bilibili.com"))
            let room = data["room_info"], author = data["anchor_info"]["base_info"]
            fields.merge(["source": .string("直播"), "sourceID": .string(String(id)), "cover": .string(room["cover"].piliString), "title": .string(room["title"].piliString), "desc": .string(room["title"].piliString), "author": .string(author["uname"].piliString), "authorID": .string(room["uid"].piliString)]) { _, n in n }
            type = 14
        } else if components.contains("bangumi"), let id = Int(last.dropFirst(2)), last.hasPrefix("ep") || last.hasPrefix("ss") {
            fields["source"] = .int(last.hasPrefix("ep") ? 16 : 7); fields["id"] = .string(String(id)); fields["source_desc"] = .string("番剧")
        } else if let link = BiliVideoLink(url: url) {
            let video: VideoItem
            if let bvid = link.bvid { video = try await fetchVideoDetail(bvid: bvid) }
            else if let aid = link.aid { video = try await fetchVideoDetail(aid: aid) }
            else { throw BiliAPIError.missingPayload }
            guard let aid = video.aid, aid > 0 else { throw BiliAPIError.missingPayload }
            fields.merge(["source": .int(5), "id": .string(String(aid)), "title": .string(video.title), "headline": .string(video.title), "thumb": .string(video.pic ?? ""), "author": .string(video.owner?.name ?? ""), "author_id": .string(String(video.owner?.mid ?? 0))]) { _, n in n }
        } else if components.contains("read"), last.hasPrefix("cv"), let id = Int(last.dropFirst(2)) {
            let info = try await piliContentRead("/x/article/viewinfo", query: ["id": String(id)], signed: true)
            fields.merge(["source": .int(6), "id": .string(String(id)), "headline": .string(info["title"].piliString), "title": .string("- 哔哩哔哩专栏"), "thumb": .string(info["origin_image_urls"].piliArray.first?.piliString ?? ""), "author": .string(info["author_name"].piliString), "author_id": .string(info["mid"].piliString)]) { _, n in n }
        } else if url.host == "t.bilibili.com" || components.contains("opus"), Int64(last) != nil {
            let data = try await piliContentRead("/x/polymer/web-dynamic/v1/detail", query: ["id": last, "features": "itemOpusStyle"])
            let item = try data["item"].piliDecode(DynamicFeedItem.self)
            fields.merge(["source": .int(11), "id": .string(last), "title": .string(item.displayText ?? title), "headline": .string(""), "thumb": .string(item.imageItems.first?.url ?? item.author?.face ?? ""), "author": .string(item.author?.name ?? ""), "author_id": .string(String(item.author?.mid ?? 0))]) { _, n in n }
        } else { throw PiliOfflineError.message("此链接不支持站内内容卡片") }
        return .init(title: title, url: url, messageType: type, body: .object(fields))
    }
    func piliSendCard(_ card: PiliShareCard, recipient: Int, identity: PiliAccountIdentity) async throws {
        guard recipient > 0 else { throw BiliAPIError.missingPayload }
        let device = UUID().uuidString, content = String(decoding: try JSONEncoder().encode(card.body), as: UTF8.self)
        let query = try await signedWBIQuery(["w_sender_uid": String(identity.mid), "w_receiver_id": String(recipient), "w_dev_id": device])
        try await piliContentWrite("/web_im/v1/web_im/send_msg", fields: [
            "msg[sender_uid]": String(identity.mid), "msg[receiver_id]": String(recipient), "msg[receiver_type]": "1",
            "msg[msg_type]": String(card.messageType), "msg[msg_status]": "0", "msg[dev_id]": device,
            "msg[timestamp]": String(Int(Date().timeIntervalSince1970)), "msg[new_face_version]": "1", "msg[content]": content,
            "from_firework": "0", "build": "0", "mobi_app": "web"], query: query, identity: identity,
            base: URL(string: "https://api.vc.bilibili.com"))
    }
}
