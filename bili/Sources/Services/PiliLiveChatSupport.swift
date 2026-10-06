import Combine
import Foundation

nonisolated struct PiliLiveMessageMetadata: Hashable, Sendable {
    let uid: Int
    let id: String
    let type: Int
    let timestamp: String
    let signature: String
    let medal: String
    let medalLevel: Int
    let replyUID: Int
    let replyName: String
    var canReport: Bool { uid > 0 && !id.isEmpty && !timestamp.isEmpty && !signature.isEmpty }

    init?(command: [String: Any]) {
        guard let info = command["info"] as? [Any], info.count > 2 else { return nil }
        let head = info[0] as? [Any] ?? []
        let content = head.indices.contains(15) ? head[15] as? [String: Any] ?? [:] : [:]
        let user = content["user"] as? [String: Any] ?? [:]
        let legacy = info[2] as? [Any] ?? []
        uid = Self.integer(user["uid"]) ?? (legacy.first.flatMap(Self.integer)) ?? 0
        var extra: [String: Any] = [:]
        if let text = content["extra"] as? String, text.utf8.count <= 65_536, let data = text.data(using: .utf8) {
            extra = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        }
        let check = info.indices.contains(9) ? info[9] as? [String: Any] ?? [:] : [:]
        id = Self.string(extra["id_str"]); type = Self.integer(extra["dm_type"]) ?? 0
        timestamp = Self.string(check["ts"]); signature = Self.string(check["ct"])
        let medalData = user["medal"] as? [String: Any] ?? [:]
        let legacyMedal = info.indices.contains(3) ? info[3] as? [Any] ?? [] : []
        medal = (medalData["name"] as? String) ?? (legacyMedal.count > 1 ? legacyMedal[1] as? String : nil) ?? ""
        medalLevel = Self.integer(medalData["level"]) ?? legacyMedal.first.flatMap(Self.integer) ?? 0
        replyUID = Self.integer(extra["reply_mid"]) ?? 0; replyName = Self.string(extra["reply_uname"])
    }
    private static func string(_ value: Any?) -> String { (value as? String) ?? (value as? NSNumber)?.stringValue ?? "" }
    private static func integer(_ value: Any?) -> Int? { (value as? Int) ?? Int(string(value)) }
}

nonisolated struct PiliLiveShield: Sendable {
    let keywords: [String]
    let users: [VideoOwner]
    let userIDs: Set<Int>
    init(_ data: DynamicJSONValue) {
        let shield = data["shield_info"]
        var words = Set<String>(), ids = Set<Int>()
        keywords = Array(shield["keyword_list"].piliArray.map(\.piliString).filter { !$0.isEmpty && words.insert($0).inserted }.prefix(500))
        users = Array(shield["shield_user_list"].piliArray.compactMap { item -> VideoOwner? in
            let uid = item["uid"].piliInt
            guard uid > 0, ids.insert(uid).inserted else { return nil }
            return .init(mid: uid, name: item["uname"].piliString, face: nil)
        }.prefix(1_000))
        userIDs = Set(users.map(\.mid))
    }
    func allows(_ item: DanmakuItem) -> Bool {
        !userIDs.contains(item.liveMetadata?.uid ?? item.superChat?.uid ?? 0) && !keywords.contains { item.text.contains($0) }
    }
}

extension BiliAPIClient {
    func piliLiveShield(roomID: Int, identity: PiliAccountIdentity) async throws -> PiliLiveShield {
        let data = try await piliContentRead("/xlive/web-room/v1/index/getInfoByUser", query: ["room_id": String(roomID),
            "from": "0", "not_mock_enter_effect": "1", "web_location": "444.8"], signed: true, identity: identity,
            base: Self.piliLiveBase, referer: "https://live.bilibili.com/\(roomID)")
        return PiliLiveShield(data)
    }
    func piliLiveShieldKeyword(_ keyword: String, remove: Bool, roomID: Int, identity: PiliAccountIdentity) async throws {
        let word = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, word.count <= 100 else { throw PiliOfflineError.message("请输入 1–100 字的关键词") }
        let csrf = await requestSnapshot().csrfToken ?? ""
        try await piliContentWrite("/xlive/web-ucenter/v1/banned/\(remove ? "DelShieldKeyword" : "AddShieldKeyword")",
            fields: ["keyword": word, "csrf_token": csrf], identity: identity, base: Self.piliLiveBase, referer: "https://live.bilibili.com/\(roomID)")
    }
    func piliLiveShieldUser(uid: Int, remove: Bool, roomID: Int, identity: PiliAccountIdentity) async throws {
        guard uid > 0 else { throw PiliOfflineError.message("请输入有效 UID") }
        let csrf = await requestSnapshot().csrfToken ?? ""
        try await piliContentWrite("/liveact/shield_user", fields: ["uid": String(uid), "roomid": String(roomID), "type": remove ? "0" : "1", "csrf_token": csrf],
            identity: identity, base: Self.piliLiveBase, referer: "https://live.bilibili.com/\(roomID)")
    }
    func piliReportLiveMessage(_ item: DanmakuItem, roomID: Int, reason: String, reasonID: Int, identity: PiliAccountIdentity) async throws {
        guard let meta = item.liveMetadata, meta.canReport, !reason.isEmpty else { throw PiliOfflineError.message("该弹幕没有提供完整举报凭据") }
        let csrf = await requestSnapshot().csrfToken ?? ""
        try await piliContentWrite("/xlive/web-ucenter/v1/dMReport/Report", fields: ["id": "0", "roomid": String(roomID),
            "tuid": String(meta.uid), "msg": item.text, "reason": reason, "ts": meta.timestamp, "sign": meta.signature,
            "reason_id": String(reasonID), "token": "", "dm_type": String(meta.type), "id_str": meta.id, "csrf_token": csrf, "visit_id": ""],
            identity: identity, base: Self.piliLiveBase, referer: "https://live.bilibili.com/\(roomID)")
    }
    func piliLiveRanks(roomID: Int, ownerID: Int, type: String, page: Int) async throws -> [DynamicJSONValue] {
        let scopes = ["online_rank": "contribution_rank", "daily_rank": "today_rank", "weekly_rank": "current_week_rank", "monthly_rank": "current_month_rank"]
        guard let value = scopes[type] else { throw BiliAPIError.missingPayload }
        let data = try await piliContentRead("/xlive/general-interface/v1/rank/queryContributionRank", query: ["ruid": String(ownerID),
            "room_id": String(roomID), "page": String(page), "page_size": "100", "type": type, "switch": value, "platform": "web", "web_location": "444.8"],
            signed: true, base: Self.piliLiveBase, referer: "https://live.bilibili.com/\(roomID)")
        return data["item"].piliArray
    }
    func piliLikeLive(roomID: Int, ownerID: Int, identity: PiliAccountIdentity) async throws {
        let fields = try await signedWBIQuery(["click_time": "1", "room_id": String(roomID), "uid": String(identity.mid), "anchor_id": String(ownerID),
            "web_location": "444.8", "csrf": requestSnapshot(purpose: .interaction).csrfToken ?? ""])
        try await piliContentWrite("/xlive/app-ucenter/v1/like_info_v3/like/likeReportV3", fields: fields, identity: identity, purpose: .interaction,
            base: Self.piliLiveBase, referer: "https://live.bilibili.com/\(roomID)")
    }
}

@MainActor
final class PiliLiveChatStore: ObservableObject {
    @Published private(set) var messages: [DanmakuItem] = []
    @Published private(set) var shield = PiliLiveShield(.null)
    @Published private(set) var error: String?
    @Published private(set) var loading = false
    private var context = ""
    private var task: Task<Void, Never>?
    deinit { task?.cancel() }
    func load(roomID: Int, api: BiliAPIClient, force: Bool = false) {
        let identity = PiliAccountIdentity(api.requestSnapshot()), key = "\(roomID)|\(api.requestSnapshot().playbackCredentialVersion)"
        guard force || context != key else { return }
        if context != key { shield = .init(.null); messages = [] }
        context = key; task?.cancel(); loading = false; error = nil
        guard api.requestSnapshot().isLoggedIn else { return }
        loading = true
        task = Task { [weak self] in
            guard let self else { return }
            defer { if context == key { loading = false } }
            do {
                let value = try await api.piliLiveShield(roomID: roomID, identity: identity)
                guard !Task.isCancelled, context == key else { return }
                shield = value; messages.removeAll { !value.allows($0) }
            } catch { if !Task.isCancelled, context == key { self.error = error.localizedDescription } }
        }
    }
    func accept(_ items: [DanmakuItem], roomID: Int, api: BiliAPIClient) -> [DanmakuItem] {
        load(roomID: roomID, api: api)
        let accepted = items.filter(shield.allows)
        var ids = Set(messages.map(\.id))
        let next = accepted.filter { $0.liveMetadata != nil && ids.insert($0.id).inserted }
        if !next.isEmpty { messages = Array((messages + next).suffix(300)) }
        return accepted
    }
    func stop(clear: Bool) { task?.cancel(); task = nil; loading = false; context = ""; if clear { messages = []; shield = .init(.null) } }
}
