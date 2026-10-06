import Foundation
import Combine

extension BiliAPIClient {
    /// The feed feedback endpoint is a GET with side effects. Bypass GET caching and retries.
    func piliFeedFeedback(video: VideoItem, reason: PiliFeedFeedbackReason, identity: PiliAccountIdentity) async throws {
        guard let metadata = video.piliRecommendation, metadata.reasons.contains(reason),
              let id = Int64(metadata.targetID), id > 0, !metadata.targetKind.isEmpty else { throw BiliAPIError.missingPayload }
        try await piliAccountAppRequest(path: "/x/feed/dislike", parameters: ["id": metadata.targetID,
            "goto": metadata.targetKind, reason.parameter: String(reason.value)], post: false, identity: identity)
    }

    func piliVideoDisliked(aid: Int, identity: PiliAccountIdentity) async throws -> Bool {
        let data = try await piliAccountAppRequest(path: "/x/v2/view", parameters: ["aid": String(aid)], post: false, identity: identity)
        guard case .object = data["req_user"] else { throw BiliAPIError.missingPayload }
        return data["req_user"]["dislike"].piliInt == 1
    }

    func piliDislikeVideo(aid: Int, dislike: Bool, identity: PiliAccountIdentity) async throws {
        guard aid > 0 else { throw BiliAPIError.missingPayload }
        try await piliAccountAppRequest(path: "/x/v2/view/dislike", parameters: ["aid": String(aid), "dislike": dislike ? "1" : "0"], post: true, identity: identity)
    }

    @discardableResult
    func piliAccountAppRequest(path: String, parameters: [String: String], post: Bool,
                                        identity: PiliAccountIdentity, base: URL? = nil) async throws -> DynamicJSONValue {
        let context = requestSnapshot(purpose: .main)
        guard identity.matches(context) else { throw PiliOfflineError.message("账号已切换，请重新打开页面") }
        guard let key = context.appAccessKey, !key.isEmpty else { throw PiliOfflineError.message("此操作需要 App 登录，请使用短信或 App 扫码登录") }
        let profile = BiliAppSigner.Profile.androidHD
        var values = ["access_key": key, "build": profile.build, "mobi_app": profile.mobiApp,
                      "platform": profile.platform, "channel": profile.channel]
        values.merge(parameters) { _, new in new }
        let query = BiliAppSigner.sign(values, profile: .androidHD)
        let response: BiliResponse<DynamicJSONValue>
        if post {
            response = try await postForm(base: base ?? appURL, path: path, body: query,
                userAgent: BiliAppSigner.Profile.androidHD.userAgent, cookieHeader: context.cookieHeader, retryPolicy: Self.piliSingleWrite)
        } else {
            let request = try await makeRequest(base: base ?? appURL, path: path, query: query,
                userAgent: BiliAppSigner.Profile.androidHD.userAgent, cookieHeader: context.cookieHeader, cachePolicy: .reloadIgnoringLocalCacheData)
            let (data, _) = try await self.data(for: request, priority: URLSessionTask.highPriority, retryPolicy: Self.piliSingleWrite)
            response = try await Self.decode(data, priority: URLSessionTask.highPriority)
        }
        guard identity.matches(requestSnapshot()) else { throw PiliOfflineError.message("账号已切换") }
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload ?? .null
    }
}

@MainActor
final class PiliFeedDismissals: ObservableObject {
    static let shared = PiliFeedDismissals()
    @Published private(set) var revision = 0
    private var hidden: [Int: Set<String>] = [:]
    func ids(account: Int) -> Set<String> { hidden[account] ?? [] }
    func dismiss(_ video: VideoItem, account: Int) {
        hidden[account, default: []].insert(video.bvid)
        revision &+= 1
    }
    func reset() { hidden = [:]; revision &+= 1 }
}
