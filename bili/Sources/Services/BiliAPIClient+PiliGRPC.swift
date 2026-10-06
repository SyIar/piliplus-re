import Foundation
import PiliPlaybackCore

extension BiliAPIClient {
    func piliGRPC(_ path: String, message: PiliProtoMessage = .init(), identity: PiliAccountIdentity?,
                  write: Bool = false, needsLogin: Bool = true, purpose: BiliAccountPurpose = .main) async throws -> PiliProtoMessage {
        let context = await requestSnapshot(purpose: purpose)
        if let identity, !identity.matches(context) { throw PiliOfflineError.message("账号已切换，请重新打开页面") }
        let access = context.appAccessKey ?? ""
        if needsLogin && access.isEmpty { throw PiliOfflineError.message("此功能需要 App 登录凭据，请使用二维码或短信重新登录") }
        let headers = BiliListenerPlaylistCodec.grpcHeaders(accessKey: access,
            buvid: Self.cookieValue(named: "buvid3", in: context.cookieHeader) ?? "",
            networkClass: PlaybackEnvironment.current.networkClass, traceID: Self.piliPlusTraceID())
        var request = try await makeRequest(base: appURL, path: path, query: [:], referer: "https://www.bilibili.com/",
            userAgent: BiliAppSigner.Profile.androidHD.userAgent, cookieHeader: context.cookieHeader,
            additionalHeaders: headers, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "POST"; request.httpBody = BiliListenerPlaylistCodec.frame(message.data)
        try Task.checkCancellation()
        if let identity, !(await identity.matches(requestSnapshot(purpose: purpose))) { throw PiliOfflineError.message("账号已切换") }
        let (bytes, response) = try await data(for: request, priority: URLSessionTask.highPriority, retryPolicy: write ? Self.piliSingleWrite : .api)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw BiliListenerPlaylistError.invalidResponse }
        for key in ["bili-status-code", "grpc-status"] {
            if let code = http.value(forHTTPHeaderField: key).flatMap(Int.init), code != 0 {
                let text = http.value(forHTTPHeaderField: "bili-status-message") ?? http.value(forHTTPHeaderField: "grpc-message")
                throw BiliListenerPlaylistError.grpcStatus(code, text?.removingPercentEncoding ?? text)
            }
        }
        guard await requestSnapshot(purpose: purpose).playbackCredentialVersion == context.playbackCredentialVersion else {
            throw PiliOfflineError.message("账号已切换，请重新打开页面")
        }
        return try await Task.detached(priority: .userInitiated) {
            try PiliProtoMessage(data: BiliListenerPlaylistCodec.unframe(bytes))
        }.value
    }
    func piliIM(_ method: String, message: PiliProtoMessage = .init(), identity: PiliAccountIdentity, write: Bool = false) async throws -> PiliProtoMessage {
        try await piliGRPC("/bilibili.app.im.v1.im/" + method, message: message, identity: identity, write: write)
    }
}
