import Foundation

nonisolated struct PiliHistoryTab: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
}

nonisolated struct PiliHistoryRecord: Identifiable, Hashable, Sendable {
    let id: String
    let deletionKey: String?
    let business: String
    let objectID: Int
    let title: String
    let cover: String?
    let author: String
    let viewedAt: Int
    let progress: Int?
    let duration: Int?
    let video: VideoItem?
    let destinationURL: URL?

    init?(_ value: DynamicJSONValue) {
        guard let object = value.objectValueForDynamicParsing,
              let history = object["history"]?.objectValueForDynamicParsing,
              let business = history["business"]?.textValueForDynamicParsing,
              let oid = history["oid"]?.intValueForDynamicParsing, oid > 0 else { return nil }
        self.business = business; objectID = oid
        let kid = object["kid"]?.intValueForDynamicParsing
        deletionKey = kid.flatMap { $0 > 0 ? "\(business)_\($0)" : nil }
        viewedAt = object["view_at"]?.intValueForDynamicParsing ?? 0
        id = deletionKey ?? "\(business)_\(oid)_\(viewedAt)"
        title = object["title"]?.textValueForDynamicParsing ?? "未命名内容"
        author = object["author_name"]?.textValueForDynamicParsing ?? ""
        cover = object["cover"]?.textValueForDynamicParsing?.normalizedBiliURL()
        progress = object["progress"]?.intValueForDynamicParsing
        duration = object["duration"]?.intValueForDynamicParsing
        video = ["archive", "pgc"].contains(business) ? value.accountVideoEntries.first?.videoItem : nil
        let uri = (object["uri"]?.textValueForDynamicParsing).flatMap { AppLinkRouter.normalizedHTTPURLString($0) }
        let fallback: String?
        switch business {
        case "live": fallback = "https://live.bilibili.com/\(oid)"
        case "article": fallback = "https://www.bilibili.com/read/cv\(oid)"
        case "article-list": fallback = "https://www.bilibili.com/read/readlist/rl\(oid)"
        case "pgc": fallback = history["epid"]?.intValueForDynamicParsing.map { "https://www.bilibili.com/bangumi/play/ep\($0)" }
        case "archive": fallback = "https://www.bilibili.com/video/av\(oid)"
        default: fallback = nil
        }
        destinationURL = (uri ?? fallback).flatMap(URL.init(string:))
    }

    var kindTitle: String {
        switch business {
        case "archive": "视频"
        case "pgc": "番剧 / 影视"
        case "live": "直播"
        case "article", "article-list": "专栏"
        default: "浏览记录"
        }
    }
}

nonisolated struct PiliHistoryPage: Sendable {
    let records: [PiliHistoryRecord]
    let tabs: [PiliHistoryTab]
    let cursorMax: Int
    let cursorViewedAt: Int
    let hasMore: Bool
}

nonisolated enum PiliHistoryMutation: Sendable {
    case delete(keys: [String]), clear, pause(Bool)
}

extension BiliAPIClient {
    func fetchPiliHistoryPage(type: String = "all", keyword: String = "", page: Int = 1,
                             max: Int = 0, viewedAt: Int = 0, credentialVersion: Int) async throws -> PiliHistoryPage {
        let context = await requestSnapshot(purpose: .historyRead)
        guard context.isLoggedIn else { throw BiliAPIError.missingSESSDATA }
        guard context.playbackCredentialVersion == credentialVersion else { throw PiliOfflineError.message("账号已切换，请重新加载历史记录") }
        let searching = !keyword.isEmpty
        let query = searching ? ["pn": String(page), "keyword": keyword, "business": "all"]
            : ["type": type, "ps": "20", "max": String(max), "view_at": String(viewedAt)]
        let response: BiliResponse<DynamicJSONValue> = try await get(base: baseURL,
            path: searching ? "/x/web-interface/history/search" : "/x/web-interface/history/cursor",
            query: query, cookieHeader: context.cookieHeader, cachePolicy: .reloadIgnoringLocalCacheData)
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        let object = response.payload?.objectValueForDynamicParsing ?? [:]
        let raw: [DynamicJSONValue]
        if case let .array(values) = object["list"] { raw = values } else { raw = [] }
        let records = raw.compactMap(PiliHistoryRecord.init)
        var tabs = [PiliHistoryTab(id: "all", title: "全部")]
        if case let .array(values) = object["tab"] {
            for value in values {
                guard let item = value.objectValueForDynamicParsing, let id = item["type"]?.textValueForDynamicParsing,
                      !id.isEmpty, !tabs.contains(where: { $0.id == id }) else { continue }
                tabs.append(PiliHistoryTab(id: id, title: item["name"]?.textValueForDynamicParsing ?? id))
            }
        }
        // Advance from the raw final record, even if its content type cannot be rendered yet.
        let last = raw.last?.objectValueForDynamicParsing
        let cursorMax = last?["history"]?.objectValueForDynamicParsing?["oid"]?.intValueForDynamicParsing ?? 0
        let cursorViewedAt = last?["view_at"]?.intValueForDynamicParsing ?? 0
        let hasMore = searching ? !raw.isEmpty : (!raw.isEmpty && cursorViewedAt > 0 && (cursorMax != max || cursorViewedAt != viewedAt))
        return PiliHistoryPage(records: records, tabs: tabs, cursorMax: cursorMax, cursorViewedAt: cursorViewedAt, hasMore: hasMore)
    }

    func fetchPiliHistoryPaused(credentialVersion: Int) async throws -> Bool {
        let context = await requestSnapshot(purpose: .historyRead)
        guard context.isLoggedIn else { throw BiliAPIError.missingSESSDATA }
        guard context.playbackCredentialVersion == credentialVersion else { throw CancellationError() }
        let response: BiliResponse<Bool> = try await get(base: baseURL, path: "/x/v2/history/shadow", query: ["jsonp": "jsonp"],
                                                       cookieHeader: context.cookieHeader, cachePolicy: .reloadIgnoringLocalCacheData)
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let paused = response.payload else { throw BiliAPIError.missingPayload }
        await libraryStore.setPiliCloudHistoryPaused(paused, mid: context.currentUserMID)
        return paused
    }

    func mutatePiliHistory(_ action: PiliHistoryMutation, credentialVersion: Int) async throws {
        let context = await requestSnapshot(purpose: .historyRead)
        guard context.playbackCredentialVersion == credentialVersion else { throw PiliOfflineError.message("账号已切换，请重新加载历史记录") }
        guard context.isLoggedIn else { throw BiliAPIError.missingSESSDATA }
        guard let csrf = context.csrfToken, !csrf.isEmpty else { throw BiliAPIError.missingCSRF }
        var body = ["csrf": csrf, "jsonp": "jsonp"]
        let path: String
        switch action {
        case .delete(let keys):
            let values = Set(keys).sorted()
            guard !values.isEmpty, values.count <= 100,
                  values.allSatisfy({ $0.range(of: #"^[a-zA-Z-]+_[1-9][0-9]*$"#, options: .regularExpression) != nil }) else {
                throw PiliOfflineError.message("每批请选择 1–100 条有效记录")
            }
            path = "/x/v2/history/delete"; body["kid"] = values.joined(separator: ",")
        case .clear: path = "/x/v2/history/clear"
        case .pause(let value): path = "/x/v2/history/shadow/set"; body["switch"] = value ? "true" : "false"
        }
        let response: BiliResponse<DynamicJSONValue> = try await postForm(base: baseURL, path: path, body: body,
            cookieHeader: context.cookieHeader,
            retryPolicy: .init(label: "historyMutation", attempts: 1, baseDelayNanoseconds: 0, maxDelayNanoseconds: 0, jitterNanoseconds: 0))
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        if case let .pause(paused) = action { await libraryStore.setPiliCloudHistoryPaused(paused, mid: context.currentUserMID) }
    }
}
