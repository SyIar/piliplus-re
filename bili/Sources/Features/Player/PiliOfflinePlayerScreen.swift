import ChunUI
import PiliPlaybackCore
import SwiftUI

struct PiliOfflinePlayerScreen: View {
    @StateObject private var model: PiliOfflinePlaybackModel
    @EnvironmentObject private var libraryStore: LibraryStore
    @StateObject private var subtitles = PiliSubtitleController()
    @State private var danmaku: [DanmakuItem] = []
    @State private var unfilteredDanmaku: [DanmakuItem] = []
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var showsDanmaku = true

    init(item: OfflineDownloadItem, url: URL) {
        _model = StateObject(wrappedValue: PiliOfflinePlaybackModel(item: item, url: url))
    }
    var body: some View {
        VStack(spacing: 16) {
            if model.item.effectiveMediaKind == .audio {
                PiliOfflineAudioControls(player: model.player, title: model.item.title, author: model.item.author).id(model.item.id)
                PiliOfflineSubtitleLayer(controller: subtitles, player: model.player)
                    .frame(height: 110)
            } else {
            BiliPlayerView(viewModel: model.player, duration: model.item.duration,
                           surfaceOverlay: AnyView(ZStack {
                               PiliOfflineDanmakuOverlay(player: model.player, items: danmaku,
                                                         isEnabled: showsDanmaku, settings: libraryStore.danmakuSettings)
                               PiliOfflineSubtitleLayer(controller: subtitles, player: model.player)
                           }),
                           isDanmakuEnabled: showsDanmaku,
                           onToggleDanmaku: { showsDanmaku.toggle() })
                .id(model.item.id)
            CCNeoButton("投屏", variant: .ghost, icon: "screen-check") {
                PiliPresentation.present(.sheet) { PiliDLNAView(source: { try .offline(model) }) }
            }
            PiliIconButton("截图与动图", systemImage: "camera") {
                if let file = try? PiliOfflineStorage.playbackURL(model.item) {
                    PiliPresentation.present(.sheet) {
                        PiliMediaCaptureView(source: file, time: model.player.currentTime, duration: model.item.duration)
                    }
                }
            }
            }
            CCNeoButton("字幕", variant: .ghost, icon: PikaIcon.Name.fileText) {
                PiliSubtitleSettingsView.present(controller: subtitles) { seconds in model.player.seek(by: seconds - model.player.currentTime) }
            }
            if let message = model.message { Text(message).ccText(font: .cc.sm, color: .cc.mutedForeground) }
            HStack {
                CCNeoButton("上一条", variant: .ghost, icon: PikaIcon.Name.arrowLeft) { model.navigate(-1) }
                Spacer()
                CCNeoButton("下一条", variant: .ghost, icon: PikaIcon.Name.arrowRight) { model.navigate(1) }
            }.padding(.horizontal, 20)
        }
        .navigationTitle(model.item.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: model.item.id) {
            let id = model.item.id
            let isAudio = model.item.effectiveMediaKind == .audio
            if isAudio { model.player.play() }
            let values = await Task.detached(priority: .utility) { isAudio ? [] : PiliOfflineDanmaku.load(id) }.value
            guard !Task.isCancelled, model.item.id == id else { return }
            unfilteredDanmaku = values
            applyRules()
            let cached = await Task.detached(priority: .utility) { PiliCachedSubtitle.load(id) }.value
            guard !Task.isCancelled, model.item.id == id else { return }
            subtitles.loadOffline(cached)
        }
        .onAppear { PiliSleepTimer.shared.resumeManually() }
        .onReceive(PiliDanmakuRulesStore.shared.$revision) { _ in applyRules() }
        .onDisappear { model.leave() }
    }
    private func applyRules() {
        danmaku = PiliDanmakuRulesStore.shared.filter(unfilteredDanmaku, identity: PiliAccountIdentity(dependencies.api.requestSnapshot()))
    }
}

struct PiliOfflineAudioControls: View {
    @ObservedObject var player: PlayerStateViewModel
    @ObservedObject var clock: PlayerPlaybackClock
    let title: String
    let author: String
    @State private var isScrubbing = false
    @State private var scrubTime = 0.0
    init(player: PlayerStateViewModel, title: String, author: String) {
        self.player = player; self.clock = player.playbackClock; self.title = title; self.author = author
    }
    private var duration: Double {
        let value = clock.duration ?? 0
        return value.isFinite && value > 0 ? value : 1
    }
    var body: some View {
        VStack(spacing: 24) {
            PiliIcon(systemName: "music.note", size: 68)
                .font(.cc.lg).foregroundStyle(.tint)
                .frame(width: 180, height: 180).piliGlassCard(radius: 36)
                .accessibilityHidden(true)
            Text(title).font(.cc.baseBold.bold()).multilineTextAlignment(.center)
            Text(author).font(.cc.base).foregroundStyle(.secondary)
            if let error = player.errorMessage { Text(error).font(.cc.sm).foregroundStyle(.secondary) }
            VStack {
                Slider(value: Binding(get: { isScrubbing ? scrubTime : min(duration, max(0, clock.currentTime)) },
                                      set: { scrubTime = $0 }), in: 0...duration) { editing in
                    if editing { scrubTime = min(duration, max(0, clock.currentTime)) }
                    isScrubbing = editing
                    if !editing { player.seek(to: scrubTime / duration) }
                }.accessibilityLabel("音频播放进度")
                HStack {
                    Text(time(isScrubbing ? scrubTime : clock.currentTime))
                    Spacer()
                    Text(time(duration))
                }.font(.cc.sm.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 32) {
                Button { player.seek(by: -10) } label: { PiliIcon(systemName: "gobackward.10") }
                    .accessibilityLabel("后退十秒")
                Button { player.isPlaying ? player.pause() : player.play() } label: {
                    PiliIcon(systemName: player.isPlaying ? "pause.fill" : "play.fill").frame(width: 48, height: 48)
                }.buttonStyle(.glassProminent).accessibilityLabel(player.isPlaying ? "暂停音频" : "播放音频")
                Button { player.seek(by: 10) } label: { PiliIcon(systemName: "goforward.10") }
                    .accessibilityLabel("前进十秒")
            }.font(.cc.lgBold)
        }.padding(24)
    }
    private func time(_ seconds: Double) -> String {
        let value = Int(max(0, seconds.isFinite ? seconds : 0))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

private struct PiliOfflineDanmakuOverlay: View {
    @AppStorage("piliplus.danmaku.separateFullscreenFont") private var separateFullscreenFont = false
    @AppStorage("piliplus.danmaku.fullscreenFontScale") private var fullscreenFontScale = 1.0
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @ObservedObject var player: PlayerStateViewModel
    let items: [DanmakuItem]
    let isEnabled: Bool
    let settings: DanmakuSettings
    var body: some View {
        DanmakuOverlayView(items: items, itemsRevision: items.count, isPlaying: player.isPlaying,
                           playbackRate: player.playbackRate.rawValue, isEnabled: isEnabled,
                           hasPresentedPlayback: player.hasPresentedPlayback, settings: settings.usingFullscreenFont(fullscreenFontScale, enabled: separateFullscreenFont, isFullscreen: verticalSizeClass == .compact),
                           topInset: 48, bottomInset: 72, playbackClock: player.playbackClock)
            .allowsHitTesting(false)
    }
}
