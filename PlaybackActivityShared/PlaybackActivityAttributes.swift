import ActivityKit
import Foundation

nonisolated struct PlaybackActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var title: String
        var author: String
        var isPlaying: Bool
        var elapsed: Double
        var duration: Double
        var rate: Double
        var updatedAt: Date

        var progress: Double { duration > 0 ? min(max(elapsed / duration, 0), 1) : 0 }
    }

    var sessionID: String
}
