import Foundation
import PiliPlaybackCore

nonisolated struct PiliAudioTrack: Identifiable, Sendable {
    let id: Int
    let item: PiliProtoMessage
    let title: String
    let cover: String
    let description: String
    let duration: Int
    let owner: VideoOwner
    let liked: Bool
    let likes: Int
    init?(_ message: PiliProtoMessage) throws {
        let item = try message.message(1), archive = try message.message(2), owner = try message.message(4), stats = try message.message(5)
        guard item.integer(1) == 3, item.integer(3) > 0 else { return nil }
        self.item = item; id = item.integer(3); title = archive.string(2); cover = archive.string(3)
        description = archive.string(4); duration = archive.integer(5)
        self.owner = .init(mid: owner.integer(1), name: owner.string(2), face: owner.string(3))
        liked = stats.integer(7) != 0; likes = stats.integer(1)
    }
}

nonisolated struct PiliAudioSource: Identifiable, Sendable {
    let id: Int
    let url: URL
    let duration: Double
    var title: String {
        switch id { case 30251: "Hi-Res"; case 30250: "杜比音效"; case 30280: "高品质"; case 30232: "标准"; case 30216: "流畅"; default: "音质 \(id)" }
    }
    static func decode(_ response: PiliProtoMessage) throws -> [Self] {
        var result: [Self] = []
        for entry in try response.messages(4) {
            let info = try entry.message(2)
            guard info.integer(11) == 0 else { continue }
            let dash = try info.message(5)
            for audio in try dash.messages(3) {
                if let url = streamURL(audio.string(2)) {
                    result.append(.init(id: audio.integer(1), url: url, duration: Double(dash.integer(1))))
                }
            }
            if result.isEmpty {
                let durls = try info.message(4).messages(1)
                // A multi-part response cannot be represented by a single AVURLAsset.
                if durls.count == 1, let first = durls.first, let url = streamURL(first.string(6)) {
                    result.append(.init(id: info.integer(1), url: url, duration: Double(first.integer(2)) / 1000))
                }
            }
        }
        guard !result.isEmpty else {
            throw PiliOfflineError.message(response.string(3).isEmpty ? "此音频暂时没有可播放的音轨" : response.string(3))
        }
        var ids = Set<Int>()
        return result.filter { ids.insert($0.id).inserted }.sorted { $0.id > $1.id }
    }
    private static func streamURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw.normalizedBiliURL()), ["https", "http"].contains(url.scheme ?? ""), url.host != nil else { return nil }
        return url
    }
}

nonisolated enum PiliAudioCodec {
    static func item(_ id: Int) -> PiliProtoMessage {
        var item = PiliProtoMessage(); item.set(1, integer: 3); item.set(3, integer: id); return item
    }
    static var playerArgs: PiliProtoMessage {
        var args = PiliProtoMessage(); args.set(1, integer: 80); args.set(3, integer: 4048); args.set(4, integer: 2); args.set(5, integer: 1); return args
    }
    static func playlist(id: Int, cursor: String?, order: VideoListenPlaylistSortOrder) -> PiliProtoMessage {
        var request = PiliProtoMessage(), sort = PiliProtoMessage(), page = PiliProtoMessage()
        if cursor == nil { request.set(1, integer: 3); request.set(3, message: item(id)) }
        request.set(2, integer: id); request.set(5, message: playerArgs)
        sort.set(1, integer: Int(order.listenerValue)); request.set(7, message: sort)
        page.set(1, integer: 20); if let cursor { page.set(2, string: cursor) }; request.set(8, message: page)
        return request
    }
}

extension BiliAPIClient {
    func piliAudioPlaylist(id: Int, cursor: String? = nil, order: VideoListenPlaylistSortOrder = .normal) async throws -> (items: [PiliAudioTrack], next: String?) {
        guard id > 0 else { throw BiliAPIError.missingPayload }
        let result = try await piliGRPC("/bilibili.app.listener.v1.Listener/Playlist", message: PiliAudioCodec.playlist(id: id, cursor: cursor, order: order), identity: nil, needsLogin: false, purpose: .playback)
        let items = try result.messages(4).compactMap { try PiliAudioTrack($0) }, next = try result.message(7).string(1)
        return (items, result.integer(3) != 0 || next.isEmpty || next == cursor ? nil : next)
    }
    func piliAudioSources(_ item: PiliProtoMessage) async throws -> [PiliAudioSource] {
        guard item.integer(1) == 3, item.integer(3) > 0 else { throw BiliAPIError.missingPayload }
        var request = PiliProtoMessage(); request.set(1, message: item); request.set(2, message: PiliAudioCodec.playerArgs)
        return try PiliAudioSource.decode(await piliGRPC("/bilibili.app.listener.v1.Listener/PlayURL", message: request, identity: nil, needsLogin: false, purpose: .playback))
    }
    func piliAudioAction(_ method: String, item: PiliProtoMessage, liked: Bool = false, identity: PiliAccountIdentity) async throws -> PiliProtoMessage {
        guard ["ThumbUp", "CoinAdd", "TripleLike"].contains(method), item.integer(1) == 3, item.integer(3) > 0 else { throw BiliAPIError.missingPayload }
        var request = PiliProtoMessage(); request.set(1, message: item)
        if method == "ThumbUp" { request.set(2, integer: liked ? 1 : 0) }
        if method == "CoinAdd" { request.set(2, integer: 1); request.set(3, integer: 0) }
        return try await piliGRPC("/bilibili.app.listener.v1.Listener/" + method, message: request, identity: identity, write: true, purpose: .interaction)
    }
}
