import Combine
import Foundation
import PiliPlaybackCore

nonisolated struct PiliDanmakuRule: Codable, Identifiable, Equatable, Sendable {
    let id: Int
    let type: Int
    let filter: String

    static func userHash(_ mid: Int) -> String {
        var crc = UInt32.max
        for byte in String(mid).utf8 {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 0 ? 0 : 0xedb88320) }
        }
        return String(crc ^ UInt32.max, radix: 16)
    }

    static func input(_ text: String, type: Int) throws -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (0...2).contains(type), !value.isEmpty, value.count <= 256 else {
            throw PiliOfflineError.message("请输入 1–256 个字符的屏蔽规则")
        }
        if type == 1 { _ = try NSRegularExpression(pattern: value) }
        if type == 2 {
            guard let mid = Int(value), mid > 0 else { throw PiliOfflineError.message("请输入有效的用户 UID") }
            return userHash(mid)
        }
        return value
    }
}

/// Compile once per rule update, never on the animation clock.
nonisolated struct PiliDanmakuRuleMatcher {
    let words: [String]
    let patterns: [NSRegularExpression]
    let users: Set<String>
    init(_ rules: [PiliDanmakuRule]) {
        words = rules.filter { $0.type == 0 && !$0.filter.isEmpty }.map(\.filter)
        patterns = rules.filter { $0.type == 1 && !$0.filter.isEmpty }.compactMap { try? NSRegularExpression(pattern: $0.filter) }
        users = Set(rules.filter { $0.type == 2 }.map { $0.filter.lowercased() })
    }
    func blocks(_ item: DanmakuItem) -> Bool {
        if let hash = item.senderHash, users.contains(hash.lowercased()) { return true }
        let text = item.special?.text ?? item.text
        if words.contains(where: text.contains) { return true }
        return patterns.contains { $0.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil }
    }
}

extension BiliAPIClient {
    func piliDanmakuRules(identity: PiliAccountIdentity) async throws -> [PiliDanmakuRule] {
        let data = try await piliContentRead("/x/dm/filter/user", identity: identity)
        if case .object = data, case .null = data["rule"] { return [] }
        guard case .array(let values) = data["rule"], values.count <= 5000 else { throw BiliAPIError.missingPayload }
        return try values.map { try $0.piliDecode(PiliDanmakuRule.self) }
    }
    func addPiliDanmakuRule(text: String, type: Int, identity: PiliAccountIdentity) async throws -> PiliDanmakuRule {
        let filter = try PiliDanmakuRule.input(text, type: type)
        let data = try await piliContentWrite("/x/dm/filter/user/add", fields: ["type": String(type), "filter": filter], identity: identity)
        let rule = try data.piliDecode(PiliDanmakuRule.self)
        guard rule.id > 0, rule.type == type else { throw BiliAPIError.missingPayload }
        return rule
    }
    func recallPiliDanmaku(_ item: DanmakuItem, identity: PiliAccountIdentity) async throws {
        guard identity.mid > 0, item.senderHash?.lowercased() == PiliDanmakuRule.userHash(identity.mid),
              let id = item.serverID, let number = Int64(id), number > 0, let cid = item.cid, cid > 0 else {
            throw PiliOfflineError.message("只能撤回自己发送的弹幕")
        }
        try await piliContentWrite("/x/dm/recall", fields: ["dmid": id, "cid": String(cid), "type": "1"], identity: identity)
    }
}

@MainActor
final class PiliDanmakuRulesStore: ObservableObject {
    static let shared = PiliDanmakuRulesStore()
    @Published private(set) var rules: [PiliDanmakuRule] = []
    @Published private(set) var revision = 0
    @Published private(set) var error: String?
    @Published private(set) var busy = false
    private(set) var identity: PiliAccountIdentity?
    private var matcher = PiliDanmakuRuleMatcher([])
    private var recalled = Set<String>()
    private var refreshed: Date?
    private var generation = UUID()
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func synchronize(api: BiliAPIClient) {
        let expected = PiliAccountIdentity(api.requestSnapshot(purpose: .main))
        guard identity != expected else { return }
        identity = expected; generation = UUID(); refreshed = nil; error = nil; busy = false; recalled = []
        let bytes = defaults.data(forKey: cacheKey(expected.mid))
        let cached = bytes.flatMap { try? JSONDecoder().decode([PiliDanmakuRule].self, from: $0) } ?? []
        install(expected.mid > 0 ? Array(cached.prefix(5000)) : [])
    }

    func refresh(api: BiliAPIClient, force: Bool = false) async {
        synchronize(api: api)
        guard let expected = identity, expected.matches(api.requestSnapshot()), !busy else { return }
        if !force, let refreshed, Date().timeIntervalSince(refreshed) < 300 { return }
        let token = generation
        busy = true
        defer { if generation == token { busy = false } }
        do {
            let values = try await api.piliDanmakuRules(identity: expected)
            guard generation == token, expected.matches(api.requestSnapshot()), !Task.isCancelled else { return }
            install(values); persist(); refreshed = Date(); error = nil
        } catch { if generation == token, !Task.isCancelled { self.error = error.localizedDescription } }
    }

    func add(text: String, type: Int, api: BiliAPIClient, identity expected: PiliAccountIdentity) async throws {
        guard expected == identity, expected.matches(api.requestSnapshot()), !busy else { throw PiliOfflineError.message("请重新打开弹幕屏蔽规则") }
        let token = generation
        busy = true
        defer { if generation == token { busy = false } }
        let rule = try await api.addPiliDanmakuRule(text: text, type: type, identity: expected)
        guard generation == token, expected.matches(api.requestSnapshot()) else { throw PiliOfflineError.message("账号已切换") }
        install(rules.filter { $0.id != rule.id } + [rule]); persist(); error = nil
    }

    func remove(_ rule: PiliDanmakuRule, api: BiliAPIClient, identity expected: PiliAccountIdentity) async throws {
        guard expected == identity, expected.matches(api.requestSnapshot()), !busy else { throw PiliOfflineError.message("请重新打开弹幕屏蔽规则") }
        let token = generation
        busy = true
        defer { if generation == token { busy = false } }
        try await api.piliContentWrite("/x/dm/filter/user/del", fields: ["ids": String(rule.id)], identity: expected)
        guard generation == token, expected.matches(api.requestSnapshot()) else { throw PiliOfflineError.message("账号已切换") }
        install(rules.filter { $0.id != rule.id }); persist(); error = nil
    }

    func didRecall(_ item: DanmakuItem, identity expected: PiliAccountIdentity) {
        guard identity == expected, let cid = item.cid, let id = item.serverID else { return }
        recalled.insert("\(cid):\(id)"); revision &+= 1
    }
    func filter(_ items: [DanmakuItem], identity expected: PiliAccountIdentity) -> [DanmakuItem] {
        guard identity == expected, !rules.isEmpty || !recalled.isEmpty else { return items }
        return items.filter { !matcher.blocks($0) && !recalled.contains("\($0.cid ?? 0):\($0.serverID ?? "")") }
    }
    private func install(_ values: [PiliDanmakuRule]) { rules = values; matcher = .init(values); revision &+= 1 }
    private func cacheKey(_ mid: Int) -> String { "piliplus.danmaku.rules.\(mid)" }
    private func persist() {
        guard let identity, identity.mid > 0, let data = try? JSONEncoder().encode(rules) else { return }
        defaults.set(data, forKey: cacheKey(identity.mid))
    }
}
