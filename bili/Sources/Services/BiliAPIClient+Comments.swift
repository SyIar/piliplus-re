import Foundation

nonisolated struct DynamicCommentImage: Encodable, Equatable, Sendable {
    let imageURL: String
    let width: Int
    let height: Int
    let size: Int

    enum CodingKeys: String, CodingKey {
        case imageURL = "img_src"
        case width = "img_width"
        case height = "img_height"
        case size = "img_size"
    }
}

private nonisolated struct DynamicCommentImageUploadPayload: Decodable, Sendable {
    let imageURL: String?
    let width: Int?
    let height: Int?
    let size: Int?

    enum CodingKeys: String, CodingKey {
        case imageURL = "image_url"
        case width = "image_width"
        case height = "image_height"
        case size = "img_size"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
        width = container.decodeLossyIntIfPresent(forKey: .width)
        height = container.decodeLossyIntIfPresent(forKey: .height)
        size = container.decodeLossyDoubleIfPresent(forKey: .size).map(Int.init)
    }
}

private nonisolated struct CommentEmotePanelPayload: Decodable, Sendable {
    let packages: [CommentEmotePackage]?
}

private nonisolated struct CommentEmotePackage: Decodable, Sendable {
    let emotes: [DynamicCommentPanelEmote]?

    enum CodingKeys: String, CodingKey {
        case emotes = "emote"
    }
}

private nonisolated struct DynamicCommentPanelEmote: Decodable, Sendable {
    let text: String?
    let url: String?
    let width: Double?
    let height: Double?
}

extension BiliAPIClient {
    func addDynamicComment(
        oid: String,
        type: Int,
        message: String,
        root: Int? = nil,
        parent: Int? = nil,
        pictures: [DynamicCommentImage]? = nil
    ) async throws {
        let normalizedOID = oid.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedOID.isEmpty,
              type > 0,
              !normalizedMessage.isEmpty,
              root.map({ $0 > 0 }) ?? true,
              parent.map({ $0 > 0 }) ?? true,
              (root == nil) == (parent == nil)
        else {
            throw BiliAPIError.missingPayload
        }
        let snapshot = requestSnapshot(purpose: .interaction)
        if let scope = PiliCommentSubmissionScope.current, !scope.identity.matches(snapshot) { throw PiliOfflineError.message("互动账号已切换") }
        let interactionContext = snapshot
        guard interactionContext.isLoggedIn else { throw BiliAPIError.missingSESSDATA }
        guard let csrf = interactionContext.csrfToken, !csrf.isEmpty else {
            throw BiliAPIError.missingCSRF
        }
        var body = [
            "oid": normalizedOID,
            "type": String(type),
            "message": normalizedMessage,
            "plat": "1",
            "csrf": csrf,
        ]
        if let mentions = PiliCommentSubmissionScope.current?.mentions, !mentions.isEmpty {
            body["at_name_to_mid"] = String(decoding: try JSONEncoder().encode(mentions), as: UTF8.self)
        }
        if let root, let parent {
            body["root"] = String(root)
            body["parent"] = String(parent)
        }
        if let pictures, !pictures.isEmpty {
            body["pictures"] = String(
                decoding: try JSONEncoder().encode(pictures),
                as: UTF8.self
            )
        }
        let response: BiliResponse<DynamicJSONValue> = try await postForm(
            base: baseURL,
            path: "/x/v2/reply/add",
            body: body,
            referer: "https://t.bilibili.com/",
            cookieHeader: interactionContext.cookieHeader,
            retryPolicy: Self.piliSingleWrite
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        let id = max(response.payload?["rpid"].piliInt ?? 0, response.payload?["reply"]["rpid"].piliInt ?? 0)
        if id > 0 {
            // A local disk failure must never turn a successful server submission
            // into a retry that posts the same comment a second time.
            let recordsComments = await MainActor.run { UserDefaults.standard.object(forKey: "piliplus.comments.record") as? Bool ?? true }
            if recordsComments {
                try? await PiliCommentArchive.shared.record(.init(account: snapshot.currentUserMID ?? 0, id: id,
                    oid: normalizedOID, type: type, root: root ?? 0, parent: parent ?? 0, message: normalizedMessage,
                    pictures: pictures?.map(\.imageURL) ?? [], created: Int(Date().timeIntervalSince1970)))
            }
            await PiliVisibilityCheckCenter.shared.schedule(.comment(oid: oid, type: type, id: id, root: root ?? 0),
                api: self, identity: PiliAccountIdentity(snapshot))
        }
    }

    func uploadDynamicCommentImage(_ imageData: Data) async throws -> DynamicCommentImage {
        let snapshot = requestSnapshot(purpose: .interaction)
        if let scope = PiliCommentSubmissionScope.current, !scope.identity.matches(snapshot) { throw PiliOfflineError.message("互动账号已切换") }
        guard snapshot.isLoggedIn, let csrf = snapshot.csrfToken else { throw BiliAPIError.missingCSRF }
        let response: BiliResponse<DynamicCommentImageUploadPayload> = try await postMultipart(
            base: baseURL,
            path: "/x/dynamic/feed/draw/upload_bfs",
            fields: [
                "biz": "new_dyn",
                "category": "daily",
                "csrf": csrf
            ],
            fileField: "file_up",
            fileName: "comment.jpg",
            mimeType: "image/jpeg",
            fileData: imageData,
            referer: "https://t.bilibili.com/", cookieHeader: snapshot.cookieHeader, retryPolicy: Self.piliSingleWrite
        )
        guard response.code == 0,
              let payload = response.payload,
              let imageURL = payload.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !imageURL.isEmpty,
              let width = payload.width,
              let height = payload.height
        else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        return DynamicCommentImage(
            imageURL: imageURL.normalizedBiliURL(),
            width: width,
            height: height,
            size: payload.size ?? imageData.count
        )
    }

    func fetchCommentEmotes() async throws -> [BiliInlineEmote] {
        let response: BiliResponse<CommentEmotePanelPayload> = try await get(
            base: baseURL,
            path: "/x/emote/user/panel/web",
            query: [
                "business": "reply",
                "web_location": "333.1245"
            ],
            referer: "https://www.bilibili.com/"
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        return (response.payload?.packages ?? [])
            .flatMap { $0.emotes ?? [] }
            .compactMap { emote in
                guard let text = emote.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty,
                      let url = emote.url?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !url.isEmpty
                else { return nil }
                return BiliInlineEmote(
                    token: text,
                    url: url,
                    width: emote.width,
                    height: emote.height
                )
            }
    }

    func setCommentLike(
        oid: String,
        type: Int,
        rpid: Int,
        liked: Bool,
        referer: String = "https://www.bilibili.com"
    ) async throws {
        let normalizedOID = oid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedOID.isEmpty, type > 0, rpid > 0 else {
            throw BiliAPIError.missingPayload
        }
        let context = await interactionRequestContext()
        guard context.isLoggedIn else { throw BiliAPIError.missingSESSDATA }
        guard let csrf = context.csrfToken, !csrf.isEmpty else { throw BiliAPIError.missingCSRF }
        let response: BiliResponse<EmptyBiliPayload> = try await postForm(
            base: baseURL,
            path: "/x/v2/reply/action",
            body: [
                "oid": normalizedOID,
                "type": String(type),
                "rpid": String(rpid),
                "action": liked ? "1" : "0",
                "csrf": csrf,
            ],
            referer: referer,
            cookieHeader: context.cookieHeader,
            retryPolicy: .idempotentMutation
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
    }

    func fetchComments(
        aid: Int,
        cursor: String = "",
        sort: CommentSort = .hot,
        cookieHeader: String? = nil
    ) async throws -> CommentPage {
        try await fetchComments(
            oid: String(aid),
            type: 1,
            cursor: cursor,
            sort: sort,
            cookieHeader: cookieHeader
        )
    }

    func fetchComments(
        oid: String,
        type: Int,
        cursor: String = "",
        sort: CommentSort = .hot,
        cookieHeader: String? = nil
    ) async throws
        -> CommentPage
    {
        let mode = sort == .hot ? "3" : "2"
        let pagination = try Self.commentPaginationString(offset: cursor)
        let revision = commentReadRevision
        let resolvedCookieHeader = await resolvedCommentCookieHeader(cookieHeader)
        let response: BiliResponse<CommentPage> = try await get(
            base: baseURL,
            path: "/x/v2/reply/main",
            query: [
                "oid": oid,
                "type": String(type),
                "mode": mode,
                "plat": "1",
                "pagination_str": pagination,
            ],
            cookieHeader: resolvedCookieHeader,
            cachePolicy: .reloadIgnoringLocalCacheData,
            priority: URLSessionTask.defaultPriority
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        let page = response.payload ?? CommentPage(replies: [], topReplies: [], cursor: nil)
        return try commentPageForCurrentWriter(page, usesDefaultReader: cookieHeader == nil, revision: revision)
    }

    private static func commentPaginationString(offset: String) throws -> String {
        let data = try JSONEncoder().encode(CommentPaginationRequest(offset: offset))
        return String(decoding: data, as: UTF8.self)
    }

    func fetchCommentReplies(
        aid: Int,
        root: Int,
        page: Int = 1,
        sort: CommentSort? = nil,
        cookieHeader: String? = nil
    ) async throws -> CommentPage {
        try await fetchCommentReplies(
            oid: String(aid),
            type: 1,
            root: root,
            page: page,
            sort: sort,
            cookieHeader: cookieHeader
        )
    }

    func fetchCommentReplies(
        oid: String,
        type: Int,
        root: Int,
        page: Int = 1,
        sort: CommentSort? = nil,
        cookieHeader: String? = nil
    ) async throws -> CommentPage {
        var query = [
            "oid": oid,
            "type": String(type),
            "root": String(root),
            "pn": String(page),
            "ps": "20",
        ]
        if sort == .time {
            query["sort"] = "1"
        }
        let revision = commentReadRevision
        let resolvedCookieHeader = await resolvedCommentCookieHeader(cookieHeader)
        let response: BiliResponse<CommentPage> = try await get(
            base: baseURL,
            path: "/x/v2/reply/reply",
            query: query,
            cookieHeader: resolvedCookieHeader,
            cachePolicy: .reloadIgnoringLocalCacheData,
            priority: URLSessionTask.lowPriority
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        let page = response.payload ?? CommentPage(replies: [], topReplies: [], cursor: nil)
        return try commentPageForCurrentWriter(page, usesDefaultReader: cookieHeader == nil, revision: revision)
    }

    func fetchCommentDialog(
        aid: Int,
        root: Int,
        dialog: Int,
        size: Int = 20,
        cookieHeader: String? = nil
    ) async throws -> CommentPage {
        try await fetchCommentDialog(
            oid: String(aid),
            type: 1,
            root: root,
            dialog: dialog,
            size: size,
            cookieHeader: cookieHeader
        )
    }

    func fetchCommentDialog(
        oid: String,
        type: Int,
        root: Int,
        dialog: Int,
        size: Int = 20,
        cookieHeader: String? = nil
    ) async throws -> CommentPage
    {
        let revision = commentReadRevision
        let resolvedCookieHeader = await resolvedCommentCookieHeader(cookieHeader)
        let response: BiliResponse<CommentPage> = try await get(
            base: baseURL,
            path: "/x/v2/reply/dialog/cursor",
            query: [
                "oid": oid,
                "type": String(type),
                "root": String(root),
                "dialog": String(dialog),
                "size": String(size),
            ],
            cookieHeader: resolvedCookieHeader,
            cachePolicy: .reloadIgnoringLocalCacheData,
            priority: URLSessionTask.lowPriority
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        let page = response.payload ?? CommentPage(replies: [], topReplies: [], cursor: nil)
        return try commentPageForCurrentWriter(page, usesDefaultReader: cookieHeader == nil, revision: revision)
    }

    private func resolvedCommentCookieHeader(_ cookieHeader: String?) async -> String {
        if let cookieHeader {
            return cookieHeader
        }
        return requestSnapshot(purpose: .commentRead).cookieHeader
    }
}

nonisolated enum CommentSort: String, CaseIterable, Identifiable, Hashable {
    case hot
    case time

    var id: Self { self }

    var title: String {
        switch self {
        case .hot:
            return "最热"
        case .time:
            return "最新"
        }
    }
}

nonisolated private struct CommentPaginationRequest: Encodable {
    let offset: String
}
