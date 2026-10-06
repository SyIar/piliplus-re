import Foundation

nonisolated enum PiliSupplementRoute: Hashable, Sendable {
    case audio(Int), music(String), bubble(String), match(Int)

    init?(url: URL) {
        let scheme = url.scheme?.lowercased(), host = url.host?.lowercased() ?? ""
        let parts = url.path.split(separator: "/").map(String.init)
        if scheme == "bilibili", host == "audio", let value = parts.last, let id = Int(value), id > 0 {
            self = .audio(id); return
        }
        guard scheme == "https" || scheme == "http" else { return nil }
        if host == "music.bilibili.com", url.path.contains("music-detail"),
           let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "music_id" })?.value,
           id.hasPrefix("MA"), id.count <= 128, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
            self = .music(id); return
        }
        guard ["www.bilibili.com", "m.bilibili.com", "bilibili.com"].contains(host) else { return nil }
        if parts.count == 2, parts[0] == "audio", parts[1].hasPrefix("au"), let id = Int(parts[1].dropFirst(2)), id > 0 {
            self = .audio(id)
        } else if parts.count == 3, parts[0] == "bubble", parts[1] == "home", let id = Int(parts[2]), id > 0 {
            self = .bubble(String(id))
        } else if (url.path.contains("match/data/detail/") || url.path.contains("match/singledata/")), let raw = parts.last, let id = Int(raw), id > 0 {
            self = .match(id)
        } else { return nil }
    }
}

nonisolated func piliCommentTarget(oid: String, type: Int, author: VideoOwner? = nil) throws -> DynamicFeedItem {
    guard Int64(oid).map({ $0 > 0 }) == true, type > 0 else { throw BiliAPIError.missingPayload }
    return try DynamicJSONValue.object([
        "id_str": .string(oid), "type": .string("DYNAMIC_TYPE_WORD"),
        "basic": .object(["comment_id_str": .string(oid), "comment_type": .number(String(type))]),
        "modules": .object(["module_author": .object(["mid": .number(String(author?.mid ?? 0)), "name": .string(author?.name ?? "")])])
    ]).piliDecode(DynamicFeedItem.self)
}
