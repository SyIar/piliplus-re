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
                }
                ZStack {
                    if !isLocked {
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
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).piliFont(.baseBold).lineLimit(1)
                Text(author).piliFont(.sm).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                moreMenu
                PiliGlassPlayerButton(symbol: "xmark", title: "退出全屏", grouped: true, action: actions.close)
                    .accessibilityIdentifier("ui.player.fullscreen.toggle")
            }
            .piliLiquidGlass(in: Capsule(), overVideo: true, interactive: true)
        }
    }

    private var moreMenu: some View {
        Menu {
            Section {
                // Native Text titles survive SwiftUI's conversion to UIMenu.
                Button("画质与播放设置", action: actions.settings)
                Button("投屏", action: actions.cast)
                Button("定时停止与连播") { PiliPlaybackToolsView.present() }
            }
            if let shareURL {
                ShareLink(item: shareURL) { Text("分享视频") }
            }
        } label: {
            PiliIcon(systemName: "ellipsis", size: 20)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("更多播放操作")
        .accessibilityIdentifier("ui.player.glass.more")
        .simultaneousGesture(TapGesture().onEnded { actions.interaction() })
    }

    private var transport: some View {
        HStack(spacing: 28) {
            PiliGlassPlayerButton(symbol: "backward.end.fill", title: "上一集", grouped: true, action: actions.previous)
                .disabled(!hasPrevious).opacity(hasPrevious ? 1 : 0)
                .accessibilityHidden(!hasPrevious)
            PiliGlassPlayerButton(symbol: "gobackward.10", title: "后退 10 秒", size: 56, grouped: true) { actions.skip(-10) }
                .disabled(!canSeek).accessibilityIdentifier("ui.player.glass.backward")
            PiliGlassPlayerButton(symbol: isPlaying ? "pause.fill" : "play.fill", title: isPlaying ? "暂停" : "播放",
                                  size: 64, prominent: true) {
                if !isPlaying { PiliSleepTimer.shared.resumeManually() }
                playback.onTogglePlayback()
            }
            .accessibilityIdentifier("ui.player.glass.play")
            PiliGlassPlayerButton(symbol: "goforward.10", title: "前进 10 秒", size: 56, grouped: true) { actions.skip(10) }
                .disabled(!canSeek).accessibilityIdentifier("ui.player.glass.forward")
            PiliGlassPlayerButton(symbol: "forward.end.fill", title: "下一集", grouped: true, action: actions.next)
                .disabled(!hasNext).opacity(hasNext ? 1 : 0)
                .accessibilityHidden(!hasNext)
        }
        .biliLiquidGlassForeground(shadowOpacity: 0.5)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                interactionAccessory
                PiliGlassPlayerButton(symbol: "list.bullet", title: "播放列表", grouped: true, action: actions.queue)
                Spacer(minLength: 12)
                PiliGlassPlayerButton(symbol: isDanmakuEnabled ? "text.bubble.fill" : "text.bubble",
                                      title: "弹幕设置", grouped: true, action: actions.danmaku)
                PiliGlassPlayerButton(symbol: "captions.bubble", title: "字幕", grouped: true, action: actions.subtitles)
                PiliGlassPlayerButton(symbol: "lock", title: "锁定播放控件", grouped: true) {
                    isLocked = true
                    actions.interaction()
                }
                .accessibilityIdentifier("ui.player.glass.lock")
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            PiliGlassProgressBar(clock: clock, canSeek: canSeek, actions: playback)
        }
        .piliLiquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), overVideo: true)
    }
}

struct PiliGlassProgressBar: View {
    @Environment(\.piliVideoTools) private var tools
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
        .piliFont(.sm)
        .padding(.horizontal, 16)
        .frame(height: 44)
        .overlay(alignment: .top) {
            if let tools { PiliEnergyStrip(store: tools).frame(height: 18).padding(.horizontal, 64).offset(y: -14).allowsHitTesting(false) }
        }
    }
}
