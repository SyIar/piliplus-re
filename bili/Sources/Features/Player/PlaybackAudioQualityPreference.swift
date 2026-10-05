import Foundation

nonisolated enum PlaybackAudioQualityPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case compatible, best
    static let storageKey = "piliplus.audio.quality"
    static let cellularStorageKey = "piliplus.audio.cellularQuality"
    var id: Self { self }
    var title: String { self == .best ? "最佳可用音质" : "兼容优先（AAC）" }
    static func stored(in defaults: UserDefaults = .standard, network: PlaybackEnvironment.NetworkClass = PlaybackEnvironment.current.networkClass) -> Self {
        let key = network == .cellular || network == .constrained ? cellularStorageKey : storageKey
        return Self(rawValue: defaults.string(forKey: key) ?? "") ?? .compatible
    }
}
