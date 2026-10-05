import Foundation

/// Navigation context only. Account credentials and playback URLs are never stored here.
nonisolated struct PiliPlaybackQueue: Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case watchLater
        case favoriteFolder(Int)
    }

    let source: Source
    let credentialVersion: Int
    var bvids: [String]
    var nextPage: Int?

    mutating func append(_ values: [String]) {
        var seen = Set(bvids)
        bvids.append(contentsOf: values.filter { !$0.isEmpty && seen.insert($0).inserted })
    }
}

extension VideoItem {
    func withPiliPlaybackQueue(_ queue: PiliPlaybackQueue?) -> VideoItem {
        var video = self
        video.piliPlaybackQueue = queue
        return video
    }
}
