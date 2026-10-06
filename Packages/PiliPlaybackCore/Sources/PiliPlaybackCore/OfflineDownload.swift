import Foundation

public enum OfflineDownloadPart: String, Codable, CaseIterable, Sendable { case video, audio }
public enum OfflineMediaKind: String, Codable, CaseIterable, Sendable { case video, audio }
public enum OfflineDownloadState: String, Codable, Sendable {
    case queued, preparing, downloading, paused, finalizing, completed, failed
}

public struct OfflineTaskIdentity: Codable, Hashable, Sendable {
    public let itemID: UUID
    public let generation: UUID
    public let part: OfflineDownloadPart
    public init(itemID: UUID, generation: UUID, part: OfflineDownloadPart) {
        self.itemID = itemID; self.generation = generation; self.part = part
    }
    public var taskDescription: String {
        "\(itemID.uuidString)|\(generation.uuidString)|\(part.rawValue)"
    }
    public init?(taskDescription: String?) {
        guard let taskDescription else { return nil }
        let fields = taskDescription.split(separator: "|", omittingEmptySubsequences: false)
        guard fields.count == 3, let id = UUID(uuidString: String(fields[0])),
              let generation = UUID(uuidString: String(fields[1])),
              let part = OfflineDownloadPart(rawValue: String(fields[2])) else { return nil }
        self.init(itemID: id, generation: generation, part: part)
    }
}

public struct OfflineDownloadItem: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let bvid: String
    public let cid: Int
    public let title: String
    public let author: String
    public let coverURL: String?
    public let duration: Double
    public let quality: Int
    public let seasonID: Int?
    public let episodeID: Int?
    public let createdAt: Date
    public var qualityTitle: String
    public var codec: String?
    public var dynamicRange = "sdr"
    public var generation = UUID()
    public var state: OfflineDownloadState = .queued
    public var requiresAudio = true
    public var completedParts: Set<OfflineDownloadPart> = []
    public var receivedBytes: [OfflineDownloadPart: Int64] = [:]
    public var expectedBytes: [OfflineDownloadPart: Int64] = [:]
    public var outputFileName: String?
    public var fileSize: Int64 = 0
    public var errorMessage: String?
    public var lastPlaybackTime: Double = 0
    public var hasDanmaku = false
    public var hasSubtitles: Bool?
    public var extrasError: String?
    // Optional stored fields keep indexes written before audio-only downloads readable.
    public var mediaKind: OfflineMediaKind?
    public var audioQualityID: Int?
    public var collectionID: String?
    public var collectionTitle: String?

    public var collectionKey: String { collectionID ?? seasonID.map { "season:\($0)" } ?? "video:\(bvid)" }

    public init(id: UUID = UUID(), bvid: String, cid: Int, title: String, author: String,
                coverURL: String?, duration: Double, quality: Int, qualityTitle: String,
                codec: String?, seasonID: Int? = nil, episodeID: Int? = nil, createdAt: Date = Date()) {
        self.id = id; self.bvid = bvid; self.cid = cid; self.title = title; self.author = author
        self.coverURL = coverURL; self.duration = duration; self.quality = quality
        self.qualityTitle = qualityTitle; self.codec = codec; self.seasonID = seasonID
        self.episodeID = episodeID; self.createdAt = createdAt
    }
    public var effectiveMediaKind: OfflineMediaKind { mediaKind ?? .video }
    public var requiredParts: Set<OfflineDownloadPart> {
        effectiveMediaKind == .audio ? [.audio] : (requiresAudio ? [.video, .audio] : [.video])
    }
    public var isReadyToFinalize: Bool { requiredParts.isSubset(of: completedParts) }
    public var progress: Double? {
        if state == .completed { return 1 }
        guard requiredParts.allSatisfy({ (expectedBytes[$0] ?? 0) > 0 }) else { return nil }
        let total = requiredParts.reduce(Int64(0)) { $0 + (expectedBytes[$1] ?? 0) }
        let received = requiredParts.reduce(Int64(0)) { $0 + (receivedBytes[$1] ?? 0) }
        return min(1, max(0, Double(received) / Double(total)))
    }
    public func accepts(_ identity: OfflineTaskIdentity) -> Bool {
        identity.itemID == id && identity.generation == generation && requiredParts.contains(identity.part)
            && state == .downloading
    }
}
