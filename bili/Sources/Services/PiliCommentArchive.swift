import Foundation

nonisolated struct PiliSavedComment: Codable, Identifiable, Hashable, Sendable {
    let account: Int
    let id: Int
    let oid: String
    let type: Int
    let root: Int
    let parent: Int
    let message: String
    let pictures: [String]
    let created: Int
    var isValid: Bool {
        account > 0 && id > 0 && Int64(oid).map({ $0 > 0 }) == true && type > 0 && root >= 0 && parent >= 0
            && message.utf8.count <= 128_000 && pictures.count <= 9 && pictures.allSatisfy { $0.utf8.count <= 4096 }
    }
    var contextURL: URL? {
        switch type {
        case 1: URL(string: "https://www.bilibili.com/video/av\(oid)?comment_root_id=\(root > 0 ? root : id)&comment_secondary_id=\(id)")
        case 12: URL(string: "https://www.bilibili.com/read/cv\(oid)")
        case 14: URL(string: "https://www.bilibili.com/audio/au\(oid)")
        case 17: URL(string: "https://t.bilibili.com/\(oid)")
        case 27: URL(string: "https://www.bilibili.com/match/data/detail/\(oid)")
        default: nil
        }
    }
}

actor PiliCommentArchive {
    static let shared = PiliCommentArchive()
    static let byteLimit = 16 * 1024 * 1024
    private let root: URL
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PiliCommentArchive", isDirectory: true)
    }
    private func file(_ account: Int) throws -> URL {
        guard account > 0 else { throw BiliAPIError.missingSESSDATA }
        return root.appendingPathComponent("\(account).json")
    }
    func comments(account: Int) throws -> [PiliSavedComment] {
        let url = try file(account)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= Self.byteLimit else { throw PiliOfflineError.message("评论备份超过 16 MB") }
        return try decode(Data(contentsOf: url), account: account)
    }
    func record(_ comment: PiliSavedComment) throws {
        guard comment.isValid else { throw BiliAPIError.missingPayload }
        var values = try comments(account: comment.account); values.removeAll { $0.id == comment.id }; values.append(comment)
        try save(values, account: comment.account)
    }
    func remove(id: Int, account: Int) throws {
        try save(comments(account: account).filter { $0.id != id }, account: account)
    }
    func export(account: Int) throws -> Data { try JSONEncoder().encode(comments(account: account)) }
    @discardableResult
    func merge(_ data: Data, account: Int) throws -> Int {
        let imported = try decode(data, account: account), existing = try comments(account: account)
        var ids = Set(existing.map(\.id)); let fresh = imported.filter { ids.insert($0.id).inserted }
        try save(existing + fresh, account: account); return fresh.count
    }
    func importFile(_ url: URL, account: Int) throws -> Int {
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= Self.byteLimit else { throw PiliOfflineError.message("评论备份超过 16 MB") }
        return try merge(Data(contentsOf: url), account: account)
    }
    private func decode(_ data: Data, account: Int) throws -> [PiliSavedComment] {
        guard account > 0, data.count <= Self.byteLimit else { throw PiliOfflineError.message("评论备份超过 16 MB 或尚未登录") }
        let values: [PiliSavedComment]
        if let own = try? JSONDecoder().decode([PiliSavedComment].self, from: data) { values = own }
        else {
            // Upstream exports ReplyInfo.toProto3Json(). Bind imported records to
            // their actual author, never to whichever account happens to be open.
            let raw = try JSONDecoder().decode([DynamicJSONValue].self, from: data)
            values = raw.map { value in
                .init(account: value["member"]["mid"].piliInt, id: value["id"].piliInt, oid: value["oid"].piliString,
                      type: value["type"].piliInt, root: value["root"].piliInt, parent: value["parent"].piliInt,
                      message: value["content"]["message"].piliString,
                      pictures: value["content"]["pictures"].piliArray.map { $0["imgSrc"].piliString }, created: value["ctime"].piliInt)
            }
        }
        guard values.count <= 20_000, values.allSatisfy(\.isValid) else { throw PiliOfflineError.message("评论备份格式无效") }
        guard values.allSatisfy({ $0.account == account }) else { throw PiliOfflineError.message("备份包含其他账号的评论，请切换到对应的互动账号后导入") }
        var seen = Set<Int>()
        return Array(values.sorted { $0.created > $1.created }.filter { seen.insert($0.id).inserted }.prefix(2000))
    }
    private func save(_ values: [PiliSavedComment], account: Int) throws {
        var seen = Set<Int>()
        var kept = Array(values.sorted { $0.created > $1.created }.filter { $0.account == account && $0.isValid && seen.insert($0.id).inserted }.prefix(2000))
        var bytes = try JSONEncoder().encode(kept)
        while bytes.count > Self.byteLimit, !kept.isEmpty { kept.removeLast(max(1, kept.count / 10)); bytes = try JSONEncoder().encode(kept) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try bytes.write(to: file(account), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
