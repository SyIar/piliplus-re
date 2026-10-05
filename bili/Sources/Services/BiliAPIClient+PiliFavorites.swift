import Foundation

private nonisolated struct PiliFavoriteImageUploadPayload: Decodable, Sendable {
    let imageURL: String?
    enum CodingKeys: String, CodingKey { case imageURL = "image_url" }
}

nonisolated enum PiliFavoriteOrder: String, CaseIterable, Identifiable, Sendable {
    case favoriteTime = "mtime", playCount = "view", publishTime = "pubtime"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .favoriteTime: "最近收藏"
        case .playCount: "最多播放"
        case .publishTime: "最新发布"
        }
    }
}
nonisolated enum PiliFavoriteResourceAction: Sendable {
    case remove, copy(to: Int), move(to: Int)
}
extension FavoriteFolder {
    var isPiliDefault: Bool { attr.map { $0 & 2 == 0 } ?? false }
    var isPiliPublic: Bool { attr.map { $0 & 1 == 0 } ?? true }
}

extension BiliAPIClient {
    func fetchPiliFavoriteFolder(id: Int) async throws -> FavoriteFolder {
        let context = await requestSnapshot(purpose: .interaction)
        let response: BiliResponse<FavoriteFolder> = try await get(base: baseURL, path: "/x/v3/fav/folder/info",
                                                                 query: ["media_id": String(id)], cookieHeader: context.cookieHeader,
                                                                 cachePolicy: .reloadIgnoringLocalCacheData)
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let folder = response.payload else { throw BiliAPIError.missingPayload }
        return folder
    }
    func fetchPiliFavoriteItems(folderID: Int, page: Int, keyword: String = "", order: PiliFavoriteOrder = .favoriteTime) async throws -> AccountVideoEntryPage {
        let context = await requestSnapshot(purpose: .interaction)
        guard context.isLoggedIn else { throw BiliAPIError.missingSESSDATA }
        let response: BiliResponse<DynamicJSONValue> = try await get(
            base: baseURL, path: "/x/v3/fav/resource/list",
            query: ["media_id": String(folderID), "pn": String(page), "ps": "20", "keyword": keyword,
                    "order": order.rawValue, "type": "0", "tid": "0", "platform": "web"],
            cookieHeader: context.cookieHeader, cachePolicy: .reloadIgnoringLocalCacheData)
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        let entries = response.payload?.accountVideoEntries ?? []
        let flag = response.payload?.objectValueForDynamicParsing?["has_more"]
        let hasMore: Bool
        if case let .bool(value) = flag { hasMore = value }
        else if let value = flag?.intValueForDynamicParsing { hasMore = value != 0 }
        else { hasMore = entries.count >= 20 }
        return AccountVideoEntryPage(entries: entries, hasMore: hasMore, nextHistoryCursor: nil)
    }
    func savePiliFavoriteFolder(id: Int?, title: String, intro: String, isPublic: Bool, cover: String, credentialVersion: Int) async throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 20, intro.count <= 200 else { throw PiliOfflineError.message("名称应为 1–20 字，简介不超过 200 字") }
        var fields = ["title": title, "intro": intro, "privacy": isPublic ? "0" : "1", "cover": cover]
        if let id { fields["media_id"] = String(id) }
        try await mutatePiliFavorites(path: id == nil ? "/x/v3/fav/folder/add" : "/x/v3/fav/folder/edit",
                                       fields: fields, credentialVersion: credentialVersion)
    }
    func deletePiliFavoriteFolders(_ folders: [FavoriteFolder], credentialVersion: Int) async throws {
        guard !folders.isEmpty, folders.allSatisfy({ !$0.isPiliDefault && $0.id > 0 }) else {
            throw PiliOfflineError.message("默认收藏夹不能删除")
        }
        try await mutatePiliFavorites(path: "/x/v3/fav/folder/del",
                                       fields: ["media_ids": folders.map { String($0.id) }.joined(separator: ","), "platform": "web"],
                                       credentialVersion: credentialVersion)
    }
    func cleanPiliFavoriteFolder(id: Int, credentialVersion: Int) async throws {
        try await mutatePiliFavorites(path: "/x/v3/fav/resource/clean", fields: ["media_id": String(id), "platform": "web"], credentialVersion: credentialVersion)
    }
    func sortPiliFavoriteFolders(ids: [Int], credentialVersion: Int) async throws {
        guard !ids.isEmpty else { return }
        try await mutatePiliFavorites(path: "/x/v3/fav/folder/sort", fields: ["sort": ids.map(String.init).joined(separator: ",")],
                                       credentialVersion: credentialVersion, signed: true)
    }
    func sortPiliFavoriteItems(folderID: Int, movements: [String], credentialVersion: Int) async throws {
        guard !movements.isEmpty else { return }
        try await mutatePiliFavorites(path: "/x/v3/fav/resource/sort",
                                       fields: ["media_id": String(folderID), "sort": movements.joined(separator: ",")],
                                       credentialVersion: credentialVersion, signed: true)
    }
    func mutatePiliFavoriteItems(folderID: Int, aids: [Int], action: PiliFavoriteResourceAction, credentialVersion: Int) async throws {
        let ids = Set(aids.filter { $0 > 0 }).sorted()
        guard !ids.isEmpty, ids.count <= 100 else { throw PiliOfflineError.message("每批请选择 1–100 个视频") }
        var fields = ["resources": ids.map { "\($0):2" }.joined(separator: ","), "platform": "web"]
        let path: String
        switch action {
        case .remove:
            path = "/x/v3/fav/resource/batch-deal"
            fields["add_media_ids"] = ""; fields["del_media_ids"] = String(folderID)
        case let .copy(target), let .move(target):
            guard target > 0, target != folderID else { throw PiliOfflineError.message("请选择另一个收藏夹") }
            fields["src_media_id"] = String(folderID); fields["tar_media_id"] = String(target)
            if case .copy = action { path = "/x/v3/fav/resource/copy" } else { path = "/x/v3/fav/resource/move" }
            let context = await requestSnapshot(purpose: .interaction)
            if let mid = context.currentUserMID { fields["mid"] = String(mid) }
        }
        try await mutatePiliFavorites(path: path, fields: fields, credentialVersion: credentialVersion)
    }
    func uploadPiliFavoriteCover(_ jpeg: Data, credentialVersion: Int) async throws -> String {
        let context = try await piliFavoriteContext(credentialVersion)
        guard !jpeg.isEmpty, jpeg.count <= 10 * 1024 * 1024 else { throw PiliOfflineError.message("图片不能超过 10 MB") }
        let response: BiliResponse<PiliFavoriteImageUploadPayload> = try await postMultipart(
            base: baseURL, path: "/x/dynamic/feed/draw/upload_bfs", fields: ["biz": "new_dyn", "category": "daily", "csrf": context.csrfToken!],
            fileField: "file_up", fileName: "cover.jpg", mimeType: "image/jpeg", fileData: jpeg,
            cookieHeader: context.cookieHeader, retryPolicy: .init(label: "favoriteCover", attempts: 1, baseDelayNanoseconds: 0, maxDelayNanoseconds: 0, jitterNanoseconds: 0))
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let url = response.payload?.imageURL, !url.isEmpty else { throw BiliAPIError.missingPayload }
        return url
    }
    private func piliFavoriteContext(_ credentialVersion: Int) async throws -> RequestSnapshot {
        let context = await requestSnapshot(purpose: .interaction)
        guard context.playbackCredentialVersion == credentialVersion else { throw PiliOfflineError.message("账号已切换，请重新打开收藏管理") }
        guard context.isLoggedIn else { throw BiliAPIError.missingSESSDATA }
        guard let csrf = context.csrfToken, !csrf.isEmpty else { throw BiliAPIError.missingCSRF }
        return context
    }
    private func mutatePiliFavorites(path: String, fields: [String: String], credentialVersion: Int, signed: Bool = false) async throws {
        let context = try await piliFavoriteContext(credentialVersion)
        var body = fields; body["csrf"] = context.csrfToken!
        if signed { body = BiliAppSigner.sign(body) }
        let response: BiliResponse<DynamicJSONValue> = try await postForm(
            base: baseURL, path: path, body: body, cookieHeader: context.cookieHeader,
            retryPolicy: .init(label: "favoriteMutation", attempts: 1, baseDelayNanoseconds: 0, maxDelayNanoseconds: 0, jitterNanoseconds: 0))
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
    }
}
