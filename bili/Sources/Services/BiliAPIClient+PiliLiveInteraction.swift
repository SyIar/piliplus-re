import Foundation

nonisolated struct PiliSuperChat: Identifiable, Hashable, Sendable {
    let id: Int
    let uid: Int
    let price: Int
    let message: String
    let name: String
    let face: String
    let start: Date
    let end: Date
    let color: UInt32
    let token: String
    let timestamp: Int

    init?(_ data: DynamicJSONValue) {
        let id = data["id"].piliInt
        let message = ["message", "message_jpn", "message_trans"].map { data[$0].piliString }.first { !$0.isEmpty } ?? ""
        guard id > 0, !message.isEmpty else { return nil }
        self.id = id; self.uid = data["uid"].piliInt; self.price = data["price"].piliInt
        self.message = message; name = data["user_info"]["uname"].piliString; face = data["user_info"]["face"].piliString.normalizedBiliURL()
        start = Date(timeIntervalSince1970: TimeInterval(data["start_time"].piliInt))
        end = Date(timeIntervalSince1970: TimeInterval(data["end_time"].piliInt))
        color = UInt32(data["background_bottom_color"].piliString.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0x3264F0
        token = data["token"].piliString; timestamp = data["ts"].piliInt
    }
    init?(dictionary: [String: Any]) {
        guard let bytes = try? JSONSerialization.data(withJSONObject: dictionary),
              let value = try? JSONDecoder().decode(DynamicJSONValue.self, from: bytes) else { return nil }
        self.init(value)
    }
}

nonisolated struct PiliLiveEmote: Identifiable, Sendable {
    let id: String
    let text: String
    let image: String
    let package: String
    let insertsText: Bool
    let allowed: Bool
    let reason: String
    static func parse(_ data: DynamicJSONValue) -> [Self] {
        var seen = Set<String>()
        return data["data"].piliArray.enumerated().flatMap { index, group in
            group["emoticons"].piliArray.compactMap { value -> Self? in
                let text = value["emoji"].piliString, unique = value["emoticon_unique"].piliString
                let id = unique.isEmpty ? text : unique
                guard !id.isEmpty, seen.insert(id).inserted else { return nil }
                let permission = value["perm"].piliInt
                let unavailable = value.piliObject["perm"] != nil && permission == 0
                return Self(id: id, text: text, image: value["url"].piliString.normalizedBiliURL(),
                    package: group["pkg_name"].piliString.isEmpty ? "表情包 \(index + 1)" : group["pkg_name"].piliString,
                    insertsText: group["pkg_type"].piliInt == 3, allowed: !unavailable,
                    reason: value["unlock_show_text"].piliString)
            }
        }
    }
}

extension BiliAPIClient {
    nonisolated static let piliLiveBase = URL(string: "https://api.live.bilibili.com")!
    func piliSuperChats(roomID: Int) async throws -> [PiliSuperChat] {
        let data = try await piliContentRead("/av/v1/SuperChat/getMessageList", query: ["room_id": String(roomID)], base: Self.piliLiveBase, referer: "https://live.bilibili.com/\(roomID)")
        return data["list"].piliArray.compactMap(PiliSuperChat.init)
    }
    func piliLiveEmotes(roomID: Int, identity: PiliAccountIdentity) async throws -> [PiliLiveEmote] {
        let data = try await piliContentRead("/xlive/web-ucenter/v2/emoticon/GetEmoticons",
            query: ["platform": "pc", "room_id": String(roomID)], identity: identity, base: Self.piliLiveBase, referer: "https://live.bilibili.com/\(roomID)")
        return PiliLiveEmote.parse(data)
    }
    func piliSendLive(roomID: Int, message: String, emote: Bool, identity: PiliAccountIdentity) async throws {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard roomID > 0, !text.isEmpty, text.utf16.count <= 1000 else { throw PiliOfflineError.message("请输入弹幕，最多 1000 字；直播间实际字数限制以平台返回为准") }
        let context = await requestSnapshot()
        guard identity.matches(context) else { throw PiliOfflineError.message("账号已切换，请重新打开输入框") }
        var fields = ["bubble": "0", "msg": text, "color": "16777215", "mode": "1", "fontsize": "25",
            "rnd": String(Int(Date().timeIntervalSince1970)), "roomid": String(roomID), "csrf_token": context.csrfToken ?? ""]
        if emote { fields["dm_type"] = "1"; fields["emoticonOptions"] = "[object Object]" }
        else {
            fields.merge(["room_type": "0", "jumpfrom": "0", "reply_mid": "0", "reply_attr": "0", "replay_dmid": "",
                "statistics": "{\"appId\":100,\"platform\":5}", "reply_type": "0", "reply_uname": ""]) { _, new in new }
        }
        try await piliContentWrite("/msg/send", fields: fields, query: ["web_location": "444.8"], signed: true,
            identity: identity, base: Self.piliLiveBase, referer: "https://live.bilibili.com/\(roomID)")
    }
    func piliReportSuperChat(_ item: PiliSuperChat, roomID: Int, reason: String, identity: PiliAccountIdentity) async throws {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PiliOfflineError.message("请填写举报原因") }
        let context = await requestSnapshot()
        try await piliContentWrite("/av/v1/SuperChat/report", fields: ["id": String(item.id), "id_str": String(item.id),
            "roomid": String(roomID), "uid": String(item.uid), "msg": item.message, "reason": reason, "reason_id": reason,
            "ts": String(item.timestamp), "token": item.token, "sign": "", "visit_id": "", "csrf_token": context.csrfToken ?? ""],
            identity: identity, base: Self.piliLiveBase, referer: "https://live.bilibili.com/\(roomID)")
    }
}
