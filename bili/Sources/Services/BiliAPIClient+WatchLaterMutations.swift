import Foundation

nonisolated enum WatchLaterCleanup: Sendable {
    case invalid, viewed, all
}

extension BiliAPIClient {
    func addToWatchLater(bvid: String) async throws {
        guard !bvid.isEmpty else { throw BiliAPIError.missingPayload }
        try await mutateWatchLater(path: "/x/v2/history/toview/add", values: ["bvid": bvid])
    }

    func removeFromWatchLater(aids: [Int]) async throws {
        let ids = Set(aids.filter { $0 > 0 }).sorted()
        guard !ids.isEmpty else { throw BiliAPIError.missingPayload }
        try await mutateWatchLater(
            path: "/x/v2/history/toview/v2/dels",
            values: ["resources": ids.map(String.init).joined(separator: ",")]
        )
    }

    func cleanWatchLater(_ mode: WatchLaterCleanup) async throws {
        let values: [String: String]
        switch mode {
        case .invalid: values = ["clean_type": "1"]
        case .viewed: values = ["clean_type": "2"]
        case .all: values = [:]
        }
        try await mutateWatchLater(path: "/x/v2/history/toview/clear", values: values)
    }

    private func mutateWatchLater(path: String, values: [String: String]) async throws {
        // Use the same account purpose as fetchAccountWatchLater; never mix
        // one account's CSRF token with another account's Cookie header.
        let context = await interactionRequestContext(purpose: .historyRead)
        guard context.isLoggedIn else { throw BiliAPIError.missingSESSDATA }
        guard let csrf = context.csrfToken, !csrf.isEmpty else { throw BiliAPIError.missingCSRF }
        var body = values
        body["csrf"] = csrf
        let response: BiliResponse<DynamicJSONValue> = try await postForm(
            base: baseURL, path: path, body: body,
            cookieHeader: context.cookieHeader,
            retryPolicy: BiliNetworkRetryPolicy(
                label: "watchLaterMutation", attempts: 1,
                baseDelayNanoseconds: 0, maxDelayNanoseconds: 0, jitterNanoseconds: 0
            )
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
    }
}
