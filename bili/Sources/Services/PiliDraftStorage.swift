import CryptoKit
import Foundation

actor PiliDraftStorage {
    static let shared = PiliDraftStorage()
    nonisolated struct Image: Sendable { let id: UUID; let data: Data }
    nonisolated struct Saved: Codable, Sendable {
        var content: PiliDynamicDraft
        var imageFiles: [String]
    }
    private let root: URL
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PiliContentDrafts", isDirectory: true)
    }
    private func directory(_ key: String) -> URL {
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(name, isDirectory: true)
    }
    func save(_ content: PiliDynamicDraft, images: [Image], key: String) throws {
        try Task.checkCancellation()
        let dir = directory(key)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var names = [String]()
        for image in images.prefix(9) {
            let name = image.id.uuidString.lowercased() + ".jpg"
            let url = dir.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path) { try image.data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
            names.append(name)
        }
        try Task.checkCancellation()
        let data = try JSONEncoder().encode(Saved(content: content, imageFiles: names))
        try data.write(to: dir.appendingPathComponent("draft.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        // Remove only files no longer referenced by the successfully written header.
        let keep = Set(names + ["draft.json"])
        for file in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) where !keep.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }
    func load(key: String) throws -> (PiliDynamicDraft, [Image])? {
        let dir = directory(key), file = directory(key).appendingPathComponent("draft.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 1024 * 1024 else { throw BiliAPIError.missingPayload }
        let saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: file))
        guard saved.imageFiles.count <= 9, saved.imageFiles.allSatisfy({ $0.hasSuffix(".jpg") && UUID(uuidString: String($0.dropLast(4))) != nil }) else { throw BiliAPIError.missingPayload }
        let images = try saved.imageFiles.map { name -> Image in
            let url = dir.appendingPathComponent(name)
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 10 * 1024 * 1024 else { throw BiliAPIError.missingPayload }
            return Image(id: UUID(uuidString: String(name.dropLast(4)))!, data: try Data(contentsOf: url))
        }
        return (saved.content, images)
    }
    func remove(key: String) throws {
        let dir = directory(key)
        if FileManager.default.fileExists(atPath: dir.path) { try FileManager.default.removeItem(at: dir) }
    }
    func archive(key: String) throws {
        let dir = directory(key)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.moveItem(at: dir, to: root.appendingPathComponent(dir.lastPathComponent + ".recovery." + UUID().uuidString))
        }
    }
}
