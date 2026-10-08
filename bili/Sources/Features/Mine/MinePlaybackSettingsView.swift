import SwiftUI

enum MinePlaybackSettingsCategory { case all, audioVideo, player }

struct MinePlaybackSettingsView: View {
    var category: MinePlaybackSettingsCategory = .all
    @AppStorage("piliplus.player.doubleTapSeek") private var doubleTapSeek = false
    @AppStorage("piliplus.player.pinchFullscreen") private var pinchFullscreen = true
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
        PiliForm {
            if category != .audioVideo {
            Section("\u{64ad}\u{653e}\u{4e0e}\u{4ea4}\u{4e92}") {
                PiliVideoAspectPicker()
                PiliFullscreenDirectionPicker()
                Toggle("\u{81ea}\u{52a8}\u{8df3}\u{8fc7}\u{756a}\u{5267}\u{7247}\u{5934}\u{7247}\u{5c3e}", isOn: $skipsPGC)
                Toggle("\u{9ad8}\u{80fd}\u{8fdb}\u{5ea6}\u{6761}", isOn: $showsEnergy)
                Toggle("\u{5f00}\u{59cb}\u{64ad}\u{653e}\u{540e}\u{81ea}\u{52a8}\u{5168}\u{5c4f}", isOn: $autoFullscreen)
                Toggle("\u{9707}\u{52a8}\u{53cd}\u{9988}", isOn: $hapticsEnabled)
                Toggle("\u{4e24}\u{4fa7}\u{53cc}\u{51fb}\u{5feb}\u{9000}/\u{5feb}\u{8fdb} 10 \u{79d2}", isOn: $doubleTapSeek)
                Toggle("\u{4e2d}\u{90e8}\u{4e0a}\u{6ed1}\u{5168}\u{5c4f}、\u{4e0b}\u{6ed1}\u{9000}\u{51fa}", isOn: $swipeFullscreen)
                Toggle("\u{53cc}\u{6307}\u{634f}\u{5408}\u{9000}\u{51fa}\u{5168}\u{5c4f}", isOn: $pinchFullscreen)
            }
            }
            if category != .player {
            Section { NavigationLink { PiliSuperResolutionSettingsView() } label: { PiliLabel("\u{8d85}\u{5206}\u{8fa8}\u{7387}", systemImage: "sparkles.tv") } }
            Section { NavigationLink { PiliLivePlaybackSettingsView(libraryStore: libraryStore) } label: { Text("\u{76f4}\u{64ad}\u{97f3}\u{89c6}\u{9891}") } }
            }
            MinePlaybackPreferenceSection(
                category: category,
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

            if category != .audioVideo {
            MinePlaybackToolsSection(libraryStore: libraryStore)
            Section {
                Toggle("\u{9501}\u{5b9a}\u{63a7}\u{4ef6}\u{65f6}\u{56fa}\u{5b9a}\u{5c4f}\u{5e55}\u{65b9}\u{5411}", isOn: $locksOrientation)
            } footer: {
                Text("\u{5168}\u{5c4f}\u{64ad}\u{653e}\u{5668}\u{70b9}\u{51fb}\u{9501}\u{5b9a}\u{540e}，\u{540c}\u{65f6}\u{56fa}\u{5b9a}\u{5f53}\u{524d}\u{6a2a}\u{5c4f}\u{65b9}\u{5411}；\u{89e3}\u{9501}\u{6216}\u{9000}\u{51fa}\u{64ad}\u{653e}\u{65f6}\u{6062}\u{590d}\u{81ea}\u{52a8}\u{65cb}\u{8f6c}。")
            }
            }
        }
        .tint(libraryStore.appTintColor)
        .formStyle(.grouped)
        .nativeTopScrollEdgeEffect()
        .navigationTitle(category == .audioVideo ? "\u{97f3}\u{89c6}\u{9891}\u{8bbe}\u{7f6e}" : "\u{64ad}\u{653e}\u{5668}\u{8bbe}\u{7f6e}")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard category != .player else { return }
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
