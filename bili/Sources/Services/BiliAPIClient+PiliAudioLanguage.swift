import Foundation

nonisolated struct PiliAudioLanguage: Decodable, Hashable, Identifiable, Sendable {
    let lang: String?
    let title: String?
    let subtitleLang: String?
    let productionType: Int?
    var id: String { lang ?? "" }
    var displayTitle: String { (title ?? lang ?? "原声") + (productionType == 2 ? " · AI" : "") }
    enum CodingKeys: String, CodingKey { case lang, title; case subtitleLang = "subtitle_lang", productionType = "production_type" }
}
nonisolated struct PiliAudioLanguages: Decodable, Sendable {
    let support: Bool?
    let items: [PiliAudioLanguage]?
}

extension BiliAPIClient {
    func piliLanguagePlayURL(bvid: String, cid: Int, language: String, quality: Int,
                            seasonID: Int? = nil, episodeID: Int? = nil) async throws -> PlayURLData {
        let snapshot = requestSnapshot(purpose: .playback)
        guard snapshot.isLoggedIn else { throw PiliOfflineError.message("请先登录播放账号以使用原声翻译") }
        var query = ["bvid": bvid, "cid": String(cid), "qn": String(quality), "fnval": "4048", "fnver": "0", "fourk": "1", "cur_language": language]
        if let seasonID { query["season_id"] = String(seasonID) }
        if let episodeID { query["ep_id"] = String(episodeID) }
        let path: String
        if let courseID = bvid.piliCourseEpisodeID {
            query["ep_id"] = String(courseID); query["try_look"] = "1"; query.removeValue(forKey: "bvid")
            path = "/pugv/player/web/playurl"
        } else { path = episodeID == nil ? "/x/player/wbi/playurl" : "/pgc/player/web/v2/playurl" }
        let result = try await piliContentRead(path, query: query, signed: true, purpose: .playback)
        let payload = result["video_info"].piliObject.isEmpty ? result : result["video_info"]
        let value = try payload.piliDecode(PlayURLData.self)
        guard value.code == nil || value.code == 0 else { throw BiliAPIError.api(code: value.code ?? -1, message: value.message) }
        guard value.hasPlayableStreamPayload else { throw BiliAPIError.emptyPlayURL }
        if !language.isEmpty, value.curLanguage != language {
            throw PiliOfflineError.message("该原声翻译暂不可用")
        }
        guard requestSnapshot(purpose: .playback).playbackCredentialVersion == snapshot.playbackCredentialVersion else {
            throw PiliOfflineError.message("播放账号已切换")
        }
        // Translated streams intentionally bypass the original-audio preload cache.
        return value
    }
}
