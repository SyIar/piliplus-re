import ActivityKit
import UIKit

/// Keeps a single playback activity; the system Now Playing card owns controls.
@MainActor
final class PlaybackLiveActivity {
    static let shared = PlaybackLiveActivity()
    private var activityID: String?
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
        if let activityID {
            lastState = state
            let previousUpdate = updateTask
            updateTask = Task {
                await previousUpdate?.value
                guard !Task.isCancelled else { return }
                await Self.updateActivity(id: activityID, state: state)
            }
        } else if player.isPlaying, UIApplication.shared.applicationState == .active {
            do {
                let activity = try Activity.request(
                    attributes: PlaybackActivityAttributes(sessionID: UUID().uuidString),
                    content: ActivityContent(state: state, staleDate: .now.addingTimeInterval(60)), pushType: nil
                )
                activityID = activity.id
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
        if let activityID {
            Task {
                await previousUpdate?.value
                await Self.endActivity(id: activityID)
            }
        }
        activityID = nil
        playerID = nil
        lastState = nil
    }

    func clearOrphanedActivities() {
        let activityIDs = Activity<PlaybackActivityAttributes>.activities.map(\.id)
        Task {
            for id in activityIDs { await Self.endActivity(id: id) }
        }
    }

    // ActivityKit objects are not Sendable. Resolve each handle in the async
    // operation that owns it; only IDs and immutable value snapshots cross actors.
    nonisolated private static func updateActivity(
        id: String, state: PlaybackActivityAttributes.ContentState
    ) async {
        guard let activity = Activity<PlaybackActivityAttributes>.activities.first(where: { $0.id == id }),
              activity.activityState == .active || activity.activityState == .stale else { return }
        await activity.update(ActivityContent(state: state, staleDate: .now.addingTimeInterval(60)))
    }

    nonisolated private static func endActivity(id: String) async {
        guard let activity = Activity<PlaybackActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
    }
}
