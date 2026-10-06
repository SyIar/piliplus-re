import Foundation

extension BiliAPIClient {
    func fetchPiliNotes(page: Int, published: Bool, videoAID: Int? = nil) async throws -> [PiliNoteRecord] {
        let context = await interactionRequestContext(purpose: .main)
        var query = ["pn": String(max(1, page)), "ps": "10"]
        if let csrf = context.csrfToken { query["csrf"] = csrf }
        let path: String
        if let videoAID {
            path = "/x/note/publish/list/archive"; query["oid"] = String(videoAID); query["oid_type"] = "0"
        } else {
            guard context.isLoggedIn else { throw BiliAPIError.missingSESSDATA }
            path = published ? "/x/note/publish/list/user" : "/x/note/list"
        }
        let response: BiliResponse<DynamicJSONValue> = try await get(base: baseURL, path: path, query: query, cookieHeader: context.cookieHeader)
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard case let .object(object) = response.payload, case let .array(list) = object["list"] else { return [] }
        return list.compactMap(PiliNoteRecord.init)
    }
    func fetchPiliNote(_ record: PiliNoteRecord, published: Bool) async throws -> PiliNoteDetail {
        let context = await interactionRequestContext(purpose: .main)
        let query: [String: String]
        let path: String
        if published, let articleID = record.articleID {
            path = "/x/note/publish/info"; query = ["cvid": articleID]
        } else {
            guard context.isLoggedIn, let aid = record.aid, let noteID = record.noteID else { throw BiliAPIError.missingPayload }
            path = "/x/note/info"; query = ["oid": String(aid), "oid_type": "0", "note_id": noteID]
        }
        let response: BiliResponse<DynamicJSONValue> = try await get(base: baseURL, path: path, query: query, cookieHeader: context.cookieHeader)
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard case let .object(object) = response.payload else { throw BiliAPIError.missingPayload }
        return PiliNoteDetail(object)
    }
    func savePiliNote(aid: Int, noteID: String?, title: String, text: String, published: Bool,
                      credentialVersion: Int) async throws -> String {
        let context = requestSnapshot(purpose: .main)
        guard context.playbackCredentialVersion == credentialVersion else { throw PiliOfflineError.message("账号已切换，请重新打开笔记") }
        guard context.isLoggedIn else { throw BiliAPIError.missingSESSDATA }
        guard let csrf = context.csrfToken, !csrf.isEmpty else { throw BiliAPIError.missingCSRF }
        guard aid > 0, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PiliOfflineError.message("请填写标题和内容") }
        let operations: [[String: String]] = [["insert": text.hasSuffix("\n") ? text : text + "\n"]]
        let content = String(decoding: try JSONEncoder().encode(operations), as: UTF8.self)
        var body = ["oid": String(aid), "oid_type": "0", "title": title,
                    "summary": String(text.prefix(200)), "content": content, "cls": "1", "from": "save",
                    "platform": "web", "publish": published ? "1" : "0", "auto_comment": "0", "csrf": csrf]
        if let noteID { body["note_id"] = noteID }
        let response: BiliResponse<DynamicJSONValue> = try await postForm(
            base: baseURL, path: "/x/note/add", body: body, cookieHeader: context.cookieHeader,
            retryPolicy: BiliNetworkRetryPolicy(label: "noteSave", attempts: 1, baseDelayNanoseconds: 0, maxDelayNanoseconds: 0, jitterNanoseconds: 0)
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let id = response.payload?.objectValueForDynamicParsing?["note_id"]?.textValue ?? noteID else { throw BiliAPIError.missingPayload }
        return id
    }
    func deletePiliNotes(_ records: [PiliNoteRecord], published: Bool, credentialVersion: Int) async throws {
        let context = requestSnapshot(purpose: .main)
        guard context.playbackCredentialVersion == credentialVersion else { throw PiliOfflineError.message("账号已切换，请重新加载笔记") }
        guard context.isLoggedIn else { throw BiliAPIError.missingSESSDATA }
        guard let csrf = context.csrfToken, !csrf.isEmpty else { throw BiliAPIError.missingCSRF }
        let ids = records.compactMap { published ? $0.articleID : $0.noteID }
        guard !ids.isEmpty else { throw BiliAPIError.missingPayload }
        let response: BiliResponse<DynamicJSONValue> = try await postForm(
            base: baseURL, path: published ? "/x/note/publish/del" : "/x/note/del",
            body: [published ? "cvids" : "note_ids": ids.joined(separator: ","), "csrf": csrf], cookieHeader: context.cookieHeader,
            retryPolicy: BiliNetworkRetryPolicy(label: "noteDelete", attempts: 1, baseDelayNanoseconds: 0, maxDelayNanoseconds: 0, jitterNanoseconds: 0)
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
    }
}
