import SwiftUI

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
}

/// Shared by the real video surface and the deterministic visual regression fixture.
struct PiliGlassFullscreenControls: View {
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

    var body: some View {
        GeometryReader { geometry in
            let windowInsets = UIApplication.shared.playbackDetailForegroundKeyWindow?.safeAreaInsets ?? .zero
            ZStack {
                if !isLocked {
                    LinearGradient(colors: [.black.opacity(0.48), .clear, .black.opacity(0.48)],
                                   startPoint: .top, endPoint: .bottom)
                        .allowsHitTesting(false)

                    VStack(spacing: 0) {
                        header
                        Spacer(minLength: 12)
                        footer
                    }

                    transport
                        .offset(y: -8)
                } else {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            PiliGlassPlayerButton(symbol: "lock.open", title: "解锁播放控件") {
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
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 19, weight: .semibold)).lineLimit(1)
                Text(author).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    if let shareURL {
                        ShareLink(item: shareURL) {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 18))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .piliLiquidGlass(in: Circle(), overVideo: true, interactive: true)
                        .accessibilityLabel("分享视频")
                    }
                    HStack(spacing: 0) {
                        PiliGlassPlayerButton(symbol: "tv", title: "投屏", grouped: true, action: actions.cast)
                        Button(action: actions.settings) {
                            Image(systemName: "4k.tv").font(.system(size: 20)).frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain).accessibilityLabel("画质与播放设置")
                        PiliGlassPlayerButton(symbol: "slider.horizontal.3", title: "更多播放设置", grouped: true, action: actions.settings)
                    }
                    .piliLiquidGlass(in: Capsule(), overVideo: true, interactive: true)
                    PiliGlassPlayerButton(symbol: "xmark", title: "退出全屏", action: actions.close)
                        .accessibilityIdentifier("ui.player.fullscreen.toggle")
                }
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 28) {
            PiliGlassPlayerButton(symbol: "backward.end.fill", title: "上一集", grouped: true, action: actions.previous)
                .disabled(!hasPrevious).opacity(hasPrevious ? 1 : 0.3)
            PiliGlassPlayerButton(symbol: "gobackward.10", title: "后退 10 秒", size: 56) { actions.skip(-10) }
                .disabled(!canSeek).accessibilityIdentifier("ui.player.glass.backward")
            PiliGlassPlayerButton(symbol: isPlaying ? "pause.fill" : "play.fill", title: isPlaying ? "暂停" : "播放",
                                  size: 76, prominent: true) {
                if !isPlaying { PiliSleepTimer.shared.resumeManually() }
                playback.onTogglePlayback()
            }
            .accessibilityIdentifier("ui.player.glass.play")
            PiliGlassPlayerButton(symbol: "goforward.10", title: "前进 10 秒", size: 56) { actions.skip(10) }
                .disabled(!canSeek).accessibilityIdentifier("ui.player.glass.forward")
            PiliGlassPlayerButton(symbol: "forward.end.fill", title: "下一集", grouped: true, action: actions.next)
                .disabled(!hasNext).opacity(hasNext ? 1 : 0.3)
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    interactionAccessory
                    PiliGlassPlayerButton(symbol: "list.bullet", title: "播放列表", action: actions.queue)
                    Spacer(minLength: 12)
                    HStack(spacing: 0) {
                        PiliGlassPlayerButton(symbol: "timer", title: "定时停止与连播", grouped: true) { PiliPlaybackToolsView.present() }
                        PiliGlassPlayerButton(symbol: isDanmakuEnabled ? "text.bubble.fill" : "text.bubble",
                                              title: "弹幕设置", grouped: true, action: actions.danmaku)
                        PiliGlassPlayerButton(symbol: "captions.bubble", title: "字幕", grouped: true, action: actions.subtitles)
                    }
                    .piliLiquidGlass(in: Capsule(), overVideo: true, interactive: true)
                    PiliGlassPlayerButton(symbol: "lock", title: "锁定播放控件") {
                        isLocked = true
                        actions.interaction()
                    }
                    .accessibilityIdentifier("ui.player.glass.lock")
                }
            }
            PiliGlassProgressBar(clock: clock, canSeek: canSeek, actions: playback)
        }
    }
}

struct PiliGlassProgressBar: View {
    @ObservedObject var clock: PlayerPlaybackClock
    let canSeek: Bool
    let actions: PlayerNativePlaybackControlsActions

    var body: some View {
        HStack(spacing: 14) {
            Text(clock.displayCurrentTime < 1 ? "00:00" : BiliFormatters.duration(Int(clock.displayCurrentTime))).monospacedDigit()
            PlayerNativeProgressSlider(
                clock: clock, canSeek: canSeek, sliderVisualScale: 1, style: .liquidGlass,
                onScrubStart: actions.onScrubStart, onScrubChanged: actions.onScrubChanged,
                onScrubEnded: actions.onScrubEnded, onScrubCancelled: actions.onScrubCancelled
            )
            Text(BiliFormatters.duration(Int(clock.duration ?? 0))).monospacedDigit()
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 16)
        .frame(height: 44)
        .piliLiquidGlass(in: Capsule(), overVideo: true)
    }
}
