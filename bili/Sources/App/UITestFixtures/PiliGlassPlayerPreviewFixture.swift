import SwiftUI

/// Opt-in visual fixture. Uses the production controls without account or media requests.
struct PiliGlassPlayerPreviewFixture: View {
    @StateObject private var clock = PlayerPlaybackClock()
    @State private var playing = false
    @State private var locked = false
    @State private var message: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.04, green: 0.17, blue: 0.22), Color(red: 0.28, green: 0.2, blue: 0.27), .black],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(.orange.opacity(0.25)).frame(width: 240, height: 240).blur(radius: 65).offset(x: 180, y: -50)
            PiliGlassFullscreenControls(
                title: "在山海之间，遇见一场日落", author: "PiliPlus · 播放器预览",
                shareURL: URL(string: "https://github.com/SyIar/piliplus-re"), clock: clock,
                isPlaying: playing, canSeek: true, hasPrevious: false, hasNext: true,
                isDanmakuEnabled: true, isLocked: $locked,
                playback: .init(
                    onScrubStart: { clock.updateSeekPreview(progress: $0, force: true) },
                    onScrubChanged: { clock.updateSeekPreview(progress: $0, force: true) },
                    onScrubEnded: { clock.update(time: $0 * 768, duration: 768, force: true); clock.clearSeekPreview() },
                    onScrubCancelled: { clock.clearSeekPreview() }, onTogglePlayback: { playing.toggle() },
                    onToggleDanmaku: { message = "弹幕设置" }, onToggleFullscreen: { AppOrientationLock.restorePortrait() }
                ),
                actions: .init(close: { AppOrientationLock.restorePortrait() }, cast: { message = "投屏" }, settings: { message = "播放设置" },
                               subtitles: { message = "字幕" }, danmaku: { message = "弹幕" }, queue: { message = "播放列表" },
                               previous: {}, next: { clock.update(time: 0, duration: 768, force: true) },
                               skip: { clock.update(time: min(768, max(0, clock.currentTime + $0)), duration: 768, force: true) }, interaction: {}),
                interactionAccessory: AnyView(HStack(spacing: 0) {
                    PiliGlassPlayerButton(symbol: "hand.thumbsup", title: "点赞", grouped: true) { message = "点赞" }
                    PiliGlassPlayerButton(symbol: "bookmark", title: "收藏", grouped: true) { message = "收藏" }
                }.piliLiquidGlass(in: Capsule(), overVideo: true))
            )
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task {
            clock.update(time: 42, duration: 768, force: true)
            try? await Task.sleep(for: .milliseconds(500))
            AppOrientationLock.update(to: .landscapeRight, in: nil, requestsGeometryUpdate: true)
        }
        .alert("预览控件", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好") { message = nil }
        } message: { Text(message ?? "") }
    }
}
