import SwiftUI

struct MinePlaybackSettingsView: View {
    @AppStorage("piliplus.player.doubleTapSeek") private var doubleTapSeek = false
    @AppStorage("piliplus.player.swipeFullscreen") private var swipeFullscreen = true
    @AppStorage("piliplus.player.skipPGC") private var skipsPGC = false
    @AppStorage("piliplus.player.energy") private var showsEnergy = true
    @AppStorage("piliplus.player.autoFullscreen") private var autoFullscreen = false
    @AppStorage("piliplus.haptics.enabled") private var hapticsEnabled = true
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
            Section("播放与交互") {
                Toggle("自动跳过番剧片头片尾", isOn: $skipsPGC)
                Toggle("高能进度条", isOn: $showsEnergy)
                Toggle("开始播放后自动全屏", isOn: $autoFullscreen)
                Toggle("震动反馈", isOn: $hapticsEnabled)
                Toggle("两侧双击快退/快进 10 秒", isOn: $doubleTapSeek)
                Toggle("中部上滑全屏、下滑退出", isOn: $swipeFullscreen)
            }
            Section { NavigationLink { PiliSuperResolutionSettingsView() } label: { Label("超分辨率", systemImage: "sparkles.tv") } }
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
