import Combine
import Foundation
import Security

nonisolated enum PiliSponsorMode: String, CaseIterable, Identifiable, Sendable {
    case automatic, manual, disabled
    var id: String { rawValue }
    var title: String { switch self { case .automatic: "自动"; case .manual: "手动"; case .disabled: "忽略" } }
}
nonisolated enum PiliSponsorCategory: String, CaseIterable, Identifiable, Sendable {
    case sponsor, selfpromo, exclusive_access, interaction, poi_highlight, intro, outro, preview, padding, filler, music_offtopic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sponsor: "赞助广告"; case .selfpromo: "自我推广"; case .exclusive_access: "独家访问/抢先体验"
        case .interaction: "互动提醒"; case .poi_highlight: "精彩时刻"; case .intro: "开场"; case .outro: "片尾"
        case .preview: "预览"; case .padding: "填充内容"; case .filler: "离题"; case .music_offtopic: "非音乐部分"
        }
    }
    var actions: [String] {
        switch self {
        case .exclusive_access: ["full"]
        case .poi_highlight: ["poi"]
        case .padding, .music_offtopic: ["skip"]
        case .sponsor, .selfpromo: ["skip", "mute", "full"]
        default: ["skip", "mute"]
        }
    }
}

@MainActor
final class PiliSponsorPreferences: ObservableObject {
    static let shared = PiliSponsorPreferences()
    @Published private(set) var modes: [String: PiliSponsorMode] = [:] {
        didSet { automaticCategories = Set(modes.filter { $0.value == .automatic }.map(\.key)) }
    }
    private(set) var automaticCategories = Set<String>()
    init() { reload() }
    func reload() { modes = Dictionary(uniqueKeysWithValues: PiliSponsorCategory.allCases.map { ($0.rawValue, PiliSponsorMode(rawValue: UserDefaults.standard.string(forKey: "piliplus.sponsor.\($0.rawValue)") ?? "automatic") ?? .automatic) }) }
    func mode(_ category: String) -> PiliSponsorMode { modes[category] ?? .manual }
    func set(_ mode: PiliSponsorMode, category: String) { modes[category] = mode; UserDefaults.standard.set(mode.rawValue, forKey: "piliplus.sponsor.\(category)") }
}

nonisolated enum PiliSponsorRules {
    static func shouldMute(at time: Double, segments: [SponsorBlockSegment], automaticCategories: Set<String>, ignoredIDs: Set<String> = [], manualIDs: Set<String> = []) -> Bool {
        guard time.isFinite else { return false }
        return segments.contains { $0.actionType == "mute" && !ignoredIDs.contains($0.id)
            && (automaticCategories.contains($0.category) || manualIDs.contains($0.id))
            && time >= $0.startTime && time < $0.endTime }
    }
}

/// The community identifier authorizes edits and votes; keep it out of settings backups.
nonisolated enum PiliSponsorIdentity {
    static func readOrCreate() throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "io.github.syiar.PiliPlusSwift.SponsorBlock", kSecAttrAccount as String: "userID"]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query.merging([kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]) { _, new in new } as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8), !value.isEmpty { return value }
        guard status == errSecItemNotFound else { throw PiliOfflineError.message("无法读取空降社区身份（\(status)）") }
        let id = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "")
        let added = SecItemAdd(query.merging([kSecValueData as String: Data(id.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]) { _, new in new } as CFDictionary, nil)
        guard added == errSecSuccess else { throw PiliOfflineError.message("无法保存空降社区身份（\(added)）") }; return id
    }
}
