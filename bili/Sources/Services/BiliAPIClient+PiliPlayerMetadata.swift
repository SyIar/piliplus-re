import Foundation
import PiliPlaybackCore

extension BiliAPIClient {
    func fetchPiliPlayerMetadata(bvid: String, cid: Int, seasonID: Int? = nil, episodeID: Int? = nil) async throws -> PiliPlayerMetadata {
        let context = await playbackAPIRequestContext()
        var query = ["bvid": bvid, "cid": String(cid)]
        if let seasonID { query["season_id"] = String(seasonID) }
        if let episodeID { query["ep_id"] = String(episodeID) }
        let signed = try await signedWBIQuery(query)
        let response: BiliResponse<PiliPlayerMetadata> = try await get(
            base: baseURL, path: "/x/player/wbi/v2", query: signed,
            cookieHeader: context.cookieHeader, responseCachePolicy: .brief
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let payload = response.payload else { throw BiliAPIError.missingPayload }
        return payload
    }
    func fetchPiliSubtitles(_ track: PiliSubtitleTrack) async throws -> [SubtitleCue] {
        guard var address = track.subtitleURL else { throw BiliAPIError.missingPayload }
        if address.hasPrefix("//") { address = "https:" + address }
        guard let url = URL(string: address), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased(),
              host == "hdslb.com" || host.hasSuffix(".hdslb.com") || host == "bilibili.com" || host.hasSuffix(".bilibili.com") else {
            throw PiliOfflineError.message("字幕地址无效")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.httpShouldHandleCookies = false
        request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        // CDN subtitle requests deliberately carry no account credentials.
        let (data, _) = try await self.data(for: request, priority: URLSessionTask.defaultPriority)
        guard data.count <= 8 * 1024 * 1024 else { throw PiliOfflineError.message("字幕文件过大") }
        struct Document: Decodable { let body: [SubtitleCue] }
        return SubtitleTimeline(try JSONDecoder().decode(Document.self, from: data).body).cues
    }
}
