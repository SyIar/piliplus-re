import Foundation

nonisolated struct PiliWatchLaterFilter: Hashable, Sendable {
    var unfinished = false
    var ascending = false
    var keyword = ""
}

extension BiliAPIClient {
    func fetchPiliWatchLaterPage(page: Int, filter: PiliWatchLaterFilter) async throws -> AccountVideoEntryPage {
        let context = await requestSnapshot(purpose: .historyRead)
        guard context.isLoggedIn else { throw BiliAPIError.missingSESSDATA }
        let query = try await signedWBIQuery([
            "pn": String(page), "ps": "20", "viewed": filter.unfinished ? "2" : "0",
            "key": filter.keyword, "asc": filter.ascending ? "true" : "false", "need_split": "true", "web_location": "333.881"
        ])
        let response: BiliResponse<DynamicJSONValue> = try await get(base: baseURL, path: "/x/v2/history/toview/web",
                                                                  query: query, cookieHeader: context.cookieHeader,
                                                                  cachePolicy: .reloadIgnoringLocalCacheData)
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        let entries = response.payload?.accountVideoEntries ?? []
        let count = response.payload?.objectValueForDynamicParsing?["count"]?.intValueForDynamicParsing
        return AccountVideoEntryPage(entries: entries, hasMore: count.map { page * 20 < $0 } ?? (entries.count >= 20), nextHistoryCursor: nil)
    }
    func fetchPiliFavoriteDestinations(purpose: BiliAccountPurpose) async throws -> [FavoriteFolder] {
        let context = await requestSnapshot(purpose: purpose)
        guard context.isLoggedIn, let mid = context.currentUserMID else { throw BiliAPIError.missingSESSDATA }
        let response: BiliResponse<FavoriteFolderListData> = try await get(base: baseURL, path: "/x/v3/fav/folder/created/list-all",
                                                                        query: ["up_mid": String(mid), "type": "2"],
                                                                        cookieHeader: context.cookieHeader, cachePolicy: .reloadIgnoringLocalCacheData)
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload?.list?.filter { $0.id > 0 } ?? []
    }
    func mutatePiliWatchLater(aids: [Int], targetFolder: Int? = nil, move: Bool = false, credentialVersion: Int) async throws {
        let context = await requestSnapshot(purpose: .historyRead)
        guard context.playbackCredentialVersion == credentialVersion else { throw PiliOfflineError.message("账号已切换，请重新打开稍后再看") }
        guard context.isLoggedIn else { throw BiliAPIError.missingSESSDATA }
        guard let csrf = context.csrfToken, !csrf.isEmpty else { throw BiliAPIError.missingCSRF }
        let ids = Set(aids.filter { $0 > 0 }).sorted()
        guard !ids.isEmpty, ids.count <= 100 else { throw PiliOfflineError.message("每批请选择 1–100 个视频") }
        var body = ["csrf": csrf, "platform": "web"]
        let path: String
        if let targetFolder {
            guard targetFolder > 0 else { throw BiliAPIError.missingPayload }
            path = move ? "/x/v2/history/toview/move" : "/x/v2/history/toview/copy"
            body["tar_media_id"] = String(targetFolder)
            // Toview endpoints take bare AV IDs; only favorite-resource endpoints use aid:type.
            body["resources"] = ids.map(String.init).joined(separator: ",")
            if !move, let mid = context.currentUserMID { body["mid"] = String(mid) }
        } else {
            path = "/x/v2/history/toview/v2/dels"
            body["resources"] = ids.map(String.init).joined(separator: ",")
        }
        let response: BiliResponse<DynamicJSONValue> = try await postForm(base: baseURL, path: path, body: body, cookieHeader: context.cookieHeader,
            retryPolicy: .init(label: "watchLaterBatch", attempts: 1, baseDelayNanoseconds: 0, maxDelayNanoseconds: 0, jitterNanoseconds: 0))
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
    }
}
