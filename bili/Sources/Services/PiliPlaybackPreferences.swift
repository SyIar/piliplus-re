import Combine
import Foundation
import PiliPlaybackCore

@MainActor
final class PiliPlaybackPreferences: ObservableObject {
    static let shared = PiliPlaybackPreferences()
    static let orderKey = "piliplus.playbackOrder"
    @Published private(set) var order: PlaybackOrder
    private var observer: AnyCancellable?

    private init() {
        order = Self.readOrder()
        observer = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            // Defaults notifications arrive on the writer's thread. Schedule
            // before entering the MainActor-isolated sink closure, not inside it.
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    let value = Self.readOrder()
                    if self?.order != value { self?.order = value }
                }
            }
    }
    func setOrder(_ value: PlaybackOrder) {
        order = value
        UserDefaults.standard.set(value.rawValue, forKey: Self.orderKey)
    }
    private static func readOrder() -> PlaybackOrder {
        if let value = UserDefaults.standard.string(forKey: orderKey), let order = PlaybackOrder(rawValue: value) { return order }
        switch UserDefaults.standard.string(forKey: "cc.bili.playback.videoListenPlaybackOrder.v1") {
        case "repeatCurrent": return .repeatOne
        case "stopAfterCurrent": return .stop
        default: return .sequential
        }
    }
}
