import Foundation
import PiliPlaybackCore

extension BiliAPIClient {
    func fetchPiliSubtitleTracks(bvid: String, aid: Int? = nil, cid: Int,
                                 seasonID: Int? = nil, episodeID: Int? = nil) async throws -> [PiliSubtitleTrack] {
        let context = requestSnapshot(purpose: .playback)
        let metadata = try await fetchPiliPlayerMetadata(bvid: bvid, cid: cid, seasonID: seasonID, episodeID: episodeID)
        let tracks = metadata.subtitle?.subtitles ?? []
        guard tracks.isEmpty, !context.isLoggedIn, !bvid.hasPrefix("pugv-") else { return tracks }
        let resolvedAID: Int?
        if let aid, aid > 0 { resolvedAID = aid }
        else { resolvedAID = try await fetchVideoDetail(bvid: bvid).aid }
        guard let resolvedAID, resolvedAID > 0, cid > 0 else { return [] }
        var request = PiliProtoMessage()
        request.set(1, integer: resolvedAID); request.set(2, integer: cid); request.set(3, integer: 1)
        let response = try await piliGRPC("/bilibili.community.service.dm.v1.DM/DmView", message: request,
            identity: nil, needsLogin: false, purpose: .playback)
        guard requestSnapshot(purpose: .playback).playbackCredentialVersion == context.playbackCredentialVersion else {
            throw PiliOfflineError.message("播放账号已切换")
        }
        return try Self.piliGuestSubtitleTracks(response)
    }

    nonisolated static func piliGuestSubtitleTracks(_ response: PiliProtoMessage) throws -> [PiliSubtitleTrack] {
        var seen = Set<String>()
        return try response.message(3).messages(3).compactMap { item in
            let language = item.string(3), address = item.string(5)
            guard !language.isEmpty, !address.isEmpty else { return nil }
            let track = PiliSubtitleTrack(lan: language, lanDoc: item.string(4), subtitleURL: address, type: item.integer(7))
            return seen.insert(track.id).inserted ? track : nil
        }
    }
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
        nonisolated struct Document: Decodable { let body: [SubtitleCue] }
        return try await Task.detached(priority: .userInitiated) {
            SubtitleTimeline(try JSONDecoder().decode(Document.self, from: data).body).cues
        }.value
    }
}
