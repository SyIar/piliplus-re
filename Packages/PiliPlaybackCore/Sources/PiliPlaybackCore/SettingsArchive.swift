import Foundation

public struct SettingsArchive: Codable, Sendable {
    public let format: String
    public let version: Int
    public let createdAt: Date
    public let values: [String: Data]
    public init(values: [String: Data], createdAt: Date = Date()) {
        self.format = "PiliPlusSwift.Settings"; self.version = 1; self.createdAt = createdAt
        self.values = values.filter { Self.allows($0.key) }
    }
    public static func allows(_ key: String) -> Bool {
        let lower = key.lowercased()
        let forbidden = ["password", "cookie", "sessdata", "csrf", "token", "credential", "keychain", "fallback", "session", "accesskey"]
        guard !forbidden.contains(where: lower.contains) else { return false }
        if key.hasPrefix("piliplus.subtitle.") { return true }
        if ["piliplus.playbackOrder", "piliplus.offline.cellular", "piliplus.player.lockOrientation", "piliplus.audio.quality", "piliplus.audio.cellularQuality"].contains(key) { return true }
        let prefixes = ["cc.bili.appearance.", "cc.bili.playback.", "cc.bili.content.", "cc.bili.videoDetail.",
                        "cc.bili.privacy.", "cc.bili.home.", "cc.bili.display.", "cc.bili.image.", "cc.bili.search.",
                        "cc.bili.experimental.", "cc.bili.danmaku.", "cc.bili.sponsorBlock."]
        guard prefixes.contains(where: key.hasPrefix) else { return false }
        return !["progressbybvid", "snapshot", "cache", "migration", "queue", "historylist"].contains(where: lower.contains)
    }
    public static func capture(_ preferences: [String: Any]) throws -> Self {
        var values: [String: Data] = [:]
        for (key, value) in preferences where allows(key) {
            values[key] = try PropertyListSerialization.data(fromPropertyList: ["value": value], format: .binary, options: 0)
        }
        return Self(values: values)
    }
    /// Decode every value before modifying any preference; a malformed archive has no partial effects.
    public func decodedValues() throws -> [String: Any] {
        guard format == "PiliPlusSwift.Settings", version == 1, values.count <= 5000 else { throw ArchiveError.invalidFormat }
        var result: [String: Any] = [:]
        for (key, data) in values {
            guard Self.allows(key), data.count <= 2 * 1024 * 1024,
                  let object = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let value = object["value"] else { throw ArchiveError.invalidValue }
            result[key] = value
        }
        return result
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 10 * 1024 * 1024 else { throw ArchiveError.tooLarge }
        let archive = try JSONDecoder().decode(Self.self, from: data)
        _ = try archive.decodedValues()
        return archive
    }
    public enum ArchiveError: LocalizedError {
        case invalidFormat, invalidValue, tooLarge
        public var errorDescription: String? {
            switch self {
            case .invalidFormat: "不是受支持的 PiliPlus Swift 设置备份"
            case .invalidValue: "备份包含无效设置或不允许恢复的凭据"
            case .tooLarge: "设置备份超过 10 MB"
            }
        }
    }
}
