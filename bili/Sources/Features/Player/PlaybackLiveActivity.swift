import ActivityKit
import UIKit

/// Keeps a single playback activity; the system Now Playing card owns controls.
@MainActor
final class PlaybackLiveActivity {
    static let shared = PlaybackLiveActivity()
    private var activity: Activity<PlaybackActivityAttributes>?
    private var playerID: ObjectIdentifier?
    private var lastState: PlaybackActivityAttributes.ContentState?
    private var updateTask: Task<Void, Never>?

    func update(player: PlayerStateViewModel) {
        // Unit-test and visual-fixture players must never create system activities.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              !ProcessInfo.processInfo.arguments.contains("--ui-test-fixture"),
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let identifier = ObjectIdentifier(player)
        if playerID != identifier { end(); playerID = identifier }
        let state = PlaybackActivityAttributes.ContentState(
            title: player.title, author: player.nowPlayingArtist, isPlaying: player.isPlaying,
            elapsed: PlaybackNumericValue.seconds(player.currentTime) ?? 0,
            duration: PlaybackNumericValue.seconds(player.displayDuration) ?? 0,
            rate: player.playbackRate.rawValue, updatedAt: .now
        )
        if let lastState,
           lastState.title == state.title, lastState.author == state.author,
           lastState.isPlaying == state.isPlaying, lastState.rate == state.rate,
           lastState.duration == state.duration,
           abs(state.elapsed - lastState.elapsed) < 5,
           state.updatedAt.timeIntervalSince(lastState.updatedAt) < 15 { return }
        let content = ActivityContent(state: state, staleDate: .now.addingTimeInterval(60))
        if let activity, activity.activityState == .active || activity.activityState == .stale {
            lastState = state
            let previousUpdate = updateTask
            updateTask = Task {
                await previousUpdate?.value
                guard !Task.isCancelled else { return }
                await activity.update(content)
            }
        } else if activity == nil, player.isPlaying, UIApplication.shared.applicationState == .active {
            do {
                activity = try Activity.request(
                    attributes: PlaybackActivityAttributes(sessionID: UUID().uuidString),
                    content: content, pushType: nil
                )
                lastState = state
            } catch {
                // Activity authorization is optional; audio and Now Playing remain available.
                lastState = state
            }
        }
    }

    func end() {
        let previousUpdate = updateTask
        updateTask?.cancel()
        updateTask = nil
        if let activity {
            Task {
                await previousUpdate?.value
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        activity = nil
        playerID = nil
        lastState = nil
    }

    func clearOrphanedActivities() {
        for activity in Activity<PlaybackActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
