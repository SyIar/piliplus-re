import SwiftUI

struct VideoDetailDanmakuOverlay: View {
    @AppStorage("piliplus.danmaku.separateFullscreenFont") private var separateFullscreenFont = false
    @AppStorage("piliplus.danmaku.fullscreenFontScale") private var fullscreenFontScale = 1.0

    let store: VideoDetailDanmakuRenderStore
    let playerViewModel: PlayerStateViewModel
    let clock: PlayerPlaybackClock
    let usesLandscapePlaybackChrome: Bool
    let isLayoutTransitioning: Bool
    let onPlaybackTime: (TimeInterval, Bool) -> Void
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var selected: DanmakuItem?
    @State private var resumesAfterSelection = false
    @StateObject private var state = VideoDetailDanmakuOverlayState()

    var body: some View {
        let snapshot = state.snapshot
        let isVisibleInCurrentOrientation = usesLandscapePlaybackChrome || !snapshot.settings.hidesInPortrait

        DanmakuOverlayView(
            items: snapshot.items,
            itemsRevision: snapshot.itemsRevision,
            currentTime: clock.currentTime,
            isPlaying: snapshot.isPlaying,
            playbackRate: snapshot.playbackRate,
            isEnabled: snapshot.isEnabled && isVisibleInCurrentOrientation,
            hasPresentedPlayback: snapshot.hasPresentedPlayback,
            isLoadShedding: snapshot.isLoadShedding,
            settings: snapshot.settings.usingFullscreenFont(fullscreenFontScale, enabled: separateFullscreenFont, isFullscreen: usesLandscapePlaybackChrome),
            topInset: usesLandscapePlaybackChrome ? 28 : 8,
            bottomInset: usesLandscapePlaybackChrome ? 84 : 54,
            isLayoutTransitioning: isLayoutTransitioning,
            playbackClock: clock,
            onPlaybackTime: onPlaybackTime,
            onSelect: { item in
                resumesAfterSelection = playerViewModel.isPlaying
                playerViewModel.pause()
                selected = item
            }
        )
        .padding(.horizontal, usesLandscapePlaybackChrome ? 0 : 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .sheet(item: $selected, onDismiss: {
            if resumesAfterSelection, ActivePlaybackCoordinator.shared.isActive(playerViewModel), !playerViewModel.isTerminated { playerViewModel.play() }
            resumesAfterSelection = false
        }) { item in PiliDanmakuActionsView(api: dependencies.api, item: item) }
        .videoDetailDanmakuOverlayLifecycle(
            store: store,
            playerViewModel: playerViewModel,
            clock: clock,
            isEnabled: snapshot.isEnabled,
            state: state,
            onPlaybackTime: onPlaybackTime
        )
    }
}
