import Foundation

/// Navigation context only. Account credentials and playback URLs are never stored here.
nonisolated struct PiliPlaybackQueue: Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case watchLater
        case watchLaterFiltered(PiliWatchLaterFilter)
        case favoriteFolder(Int)
        case ugcSeason(id: Int, title: String)
        case collection(owner: VideoOwner, kind: UploaderSeasonSeriesKind, ascending: Bool, title: String)
    }

    let source: Source
    let credentialVersion: Int
    var bvids: [String]
    var nextPage: Int?
    var titles: [String: String] = [:]

    var title: String {
        switch source {
        case .watchLater, .watchLaterFiltered: "稍后再看"
        case .favoriteFolder: "收藏夹"
        case let .ugcSeason(_, title), let .collection(_, _, _, title): title
        }
    }
    mutating func append(videos: [VideoItem]) {
        append(videos.map(\.bvid))
        for video in videos { titles[video.bvid] = video.title }
    }
    func placeholderVideos() -> [VideoItem] {
        bvids.map { VideoItem(bvid: $0, aid: nil, title: titles[$0] ?? $0, pic: nil, desc: nil, duration: nil,
                              pubdate: nil, owner: nil, stat: nil, cid: nil, pages: nil, dimension: nil) }
    }

    mutating func append(_ values: [String]) {
        var seen = Set(bvids)
        bvids.append(contentsOf: values.filter { !$0.isEmpty && seen.insert($0).inserted })
    }
}

extension VideoItem {
    nonisolated func withPiliPlaybackQueue(_ queue: PiliPlaybackQueue?) -> VideoItem {
        var video = self
        video.piliPlaybackQueue = queue
        return video
    }
}
