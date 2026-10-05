import Combine
import Foundation
import PiliPlaybackCore

@MainActor
final class PiliOfflinePlaybackModel: ObservableObject {
    @Published private(set) var item: OfflineDownloadItem
    @Published private(set) var player: PlayerStateViewModel
    @Published private(set) var message: String?

    init(item: OfflineDownloadItem, url: URL) {
        self.item = item
        player = Self.makePlayer(item, url: url, resume: true)
        bindEnd()
    }

    func leave() {
        PiliOfflineStore.shared.savePlaybackPosition(item.id, time: player.currentTime)
        player.stop()
    }
    func navigate(_ offset: Int) {
        let queue = playbackQueue
        guard let index = queue.firstIndex(where: { $0.id == item.id }), queue.indices.contains(index + offset) else { return }
        PiliSleepTimer.shared.resumeManually()
        open(queue[index + offset])
    }

    private func bindEnd() {
        let activePlayer = player
        let position = playbackQueue.firstIndex { $0.id == item.id }
        player.setTrackNavigationAvailability(hasPrevious: (position ?? 0) > 0,
                                              hasNext: position.map { $0 + 1 < playbackQueue.count } ?? false)
        player.onNextTrackRequested = { [weak self, weak activePlayer] in
            guard let self, self.player === activePlayer else { return }; self.navigate(1)
        }
        player.onPreviousTrackRequested = { [weak self, weak activePlayer] in
            guard let self, self.player === activePlayer else { return }; self.navigate(-1)
        }
        player.onPlaybackEnded = { [weak self, weak activePlayer] in
            guard let self, self.player === activePlayer else { return }
            let queue = self.playbackQueue
            let order = PiliPlaybackPreferences.shared.order
            let action = PlaybackEndPolicy.resolve(order: order, currentIndex: queue.firstIndex { $0.id == self.item.id },
                                                  count: queue.count, sleepTimerStops: PiliSleepTimer.shared.shouldStopAtPlaybackEnd())
            switch action {
            case .stop, .loadRelated: self.player.pause()
            case .replay: self.player.seek(to: 0); self.player.play()
            case let .advance(index): self.open(queue[index])
            }
        }
    }
    private var playbackQueue: [OfflineDownloadItem] {
        PiliOfflineStore.shared.items.filter { $0.state == .completed && $0.effectiveMediaKind == item.effectiveMediaKind }
    }
    private func open(_ next: OfflineDownloadItem) {
        do {
            let url = try PiliOfflineStorage.playbackURL(next)
            PiliOfflineStore.shared.savePlaybackPosition(item.id, time: player.currentTime)
            player.stop()
            item = next
            player = Self.makePlayer(next, url: url, resume: false)
            message = nil
            bindEnd()
        } catch { message = error.localizedDescription }
    }
    private static func makePlayer(_ item: OfflineDownloadItem, url: URL, resume: Bool) -> PlayerStateViewModel {
        PlayerStateViewModel(videoURL: item.effectiveMediaKind == .video ? url : nil,
                             audioURL: item.effectiveMediaKind == .audio ? url : nil, title: item.title, authorName: item.author,
                             referer: "", durationHint: item.duration > 0 ? item.duration : nil,
                             resumeTime: resume ? item.lastPlaybackTime : 0, startupResumePolicy: .immediate,
                             dynamicRange: BiliVideoDynamicRange(rawValue: item.dynamicRange) ?? .sdr,
                             metricsID: "offline-\(item.id.uuidString)", httpHeaders: [:],
                             playbackContentMode: item.effectiveMediaKind == .audio ? .audioOnly : .video)
    }
}
