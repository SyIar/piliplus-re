import UIKit
import SwiftUI
import ChunUI

struct PiliGlassFullscreenActions {
    let close: () -> Void
    let cast: () -> Void
    let settings: () -> Void
    let subtitles: () -> Void
    let danmaku: () -> Void
    let queue: () -> Void
    let previous: () -> Void
    let next: () -> Void
    let skip: (Double) -> Void
    let interaction: () -> Void
    var rateChanged: (BiliPlaybackRate) -> Void = { _ in }
    var capture: (() -> Void)? = nil
    var menuPresentationChanged: (Bool) -> Void = { _ in }
}

/// Shared by the real video surface and the deterministic visual regression fixture.
struct PiliGlassFullscreenControls: View {
    @State private var showsMoreActions = false
    @State private var pendingMoreAction: (() -> Void)?
    let title: String
    let author: String
    let shareURL: URL?
    let clock: PlayerPlaybackClock
    let isPlaying: Bool
    let canSeek: Bool
    let hasPrevious: Bool
    let hasNext: Bool
    let isDanmakuEnabled: Bool
    @Binding var isLocked: Bool
    let playback: PlayerNativePlaybackControlsActions
    let actions: PiliGlassFullscreenActions
    let interactionAccessory: AnyView
    var playbackRate: BiliPlaybackRate = .x10

    var body: some View {
        GeometryReader { geometry in
            let windowInsets = UIApplication.shared.playbackDetailForegroundKeyWindow?.safeAreaInsets ?? .zero
            ZStack {
                if !isLocked {
                    LinearGradient(colors: [.black.opacity(0.48), .clear, .black.opacity(0.48)],
                                   startPoint: .top, endPoint: .bottom)
                        .allowsHitTesting(false)
                }
                ZStack {
                    if !isLocked {
                        VStack(spacing: 0) {
                            header
                            Spacer(minLength: 12)
                            footer
                        }

                        HStack {
                            lockControl
                            Spacer()
                            if let capture = actions.capture {
                                PiliGlassPlayerButton(symbol: "camera", title: "\u{622a}\u{56fe}", action: capture)
                            }
                        }
                    } else {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                PiliGlassPlayerButton(symbol: "lock.open", title: "\u{89e3}\u{9501}\u{64ad}\u{653e}\u{63a7}\u{4ef6}") {
                                    isLocked = false
                                    actions.interaction()
                                }
                                .accessibilityIdentifier("ui.player.glass.unlock")
                            }
                        }
                    }
                }
                .padding(.horizontal, max(20, max(max(geometry.safeAreaInsets.leading, geometry.safeAreaInsets.trailing), max(windowInsets.left, windowInsets.right))))
                .padding(.top, max(16, geometry.safeAreaInsets.top))
                .padding(.bottom, max(14, geometry.safeAreaInsets.bottom))
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .piliSheet(isPresented: $showsMoreActions, onDismiss: {
            actions.menuPresentationChanged(false)
            let action = pendingMoreAction
            pendingMoreAction = nil
            action?()
        }) {
            NavigationStack {
                PiliList {
                    interactionAccessory
                    Button("\u{540e}\u{9000} 10 \u{79d2}") { selectMoreAction { actions.skip(-10) } }
                        .disabled(!canSeek)
                        .accessibilityIdentifier("ui.player.glass.backward")
                    Button("\u{524d}\u{8fdb} 10 \u{79d2}") { selectMoreAction { actions.skip(10) } }
                        .disabled(!canSeek)
                        .accessibilityIdentifier("ui.player.glass.forward")
                    Button("\u{64ad}\u{653e}\u{5217}\u{8868}", action: { selectMoreAction(actions.queue) })
                    Button("\u{4e0a}\u{4e00}\u{96c6}", action: { selectMoreAction(actions.previous) }).disabled(!hasPrevious)
                    Button("\u{4e0b}\u{4e00}\u{96c6}", action: { selectMoreAction(actions.next) }).disabled(!hasNext)
                    Button("\u{753b}\u{8d28}\u{4e0e}\u{64ad}\u{653e}\u{8bbe}\u{7f6e}") { selectMoreAction(actions.settings) }
                    Button("\u{6295}\u{5c4f}") { selectMoreAction(actions.cast) }
                    Button("\u{5b9a}\u{65f6}\u{505c}\u{6b62}\u{4e0e}\u{8fde}\u{64ad}") { selectMoreAction { PiliPlaybackToolsView.present() } }
                    if let shareURL {
                        ShareLink(item: shareURL) { Text("\u{5206}\u{4eab}\u{89c6}\u{9891}") }
                    }
                }
                .navigationTitle("\u{66f4}\u{591a}\u{64ad}\u{653e}\u{64cd}\u{4f5c}")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("\u{5b8c}\u{6210}") { showsMoreActions = false }
                    }
                }
            }
            .piliPresentationDetents([.medium, .large])
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            PiliGlassPlayerButton(symbol: "chevron.left", title: "\u{9000}\u{51fa}\u{5168}\u{5c4f}", action: actions.close)
            Text(title).font(.headline).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                PiliGlassPlayerButton(symbol: "airplayvideo", title: "\u{6295}\u{5c4f}", grouped: true, action: actions.cast)
                PiliGlassPlayerButton(symbol: isDanmakuEnabled ? "text.bubble.fill" : "text.bubble",
                                      title: "\u{5f39}\u{5e55}\u{8bbe}\u{7f6e}", grouped: true, action: actions.danmaku)
                moreMenu
            }
            .piliLiquidGlass(in: Capsule(), overVideo: true, interactive: true)
        }
    }

    private var moreMenu: some View {
        Button {
            actions.menuPresentationChanged(true)
            showsMoreActions = true
        } label: {
            PiliIcon(systemName: "ellipsis", size: 20)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\u{66f4}\u{591a}\u{64ad}\u{653e}\u{64cd}\u{4f5c}")
        .accessibilityIdentifier("ui.player.glass.more")
    }

    private func selectMoreAction(_ action: @escaping () -> Void) {
        // Finish dismissing this sheet before presenting the requested panel.
        pendingMoreAction = action
        showsMoreActions = false
    }

    private var lockControl: some View {
        PiliGlassPlayerButton(symbol: "lock", title: "\u{9501}\u{5b9a}\u{64ad}\u{653e}\u{63a7}\u{4ef6}") {
            isLocked = true
            actions.interaction()
        }
        .accessibilityIdentifier("ui.player.glass.lock")
    }

    private var footer: some View {
        VStack(spacing: 0) {
            PlayerNativeProgressSlider(
                clock: clock, canSeek: canSeek, sliderVisualScale: 1, style: .telegram,
                onScrubStart: playback.onScrubStart, onScrubChanged: playback.onScrubChanged,
                onScrubEnded: playback.onScrubEnded, onScrubCancelled: playback.onScrubCancelled
            )
            .frame(height: 32)
            HStack(spacing: 8) {
                PiliGlassPlayerButton(symbol: isPlaying ? "pause.fill" : "play.fill",
                                      title: isPlaying ? "\u{6682}\u{505c}" : "\u{64ad}\u{653e}", grouped: true) {
                    if !isPlaying { PiliSleepTimer.shared.resumeManually() }
                    playback.onTogglePlayback()
                }
                .accessibilityIdentifier("ui.player.glass.play")
                PlayerNativeTimeLabel(clock: clock, metrics: .landscape)
                Spacer(minLength: 8)
                PiliGlassPlayerButton(symbol: "captions.bubble", title: "\u{5b57}\u{5e55}", grouped: true, action: actions.subtitles)
                PlayerPlaybackRateMenu(rate: playbackRate, onSelect: actions.rateChanged)
                PiliGlassPlayerButton(symbol: "gearshape", title: "\u{753b}\u{8d28}\u{4e0e}\u{64ad}\u{653e}\u{8bbe}\u{7f6e}", grouped: true, action: actions.settings)
                PiliGlassPlayerButton(symbol: "arrow.down.right.and.arrow.up.left", title: "\u{9000}\u{51fa}\u{5168}\u{5c4f}",
                                      grouped: true, action: actions.close)
                    .accessibilityIdentifier("ui.player.fullscreen.toggle")
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .piliLiquidGlass(in: RoundedRectangle(cornerRadius: 16), overVideo: true)
    }

}

struct PiliGlassProgressBar: View {
    @Environment(\.piliVideoTools) private var tools
    @ObservedObject var clock: PlayerPlaybackClock
    let canSeek: Bool
    let actions: PlayerNativePlaybackControlsActions

    var body: some View {
        HStack(spacing: 14) {
            Text(clock.displayCurrentTime < 1 ? "00:00" : BiliFormatters.duration(PlaybackNumericValue.integer(clock.displayCurrentTime))).monospacedDigit()
            PlayerNativeProgressSlider(
                clock: clock, canSeek: canSeek, sliderVisualScale: 1, style: .liquidGlass,
                onScrubStart: actions.onScrubStart, onScrubChanged: actions.onScrubChanged,
                onScrubEnded: actions.onScrubEnded, onScrubCancelled: actions.onScrubCancelled
            )
            Text(BiliFormatters.duration(PlaybackNumericValue.integer(clock.duration ?? 0))).monospacedDigit()
        }
        .piliFont(.sm)
        .padding(.horizontal, 16)
        .frame(height: 44)
        .overlay(alignment: .top) {
            if let tools { PiliEnergyStrip(store: tools).frame(height: 18).padding(.horizontal, 64).offset(y: -14).allowsHitTesting(false) }
        }
    }
}
