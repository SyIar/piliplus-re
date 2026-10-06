import SwiftUI

struct MinePlaybackSettingsView: View {
    @ObservedObject var libraryStore: LibraryStore
    @AppStorage("piliplus.player.lockOrientation") private var locksOrientation = true
    @AppStorage("cc.bili.playback.showsAdvancedSettings.v1") var showsAdvancedPlaybackSettings = false
    @State var isProbingPlaybackCDN = false
    @State var playbackCDNProbeResults: [PlaybackCDNProbeResult] = []
    @State var playbackCDNProbeMessage: String?
    @State var playbackCDNProbeTask: Task<Void, Never>?
    @State var isShowingPlaybackCDNProbeDetails = false
    @State var playbackURLPreferenceSnapshots: [PlaybackURLPreferenceSnapshot] = []
    @State var isShowingPlaybackURLPreferenceDetails = false
    @State var playbackCustomCDNHostDraft = ""

    var body: some View {
        Form {
            Section { NavigationLink("超分辨率", systemImage: "sparkles.tv") { PiliSuperResolutionSettingsView() } }
            MinePlaybackPreferenceSection(
                libraryStore: libraryStore,
                playbackPreferenceSummary: AnyView(playbackPreferenceSummary),
                playbackCDNProbeRefreshIntervalTitle: playbackCDNProbeRefreshIntervalTitle,
                isProbingPlaybackCDN: isProbingPlaybackCDN,
                playbackCDNProbeMessage: playbackCDNProbeMessage,
                probePlaybackCDN: probePlaybackCDN,
                showsAdvancedPlaybackSettings: $showsAdvancedPlaybackSettings,
                playbackCustomCDNHostDraft: $playbackCustomCDNHostDraft,
                commitPlaybackCustomCDNHost: commitPlaybackCustomCDNHost
            ) {
                playbackCDNProbeSummary
                playbackURLPreferenceSummary
            }

            MinePlaybackToolsSection(libraryStore: libraryStore)
            Section {
                Toggle("锁定控件时固定屏幕方向", isOn: $locksOrientation)
            } footer: {
                Text("全屏播放器点击锁定后，同时固定当前横屏方向；解锁或退出播放时恢复自动旋转。")
            }
        }
        .tint(libraryStore.appTintColor)
        .formStyle(.grouped)
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
        .task {
            playbackCustomCDNHostDraft = libraryStore.playbackCustomCDNHost ?? ""
            refreshPlaybackURLPreferenceSnapshots()
            refreshPlaybackCDNProbeIfNeeded()
        }
        .onChange(of: libraryStore.playbackCustomCDNHost) { _, host in
            playbackCustomCDNHostDraft = host ?? ""
        }
        .onDisappear {
            playbackCDNProbeTask?.cancel()
            playbackCDNProbeTask = nil
            isProbingPlaybackCDN = false
        }
    }

}

extension MinePlaybackSettingsView {
    func commitPlaybackCustomCDNHost() {
        let trimmedHost = playbackCustomCDNHostDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            playbackCustomCDNHostDraft = ""
            libraryStore.setPlaybackCustomCDNHost(nil)
            return
        }
        guard let normalizedHost = PlaybackCDNPreference.normalizedCustomHost(trimmedHost) else {
            return
        }
        playbackCustomCDNHostDraft = normalizedHost
        libraryStore.setPlaybackCustomCDNHost(normalizedHost)
        libraryStore.setPlaybackCDNPreference(.custom)
    }
}
