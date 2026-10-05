import ChunUI
import PiliPlaybackCore
import SwiftUI

struct PiliOfflinePlayerScreen: View {
    @StateObject private var model: PiliOfflinePlaybackModel
    @EnvironmentObject private var libraryStore: LibraryStore
    @StateObject private var subtitles = PiliSubtitleController()
    @State private var danmaku: [DanmakuItem] = []
    @State private var showsDanmaku = true

    init(item: OfflineDownloadItem, url: URL) {
        _model = StateObject(wrappedValue: PiliOfflinePlaybackModel(item: item, url: url))
    }
    var body: some View {
        VStack(spacing: 16) {
            BiliPlayerView(viewModel: model.player, duration: model.item.duration,
                           surfaceOverlay: AnyView(ZStack {
                               PiliOfflineDanmakuOverlay(player: model.player, items: danmaku,
                                                         isEnabled: showsDanmaku, settings: libraryStore.danmakuSettings)
                               PiliSubtitleOverlay(controller: subtitles, clock: model.player.playbackClock)
                           }),
                           isDanmakuEnabled: showsDanmaku,
                           onToggleDanmaku: { showsDanmaku.toggle() })
                .id(model.item.id)
            CCNeoButton("字幕", variant: .ghost, icon: PikaIcon.Name.fileText) {
                PiliSubtitleSettingsView.present(controller: subtitles) { model.player.seek(to: $0) }
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
            let values = await Task.detached(priority: .utility) { PiliOfflineDanmaku.load(id) }.value
            guard !Task.isCancelled, model.item.id == id else { return }
            danmaku = values
            let cached = await Task.detached(priority: .utility) { PiliCachedSubtitle.load(id) }.value
            guard !Task.isCancelled, model.item.id == id else { return }
            subtitles.loadOffline(cached)
        }
        .onAppear { PiliSleepTimer.shared.resumeManually() }
        .onDisappear { model.leave() }
    }
}

private struct PiliOfflineDanmakuOverlay: View {
    @ObservedObject var player: PlayerStateViewModel
    let items: [DanmakuItem]
    let isEnabled: Bool
    let settings: DanmakuSettings
    var body: some View {
        DanmakuOverlayView(items: items, itemsRevision: items.count, isPlaying: player.isPlaying,
                           playbackRate: player.playbackRate.rawValue, isEnabled: isEnabled,
                           hasPresentedPlayback: player.hasPresentedPlayback, settings: settings,
                           topInset: 48, bottomInset: 72, playbackClock: player.playbackClock)
            .allowsHitTesting(false)
    }
}
