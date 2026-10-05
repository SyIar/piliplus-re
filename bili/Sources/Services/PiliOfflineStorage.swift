import Foundation
import PiliPlaybackCore

nonisolated enum PiliOfflineError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(message) = self { message } else { nil } }
}

/// User downloads live in Application Support, independently of disposable playback caches.
nonisolated enum PiliOfflineStorage {
    static func root() throws -> URL {
        var root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true)
            .appendingPathComponent("PiliOffline", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                               attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try root.setResourceValues(values)
        return root
    }

    static func directory(_ id: UUID) throws -> URL {
        let url = try root().appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static func part(_ id: UUID, _ part: OfflineDownloadPart) throws -> URL {
        try directory(id).appendingPathComponent("\(part.rawValue).mp4")
    }
    static func resumeFile(_ id: UUID, _ part: OfflineDownloadPart) throws -> URL {
        try directory(id).appendingPathComponent("\(part.rawValue).resume")
    }
    static func staging(_ identity: OfflineTaskIdentity) throws -> URL {
        let folder = try root().appendingPathComponent("Incoming", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("\(identity.itemID.uuidString)-\(identity.generation.uuidString)-\(identity.part.rawValue).mp4")
    }
    static func load() throws -> [OfflineDownloadItem] {
        let index = try root().appendingPathComponent("index.json")
        guard FileManager.default.fileExists(atPath: index.path) else { return [] }
        return try JSONDecoder().decode([OfflineDownloadItem].self, from: Data(contentsOf: index))
    }
    static func save(_ items: [OfflineDownloadItem]) throws {
        try JSONEncoder().encode(items).write(to: root().appendingPathComponent("index.json"), options: .atomic)
    }
    static func playbackURL(_ item: OfflineDownloadItem) throws -> URL {
        guard item.state == .completed, let name = item.outputFileName,
              ["media.mp4", "media.mov", "media.m4a"].contains(name) else {
            throw PiliOfflineError.message("媒体尚未下载完成")
        }
        let url = try directory(item.id).appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PiliOfflineError.message("下载文件已丢失，请重新下载")
        }
        return url
    }
    static func size(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }
}
