import SwiftUI
import ChunUI

struct PlayerNativeControlButtonRow: View {
    let clock: PlayerPlaybackClock
    let metrics: PlayerNativeControlMetrics
    let layout: BiliPlayerControlLayout
    let isPlaying: Bool
    let isDanmakuEnabled: Bool
    let showsDanmakuButton: Bool
    let canToggleFullscreen: Bool
    let isFullscreenActive: Bool
    let controlsAccessory: AnyView?
    let controlsCenterAccessory: AnyView?
    let actions: PlayerNativePlaybackControlsActions

    var body: some View {
        ZStack {
            HStack(spacing: metrics.controlSpacing) {
                if layout.showsPlaybackToggle {
                    PlayerNativeGlassIconButton(
                        systemName: isPlaying ? "pause.fill" : "play.fill",
                        accessibilityLabel: isPlaying ? "\u{6682}\u{505c}" : "\u{64ad}\u{653e}",
                        metrics: metrics,
                        action: {
                            if !isPlaying { PiliSleepTimer.shared.resumeManually() }
                            actions.onTogglePlayback()
                        }
                    )
                }

                if layout.showsTimeLabel {
                    PlayerNativeTimeLabel(clock: clock, metrics: metrics)
                        .frame(
                            width: metrics.timeLabelWidth,
                            height: metrics.controlHeight
                        )

                }

                if layout.isLive, let controlsAccessory {
                    controlsAccessory
                        .frame(height: metrics.controlHeight)
                }

                Spacer(minLength: 0)

                if !layout.isLive, let controlsAccessory {
                    controlsAccessory
                        .frame(height: metrics.controlHeight)
                }

                if showsDanmakuButton {
                    PlayerNativeGlassIconButton(
                        systemName: danmakuControlSymbol,
                        accessibilityLabel: "\u{5f39}\u{5e55}\u{8bbe}\u{7f6e}",
                        accessibilityIdentifier: "ui.player.danmaku.toggle",
                        metrics: metrics,
                        action: actions.onToggleDanmaku
                    )
                }

                if canToggleFullscreen {
                    PlayerNativeGlassIconButton(
                        systemName: isFullscreenActive ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                        accessibilityLabel: isFullscreenActive ? "\u{9000}\u{51fa}\u{5168}\u{5c4f}" : "\u{5168}\u{5c4f}",
                        accessibilityIdentifier: "ui.player.fullscreen.toggle",
                        metrics: metrics,
                        action: actions.onToggleFullscreen
                    )
                }
            }


        }
        .frame(maxWidth: .infinity)
        .frame(height: metrics.controlHeight)
    }

    private var danmakuControlSymbol: String {
        layout.isLive
            ? "slider.horizontal.3"
            : (isDanmakuEnabled ? "text.bubble.fill" : "text.bubble")
    }
}
