import Foundation

/// A typed JSON body: numeric fields must be JSON numbers, not the display
/// strings used by DynamicJSONValue's compatibility encoder.
nonisolated enum PiliJSON: Encodable, Sendable {
    case string(String), int(Int), decimal(Double), bool(Bool), array([PiliJSON]), object([String: PiliJSON]), null
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .decimal(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

extension DynamicJSONValue {
    nonisolated subscript(_ key: String) -> DynamicJSONValue { objectValueForDynamicParsing?[key] ?? .null }
    nonisolated var piliString: String { textValueForDynamicParsing ?? "" }
    nonisolated var piliInt: Int { intValueForDynamicParsing ?? 0 }
    nonisolated var piliArray: [DynamicJSONValue] { if case .array(let values) = self { return values }; return [] }
    nonisolated var piliObject: [String: DynamicJSONValue] { objectValueForDynamicParsing ?? [:] }
    nonisolated var piliJSON: PiliJSON {
        switch self {
        case .string(let v): .string(v)
        case .number(let v): Int(v).map(PiliJSON.int) ?? Double(v).map(PiliJSON.decimal) ?? .null
        case .bool(let v): .bool(v)
        case .array(let v): .array(v.map(\.piliJSON))
        case .object(let v): .object(v.mapValues(\.piliJSON))
        case .null: .null
        }
    }
    nonisolated func piliDecode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(piliJSON))
    }
}

extension BiliAPIClient {
    nonisolated static let piliSingleWrite = BiliNetworkRetryPolicy(
        label: "contentMutation", attempts: 1, baseDelayNanoseconds: 0, maxDelayNanoseconds: 0, jitterNanoseconds: 0)

    func piliContentRead(_ path: String, query: [String: String] = [:], signed: Bool = false,
                         purpose: BiliAccountPurpose = .main, identity: PiliAccountIdentity? = nil,
                         base: URL? = nil, referer: String = "https://www.bilibili.com/") async throws -> DynamicJSONValue {
        let context = await requestSnapshot(purpose: purpose)
        if let identity, !identity.matches(context) { throw PiliOfflineError.message("账号已切换，请重新打开页面") }
        let parameters = signed ? try await signedWBIQuery(query) : query
        let response: BiliResponse<DynamicJSONValue> = try await get(
            base: base ?? baseURL, path: path, query: parameters, referer: referer,
            cookieHeader: context.isLoggedIn ? context.cookieHeader : context.anonymousCookieHeader,
            cachePolicy: .reloadIgnoringLocalCacheData)
        if let identity, !(await identity.matches(requestSnapshot(purpose: purpose))) {
            throw PiliOfflineError.message("账号已切换，请重新打开页面")
        }
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload ?? .null
    }

    @discardableResult
    func piliContentWrite(_ path: String, body: PiliJSON? = nil, fields: [String: String]? = nil,
                          query: [String: String] = [:], signed: Bool = false,
                          identity: PiliAccountIdentity, purpose: BiliAccountPurpose = .main,
                          base: URL? = nil, referer: String = "https://www.bilibili.com/") async throws -> DynamicJSONValue {
        let context = await requestSnapshot(purpose: purpose)
        guard identity.matches(context) else { throw PiliOfflineError.message("账号已切换，请重新打开页面") }
        guard let csrf = context.csrfToken, !csrf.isEmpty else { throw BiliAPIError.missingCSRF }
        var parameters = query; parameters["csrf"] = csrf
        if signed { parameters = try await signedWBIQuery(parameters) }
        try Task.checkCancellation()
        guard await identity.matches(requestSnapshot(purpose: purpose)) else { throw PiliOfflineError.message("账号已切换") }
        let response: BiliResponse<DynamicJSONValue>
        if var fields {
            fields["csrf"] = csrf
            response = try await postForm(base: base ?? baseURL, path: path, query: parameters,
                body: fields, referer: referer, cookieHeader: context.cookieHeader, retryPolicy: Self.piliSingleWrite)
        } else {
            var request = try await makeRequest(base: base ?? baseURL, path: path, query: parameters,
                referer: referer, cookieHeader: context.cookieHeader,
                cachePolicy: .reloadIgnoringLocalCacheData)
            request.httpMethod = "POST"
            request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body ?? .object([:]))
            let (data, _) = try await self.data(for: request, priority: URLSessionTask.highPriority, retryPolicy: Self.piliSingleWrite)
            response = try await Self.decode(data, priority: URLSessionTask.highPriority)
        }
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload ?? .null
    }

    func uploadPiliContentImage(_ bytes: Data, identity: PiliAccountIdentity, biz: String = "new_dyn") async throws -> DynamicCommentImage {
        let context = await requestSnapshot(purpose: .main)
        guard identity.matches(context) else { throw PiliOfflineError.message("账号已切换，请重新打开编辑器") }
        guard let csrf = context.csrfToken else { throw BiliAPIError.missingCSRF }
        guard !bytes.isEmpty, bytes.count <= 10 * 1024 * 1024 else { throw PiliOfflineError.message("图片需小于 10 MB") }
        let response: BiliResponse<DynamicJSONValue> = try await postMultipart(base: baseURL,
            path: "/x/dynamic/feed/draw/upload_bfs", fields: ["biz": biz, "category": "daily", "csrf": csrf],
            fileField: "file_up", fileName: "image.jpg", mimeType: "image/jpeg", fileData: bytes,
            cookieHeader: context.cookieHeader, retryPolicy: Self.piliSingleWrite)
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let p = response.payload, !p["image_url"].piliString.isEmpty,
              p["image_width"].piliInt > 0, p["image_height"].piliInt > 0 else { throw BiliAPIError.missingPayload }
        return DynamicCommentImage(imageURL: p["image_url"].piliString.normalizedBiliURL(),
            width: p["image_width"].piliInt, height: p["image_height"].piliInt, size: bytes.count)
    }
}
