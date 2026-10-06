import Foundation

nonisolated enum PiliRelationList: String, CaseIterable, Identifiable, Sendable {
    case following, fans, blocked
    var id: Self { self }
    var title: String {
        switch self { case .following: "关注"; case .fans: "粉丝"; case .blocked: "黑名单" }
    }
}

nonisolated struct PiliFollowGroup: Identifiable, Hashable, Sendable {
    let id: Int
    var name: String
    let count: Int
    var isCustom: Bool { id > 0 }
    init?(_ value: DynamicJSONValue) {
        guard let object = value.objectValueForDynamicParsing, let id = object["tagid"]?.intValueForDynamicParsing else { return nil }
        self.id = id
        name = object["name"]?.textValueForDynamicParsing ?? "分组 \(id)"
        count = object["count"]?.intValueForDynamicParsing ?? 0
    }
}

nonisolated struct PiliRelationUser: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let face: String?
    let sign: String
    let attribute: Int
    let special: Bool
    var isFollowing: Bool { attribute == 2 || attribute == 6 }
    var owner: VideoOwner { VideoOwner(mid: id, name: name, face: face) }
    init?(_ value: DynamicJSONValue) {
        guard let object = value.objectValueForDynamicParsing, let id = object["mid"]?.intValueForDynamicParsing, id > 0 else { return nil }
        self.id = id
        name = object["uname"]?.textValueForDynamicParsing ?? "UID \(id)"
        face = object["face"]?.textValueForDynamicParsing?.normalizedBiliURL()
        sign = object["sign"]?.textValueForDynamicParsing ?? ""
        attribute = object["attribute"]?.intValueForDynamicParsing ?? 0
        special = object["special"]?.intValueForDynamicParsing == 1
    }
}

nonisolated struct PiliRelationPage: Sendable {
    let users: [PiliRelationUser]
    let total: Int?
    let hasMore: Bool
}

nonisolated enum PiliRelationMutation: Sendable {
    case follow(Int), unfollow(Int), block(Int), unblock(Int), removeFan(Int)
    case special(Int, Bool)
    case setGroups(mid: Int, ids: [Int])
    case createGroup(String), renameGroup(Int, String), deleteGroup(Int), sortGroups([Int])
}

extension BiliAPIClient {
    func fetchPiliFollowGroups(identity: PiliAccountIdentity) async throws -> [PiliFollowGroup] {
        let context = await requestSnapshot(purpose: .main)
        guard identity.matches(context) else { throw PiliOfflineError.message("账号已切换，请重新打开关注管理") }
        let response: BiliResponse<DynamicJSONValue> = try await get(base: baseURL, path: "/x/relation/tags", query: [:],
            cookieHeader: context.cookieHeader, cachePolicy: .reloadIgnoringLocalCacheData)
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard case .array(let values) = response.payload else { throw BiliAPIError.missingPayload }
        var seen = Set<Int>()
        return values.compactMap(PiliFollowGroup.init).filter { seen.insert($0.id).inserted }
    }

    func fetchPiliRelationGroups(mid: Int, identity: PiliAccountIdentity) async throws -> Set<Int> {
        let context = await requestSnapshot(purpose: .main)
        guard identity.matches(context), mid > 0 else { throw PiliOfflineError.message("账号已切换，请重新打开关注管理") }
        let response: BiliResponse<DynamicJSONValue> = try await get(base: baseURL, path: "/x/relation", query: ["fid": String(mid)],
            cookieHeader: context.cookieHeader, cachePolicy: .reloadIgnoringLocalCacheData)
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let object = response.payload?.objectValueForDynamicParsing else { throw BiliAPIError.missingPayload }
        var ids = Set<Int>()
        if case .array(let values) = object["tag"] { ids = Set(values.compactMap(\.intValueForDynamicParsing)) }
        if object["special"]?.intValueForDynamicParsing == 1 { ids.insert(-10) }
        ids.remove(0)
        return ids
    }

    func fetchPiliRelations(kind: PiliRelationList, ownerMID: Int, page: Int, group: Int?, frequent: Bool,
                           keyword: String, identity: PiliAccountIdentity) async throws -> PiliRelationPage {
        let context = await requestSnapshot(purpose: .main)
        guard ownerMID > 0, page > 0, identity.mid == (context.currentUserMID ?? 0), identity.version == context.playbackCredentialVersion else {
            throw PiliOfflineError.message("账号已切换，请重新打开关注管理")
        }
        if kind == .blocked || group != nil {
            guard identity.matches(context), ownerMID == identity.mid else { throw BiliAPIError.missingSESSDATA }
        }
        let pageSize = kind == .blocked ? 50 : 20
        var query = ["vmid": String(ownerMID), "pn": String(page), "ps": String(pageSize), "order": "desc", "order_type": frequent ? "attention" : ""]
        let path: String
        if kind == .blocked {
            path = "/x/relation/blacks"
            query = ["pn": String(page), "ps": String(pageSize), "re_version": "0", "jsonp": "jsonp", "csrf": context.csrfToken ?? ""]
        } else if kind == .fans {
            path = "/x/relation/fans"; query["order_type"] = "attention"
        } else if !keyword.isEmpty {
            path = "/x/relation/followings/search"
            query["name"] = keyword; query["order_type"] = "attention"; query["gaia_source"] = "main_web"; query["web_location"] = "333.999"
            query = try await signedWBIQuery(query)
        } else if let group {
            path = "/x/relation/tag"
            query.removeValue(forKey: "vmid"); query.removeValue(forKey: "order")
            query["mid"] = String(ownerMID); query["tagid"] = String(group)
        } else { path = "/x/relation/followings" }
        let response: BiliResponse<DynamicJSONValue> = try await get(base: baseURL, path: path, query: query,
            cookieHeader: context.cookieHeader, cachePolicy: .reloadIgnoringLocalCacheData)
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let data = response.payload else { throw BiliAPIError.missingPayload }
        let values: [DynamicJSONValue]
        let total: Int?
        if case .array(let array) = data { values = array; total = nil }
        else if let object = data.objectValueForDynamicParsing {
            if case .array(let array) = object["list"] { values = array } else { values = [] }
            total = object["total"]?.intValueForDynamicParsing
        } else { throw BiliAPIError.missingPayload }
        return PiliRelationPage(users: values.compactMap(PiliRelationUser.init), total: total,
                                hasMore: !values.isEmpty && (total.map { page * pageSize < $0 } ?? (values.count >= pageSize)))
    }

    @discardableResult
    func mutatePiliRelation(_ action: PiliRelationMutation, identity: PiliAccountIdentity) async throws -> Int? {
        let context = await requestSnapshot(purpose: .main)
        guard identity.matches(context) else { throw PiliOfflineError.message("账号已切换，请重新打开关注管理") }
        guard let csrf = context.csrfToken, !csrf.isEmpty else { throw BiliAPIError.missingCSRF }
        var body = ["csrf": csrf]
        var query = ["x-bili-device-req-json": #"{"platform":"web","device":"pc","spmid":"333.1387"}"#]
        var headers: [String: String] = [:]
        var referer = "https://space.bilibili.com"
        let path: String
        func validMID(_ mid: Int) throws {
            guard mid > 0, mid != identity.mid else { throw PiliOfflineError.message("不能对自己执行此操作") }
        }
        func validGroup(_ id: Int) throws {
            guard id > 0 else { throw PiliOfflineError.message("默认分组不能修改、删除或排序") }
        }
        func validName(_ name: String) throws -> String {
            let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count <= 16 else { throw PiliOfflineError.message("分组名称需为 1–16 个字") }
            return value
        }
        switch action {
        case .follow(let mid), .unfollow(let mid), .block(let mid), .unblock(let mid), .removeFan(let mid):
            try validMID(mid)
            let act: Int
            switch action { case .follow: act = 1; case .unfollow: act = 2; case .block: act = 5; case .unblock: act = 6; default: act = 7 }
            path = "/x/relation/modify"
            body.merge(["fid": String(mid), "act": String(act), "re_src": "11", "gaia_source": "web_main", "spmid": "333.1387"], uniquingKeysWith: { _, new in new })
            let content: [String: Any] = ["entity": "user", "entity_id": mid, "fp": Self.webUserAgent]
            body["extend_content"] = String(decoding: try JSONSerialization.data(withJSONObject: content), as: UTF8.self)
            query["statistics"] = #"{"appId":100,"platform":5}"#
            headers["Origin"] = "https://space.bilibili.com"; referer += "/\(mid)/dynamic"
        case .special(let mid, let enabled):
            try validMID(mid); path = "/x/relation/tag/special/\(enabled ? "add" : "del")"; body["fid"] = String(mid)
        case .setGroups(let mid, let ids):
            try validMID(mid); path = "/x/relation/tags/addUsers"
            let selected = Set(ids).subtracting([0]).sorted()
            body["fids"] = String(mid); body["tagids"] = selected.isEmpty ? "0" : selected.map(String.init).joined(separator: ",")
        case .createGroup(let name):
            path = "/x/relation/tag/create"; body["tag"] = try validName(name)
        case .renameGroup(let id, let name):
            try validGroup(id); path = "/x/relation/tag/update"; body["tagid"] = String(id); body["name"] = try validName(name)
        case .deleteGroup(let id):
            try validGroup(id); path = "/x/relation/tag/del"; body["tagid"] = String(id)
        case .sortGroups(let ids):
            guard !ids.isEmpty, Set(ids).count == ids.count else { throw BiliAPIError.missingPayload }
            try ids.forEach(validGroup)
            path = "/x/relation/tags/update_sort"; body["tagids"] = ids.map(String.init).joined(separator: ",")
        }
        let response: BiliResponse<DynamicJSONValue> = try await postForm(base: baseURL, path: path, query: query, body: body,
            referer: referer, userAgent: Self.webUserAgent, cookieHeader: context.cookieHeader, additionalHeaders: headers,
            retryPolicy: .init(label: "relationMutation", attempts: 1, baseDelayNanoseconds: 0, maxDelayNanoseconds: 0, jitterNanoseconds: 0))
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard identity.matches(requestSnapshot()) else { throw PiliOfflineError.message("账号已切换") }
        switch action {
        case .block(let mid): PiliBlacklistedCreators.shared.didChange(mid: mid, blocked: true, account: identity)
        case .unblock(let mid): PiliBlacklistedCreators.shared.didChange(mid: mid, blocked: false, account: identity)
        default: break
        }
        return response.payload?.objectValueForDynamicParsing?["tagid"]?.intValueForDynamicParsing
    }
}
