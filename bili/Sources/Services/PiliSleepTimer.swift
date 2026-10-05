import Combine
import Foundation
import PiliPlaybackCore
import UIKit

@MainActor
final class PiliSleepTimer: ObservableObject {
    static let shared = PiliSleepTimer()
    private static let storageKey = "piliplus.sleepTimer.v1"
    @Published private(set) var policy = SleepTimerPolicy()
    @Published private(set) var now = Date()
    private var ticker: AnyCancellable?
    private var foregroundObserver: AnyCancellable?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let restored = try? JSONDecoder().decode(SleepTimerPolicy.self, from: data) {
            policy = restored
        }
        foregroundObserver = NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.checkDeadline() }
            }
        updateTicker()
        checkDeadline()
    }

    var summary: String {
        switch policy.state {
        case .off: "未设置"
        case .waitingForEnd: "播完当前视频后停止"
        case .stopped: "已到时间，播放已停止"
        case let .scheduled(deadline, finishCurrent):
            "\(max(0, Int(ceil(deadline.timeIntervalSince(now) / 60)))) 分钟后\(finishCurrent ? "播完当前视频再停" : "停止")"
        }
    }

    func schedule(minutes: Int, finishCurrent: Bool) {
        guard (1...1440).contains(minutes) else { return }
        policy.schedule(deadline: Date().addingTimeInterval(Double(minutes) * 60), finishCurrent: finishCurrent)
        now = Date()
        persist()
        updateTicker()
    }

    func stopAfterCurrent() {
        policy.stopAfterCurrent()
        checkDeadline()
        persist()
        updateTicker()
    }

    func cancel() {
        policy.cancel()
        persist()
        updateTicker()
    }

    /// Called on explicit transport-button play, not on automatic next-item loading.
    func resumeManually() {
        if policy.preventsAutomaticPlayback { cancel() }
    }

    func shouldStopAtPlaybackEnd() -> Bool {
        let shouldStop = policy.playbackEnded(now: Date())
        persist()
        updateTicker()
        return shouldStop
    }

    func checkDeadline() {
        now = Date()
        let active = ActivePlaybackCoordinator.shared.currentActivePlayer()
        let before = policy
        if policy.tick(now: now, hasActiveItem: active != nil) {
            active?.pause()
        }
        if before != policy {
            persist()
            updateTicker()
        }
    }

    private func updateTicker() {
        ticker?.cancel()
        ticker = nil
        guard case .scheduled = policy.state else { return }
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in self?.checkDeadline() }
            }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(policy) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
