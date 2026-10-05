import Foundation
import PiliPlaybackCore

nonisolated struct PiliSubtitleTrack: Codable, Identifiable, Hashable, Sendable {
    let lan: String
    let lanDoc: String?
    let subtitleURL: String?
    let type: Int?
    var id: String { lan + "|" + (subtitleURL ?? "") }
    var isAI: Bool { type == 1 || lan.hasPrefix("ai-") }
    var title: String { (lanDoc ?? lan) + (isAI ? " · AI" : "") }
    enum CodingKeys: String, CodingKey { case lan, type; case lanDoc = "lan_doc", subtitleURL = "subtitle_url" }
}

nonisolated struct PiliPlayerMetadata: Decodable, Sendable {
    struct SubtitleList: Decodable, Sendable { let subtitles: [PiliSubtitleTrack]? }
    struct Interaction: Decodable, Sendable {
        let graphVersion: Int?
        enum CodingKeys: String, CodingKey { case graphVersion = "graph_version" }
    }
    let subtitle: SubtitleList?
    let interaction: Interaction?
}

nonisolated struct PiliCachedSubtitle: Codable, Sendable {
    let track: PiliSubtitleTrack
    let cues: [SubtitleCue]
    static func load(_ id: UUID) -> [Self] {
        guard let directory = try? PiliOfflineStorage.directory(id),
              let data = try? Data(contentsOf: directory.appendingPathComponent("subtitles.json")) else { return [] }
        return (try? JSONDecoder().decode([Self].self, from: data)) ?? []
    }
}
