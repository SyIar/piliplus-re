import SwiftUI
import ChunUI

struct MinePlaybackPreferenceSection<ProbeSummary: View>: View {
    var category: MinePlaybackSettingsCategory = .all
    @ObservedObject var libraryStore: LibraryStore
    @State private var av1HardwareDecodeProbe = PlaybackCodecPolicy.av1HardwareDecodeProbe
    @State private var isShowingAV1HardwareDecodeResult = false
    let playbackPreferenceSummary: AnyView
    let playbackCDNProbeRefreshIntervalTitle: String
    let isProbingPlaybackCDN: Bool
    let playbackCDNProbeMessage: String?
    let probePlaybackCDN: () -> Void
    @Binding var showsAdvancedPlaybackSettings: Bool
    @Binding var playbackCustomCDNHostDraft: String
    let commitPlaybackCustomCDNHost: () -> Void
    @ViewBuilder let probeSummary: () -> ProbeSummary

    var body: some View {
        Section {
            if category != .audioVideo {
                videoDetailAutoplayToggle
                pictureInPictureToggle
                playbackHistorySyncThresholdPicker
                defaultPlaybackRatePicker
            }
            if category != .player {
            playbackPreferenceSummary
            playbackAutoOptimizationPicker
            preferredVideoQualityPicker
            cellularPreferredVideoQualityPicker
            PiliSettingPicker("\u{9ed8}\u{8ba4}\u{97f3}\u{8d28}", selection: Binding(get: { libraryStore.audioQualityPreference }, set: { libraryStore.setAudioQualityPreference($0) })) {
                ForEach(PlaybackAudioQualityPreference.allCases) { Text($0.title).tag($0) }
            }
            PiliSettingPicker("\u{8702}\u{7a9d}\u{7f51}\u{7edc}\u{97f3}\u{8d28}", selection: Binding(get: { libraryStore.cellularAudioQualityPreference }, set: { libraryStore.setAudioQualityPreference($0, cellular: true) })) {
                ForEach(PlaybackAudioQualityPreference.allCases) { Text($0.title).tag($0) }
            }
            Text("\u{6700}\u{4f73}\u{97f3}\u{8d28}\u{6309}\u{53ef}\u{7528}\u{97f3}\u{8f68}\u{9009}\u{62e9}\u{65e0}\u{635f}、\u{675c}\u{6bd4}\u{6216} AAC；\u{64ad}\u{653e}\u{5931}\u{8d25}\u{65f6}\u{56de}\u{9000}\u{5230}\u{517c}\u{5bb9}\u{97f3}\u{8f68}。\u{9700}\u{8981}\u{5bf9}\u{5e94}\u{5185}\u{5bb9}\u{548c}\u{8d26}\u{53f7}\u{6743}\u{9650}，\u{542c}\u{89c6}\u{9891}\u{624b}\u{52a8}\u{9009}\u{62e9}\u{7684}\u{97f3}\u{8f68}\u{4f18}\u{5148}。").piliFont(.sm).foregroundStyle(.secondary)
            av1HardwareDecodeProbeButton
            videoCodecPreferenceLink
            forceHardwareDecodeToggle
            dolbyVisionRenderingPolicyPicker
            }
        } header: {
            Text("\u{64ad}\u{653e}\u{4f53}\u{9a8c}")
        } footer: {
            if category != .audioVideo {
            Text("\u{5173}\u{95ed}\u{8be6}\u{60c5}\u{81ea}\u{52a8}\u{64ad}\u{653e}\u{540e}，\u{8fdb}\u{5165}\u{89c6}\u{9891}\u{8be6}\u{60c5}\u{9875}\u{4f1a}\u{5148}\u{505c}\u{5728}\u{9996}\u{5e27}，\u{9700}\u{624b}\u{52a8}\u{70b9}\u{64ad}\u{653e}。\u{64ad}\u{653e}\u{6ee1} \(libraryStore.playbackHistorySyncThresholdSeconds) \u{79d2}\u{540e}\u{540c}\u{6b65}\u{89c2}\u{770b}\u{8bb0}\u{5f55}\u{5e76}\u{7528}\u{4e8e}\u{4e0b}\u{6b21}\u{7eed}\u{64ad}；\u{672a}\u{6ee1}\u{4e0d}\u{4f1a}\u{4e0a}\u{62a5}。")
            }
        }

        if category != .player {
        Section {
            advancedPlaybackSettingsToggle
            if showsAdvancedPlaybackSettings {
                playbackStreamSourcePicker
                playbackCDNPicker
                cellularBiliTrafficCompatibilityExperimentToggle
                prefersBackupAudioURLToggle
                playbackCustomCDNHostEditor
                playbackCDNProbeRefreshPolicyPicker
                playbackCDNProbeRefreshPolicyDetail
                playbackNetworkAddressFamilyPicker
                playbackNetworkAddressFamilyNotice
                playbackCDNProbeButton
                playbackCDNProbeMessageText
                probeSummary()
            } else {
                advancedPlaybackSummary
            }
        } header: {
            Text("\u{9ad8}\u{7ea7}\u{64ad}\u{653e}\u{8bbe}\u{7f6e}")
        } footer: {
            Text(showsAdvancedPlaybackSettings ? "\u{9ad8}\u{7ea7}\u{9009}\u{9879}\u{4f1a}\u{5f71}\u{54cd}\u{64ad}\u{653e}\u{7ebf}\u{8def}、\u{53d6}\u{6d41}\u{6765}\u{6e90}\u{548c}\u{8bca}\u{65ad}\u{4fe1}\u{606f}；\u{4e0d}\u{786e}\u{5b9a}\u{65f6}\u{4fdd}\u{6301}\u{81ea}\u{52a8}\u{5373}\u{53ef}。" : "\u{9047}\u{5230}\u{5730}\u{533a}\u{7f51}\u{7edc}\u{5f02}\u{5e38}\u{6216}\u{9700}\u{8981}\u{8bca}\u{65ad}\u{65f6}\u{518d}\u{6253}\u{5f00}。")
        }
        }
    }

    private var advancedPlaybackSettingsToggle: some View {
        Toggle(isOn: $showsAdvancedPlaybackSettings) {
            MineSettingsLabel("\u{663e}\u{793a}\u{9ad8}\u{7ea7}\u{9009}\u{9879}", systemImage: "slider.horizontal.3")
        }
        .animation(.easeInOut(duration: 0.2), value: showsAdvancedPlaybackSettings)
    }

    private var advancedPlaybackSummary: some View {
        HStack(spacing: 8) {
            MineSettingsLabel("\u{5f53}\u{524d}\u{7ebf}\u{8def}", systemImage: "network")
            Spacer(minLength: 8)
            Text(advancedPlaybackSummaryText)
                .piliFont(.sm)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }

    private var advancedPlaybackSummaryText: String {
        let cdnTitle = libraryStore.playbackCDNPreference == .automatic
            ? "\u{667a}\u{80fd}\u{9009}\u{62e9}"
            : libraryStore.playbackCDNPreference.title
        let networkTitle = libraryStore.playbackNetworkAddressFamilyPreference == .automatic
            ? "\u{81ea}\u{52a8}\u{7f51}\u{7edc}"
            : libraryStore.playbackNetworkAddressFamilyPreference.title
        let compatibilityTitle = libraryStore.cellularBiliTrafficCompatibilityExperimentEnabled
            ? "B\u{7ad9}\u{57df}\u{540d}\u{4f18}\u{5148}"
            : "\u{5e38}\u{89c4}\u{7ebf}\u{8def}"
        return "\(cdnTitle) · \(networkTitle) · \(compatibilityTitle)"
    }

    private var playbackAutoOptimizationPicker: some View {
        PiliSettingPicker(selection: Binding(
            get: { libraryStore.playbackAutoOptimizationMode },
            set: { libraryStore.setPlaybackAutoOptimizationMode($0) }
        )) {
            ForEach(PlaybackAutoOptimizationMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        } label: {
            MineSettingsLabel("\u{667a}\u{80fd}\u{64ad}\u{653e}\u{52a0}\u{901f}", systemImage: "wand.and.stars")
        }
        .pickerStyle(.menu)
    }

    private var pictureInPictureToggle: some View {
        Toggle(isOn: Binding(
            get: { libraryStore.pictureInPictureEnabled },
            set: { libraryStore.setPictureInPictureEnabled($0) }
        )) {
            MineSettingsLabel("\u{753b}\u{4e2d}\u{753b}\u{64ad}\u{653e}", systemImage: "pip")
        }
    }

    private var videoDetailAutoplayToggle: some View {
        Toggle(isOn: Binding(
            get: { libraryStore.videoDetailAutoplayEnabled },
            set: { libraryStore.setVideoDetailAutoplayEnabled($0) }
        )) {
            MineSettingsLabel("\u{8fdb}\u{5165}\u{8be6}\u{60c5}\u{81ea}\u{52a8}\u{64ad}\u{653e}", systemImage: "play.circle")
        }
    }

    private var playbackHistorySyncThresholdPicker: some View {
        PiliSettingPicker(selection: Binding<Int>(
            get: { libraryStore.playbackHistorySyncThresholdSeconds },
            set: { libraryStore.setPlaybackHistorySyncThresholdSeconds($0) }
        )) {
            ForEach(LibraryStore.supportedPlaybackHistorySyncThresholdSeconds, id: \.self) { seconds in
                Text("\(seconds) \u{79d2}").tag(seconds)
            }
        } label: {
            MineSettingsLabel("\u{5386}\u{53f2}\u{540c}\u{6b65}\u{95e8}\u{69db}", systemImage: "clock.arrow.circlepath")
        }
        .pickerStyle(.menu)
    }

    private var preferredVideoQualityPicker: some View {
        PiliSettingPicker(selection: Binding<Int>(
            get: { libraryStore.preferredVideoQuality ?? 0 },
            set: { libraryStore.setPreferredVideoQuality($0 == 0 ? nil : $0) }
        )) {
            Text(LibraryStore.videoQualityTitle(nil)).tag(0)
            ForEach(LibraryStore.supportedVideoQualities, id: \.self) { quality in
                Text(LibraryStore.videoQualityTitle(quality)).tag(quality)
            }
        } label: {
            MineSettingsLabel("\u{9ed8}\u{8ba4}\u{753b}\u{8d28}", systemImage: "play.rectangle")
        }
        .pickerStyle(.menu)
    }

    private var cellularPreferredVideoQualityPicker: some View {
        PiliSettingPicker(selection: Binding<Int>(
            get: { libraryStore.cellularPreferredVideoQuality ?? 0 },
            set: { libraryStore.setCellularPreferredVideoQuality($0 == 0 ? nil : $0) }
        )) {
            Text(LibraryStore.videoQualityTitle(nil)).tag(0)
            ForEach(LibraryStore.supportedVideoQualities, id: \.self) { quality in
                Text(LibraryStore.videoQualityTitle(quality)).tag(quality)
            }
        } label: {
            MineSettingsLabel("\u{8702}\u{7a9d}\u{7f51}\u{7edc}\u{753b}\u{8d28}", systemImage: "antenna.radiowaves.left.and.right")
        }
        .pickerStyle(.menu)
    }

    private var videoCodecPreferenceLink: some View {
        NavigationLink {
            VideoCodecSelectionSettingsView(libraryStore: libraryStore)
        } label: {
            LabeledContent {
                Text(libraryStore.videoCodecPreference.title)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            } label: {
                MineSettingsLabel("\u{89c6}\u{9891}\u{7f16}\u{7801}", systemImage: "film.stack")
            }
        }
    }

    private var av1HardwareDecodeProbeButton: some View {
        Button {
            av1HardwareDecodeProbe = PlaybackCodecPolicy.av1HardwareDecodeProbe
            isShowingAV1HardwareDecodeResult = true
        } label: {
            HStack(spacing: 8) {
                MineSettingsLabel("\u{68c0}\u{6d4b} AV1 \u{786c}\u{89e3}", systemImage: "cpu")
                Spacer(minLength: 8)
                Text(av1HardwareDecodeProbe.settingsStatusTitle)
                    .foregroundStyle(.secondary)
            }
        }
        .piliAlert("AV1 \u{786c}\u{89e3}\u{68c0}\u{6d4b}", isPresented: $isShowingAV1HardwareDecodeResult) {
            PiliAlertButton("\u{597d}", role: .cancel) {}
        } message: { av1HardwareDecodeProbe.detail }
    }

    private var forceHardwareDecodeToggle: some View {
        Toggle(isOn: Binding(
            get: { libraryStore.forceHardwareDecodeEnabled },
            set: { libraryStore.setForceHardwareDecodeEnabled($0) }
        )) {
            MineSettingsLabel("\u{786c}\u{89e3}\u{4f18}\u{5148}", systemImage: "cpu")
        }
    }

    private var dolbyVisionRenderingPolicyPicker: some View {
        PiliSettingPicker(selection: Binding(
            get: { libraryStore.dolbyVisionRenderingPolicy },
            set: { libraryStore.setDolbyVisionRenderingPolicy($0) }
        )) {
            ForEach(DolbyVisionRenderingPolicy.allCases) { policy in
                Text(policy.title).tag(policy)
            }
        } label: {
            MineSettingsLabel("\u{675c}\u{6bd4}\u{89c6}\u{754c}\u{6e32}\u{67d3}", systemImage: "sparkles.tv")
        }
        .pickerStyle(.menu)
    }

    private var playbackStreamSourcePicker: some View {
        PiliSettingPicker(selection: Binding(
            get: { libraryStore.playbackStreamSourcePreference },
            set: { libraryStore.setPlaybackStreamSourcePreference($0) }
        )) {
            ForEach(PlaybackStreamSourcePreference.allCases) { source in
                Text(source.title).tag(source)
            }
        } label: {
            MineSettingsLabel("\u{64ad}\u{653e}\u{6765}\u{6e90}", systemImage: "antenna.radiowaves.left.and.right")
        }
        .pickerStyle(.menu)
    }

    private var cellularBiliTrafficCompatibilityExperimentToggle: some View {
        Toggle(isOn: Binding(
            get: { libraryStore.cellularBiliTrafficCompatibilityExperimentEnabled },
            set: { libraryStore.setCellularBiliTrafficCompatibilityExperimentEnabled($0) }
        )) {
            VStack(alignment: .leading, spacing: 3) {
                MineSettingsLabel("\u{5b9a}\u{5411}\u{6d41}\u{91cf}\u{517c}\u{5bb9}（\u{5b9e}\u{9a8c}）", systemImage: "antenna.radiowaves.left.and.right")
                Text("\u{8702}\u{7a9d}\u{7f51}\u{7edc}\u{4f18}\u{5148}\u{4f7f}\u{7528} B \u{7ad9}\u{7ebf}\u{8def}；\u{5931}\u{8d25}\u{65f6}\u{4ecd}\u{53ef}\u{80fd}\u{6d88}\u{8017}\u{666e}\u{901a}\u{6d41}\u{91cf}。")
                    .piliFont(.sm)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var playbackCDNPicker: some View {
        PiliSettingPicker(selection: Binding(
            get: { libraryStore.playbackCDNPreference },
            set: { libraryStore.setPlaybackCDNPreference($0) }
        )) {
            ForEach(PlaybackCDNPreference.allCases) { preference in
                Text(preference.title).tag(preference)
            }
        } label: {
            MineSettingsLabel("CDN \u{7ebf}\u{8def}", systemImage: "network")
        }
        .pickerStyle(.menu)
    }

    private var prefersBackupAudioURLToggle: some View {
        Toggle(isOn: Binding(
            get: { libraryStore.prefersBackupAudioURL },
            set: { libraryStore.setPrefersBackupAudioURL($0) }
        )) {
            MineSettingsLabel("\u{4f18}\u{5148}\u{5907}\u{7528}\u{97f3}\u{9891}\u{7ebf}\u{8def}", systemImage: "speaker.wave.2")
        }
    }

    @ViewBuilder
    private var playbackCustomCDNHostEditor: some View {
        if libraryStore.playbackCDNPreference == .custom {
            TextField(
                "upos-sz-mirrorali.bilivideo.com",
                text: $playbackCustomCDNHostDraft
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .onSubmit(commitPlaybackCustomCDNHost)

            if let normalizedCustomCDNHost {
                LabeledContent("\u{81ea}\u{5b9a}\u{4e49} Host", value: normalizedCustomCDNHost)
                    .piliFont(.sm)
                    .foregroundStyle(.secondary)
            } else if !playbackCustomCDNHostDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                MineSettingsLabel("Host \u{683c}\u{5f0f}\u{65e0}\u{6548}", systemImage: "exclamationmark.triangle")
                    .piliFont(.sm)
                    .foregroundStyle(Color.cc.warning)
            }

            Button(action: commitPlaybackCustomCDNHost) {
                Text("\u{5e94}\u{7528}\u{7ebf}\u{8def}").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .disabled(isCustomCDNHostDraftInvalid)
        }
    }

    private var normalizedCustomCDNHost: String? {
        PlaybackCDNPreference.normalizedCustomHost(playbackCustomCDNHostDraft)
    }

    private var isCustomCDNHostDraftInvalid: Bool {
        let trimmedHost = playbackCustomCDNHostDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedHost.isEmpty && normalizedCustomCDNHost == nil
    }

    private var playbackCDNProbeRefreshPolicyPicker: some View {
        PiliSettingPicker(selection: Binding(
            get: { libraryStore.playbackCDNProbeRefreshPolicy },
            set: { libraryStore.setPlaybackCDNProbeRefreshPolicy($0) }
        )) {
            ForEach(PlaybackCDNProbeRefreshPolicy.allCases) { policy in
                Text(policy.title).tag(policy)
            }
        } label: {
            MineSettingsLabel("CDN \u{81ea}\u{52a8}\u{6d4b}\u{901f}", systemImage: "arrow.triangle.2.circlepath")
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private var playbackCDNProbeRefreshPolicyDetail: some View {
        if libraryStore.playbackCDNProbeRefreshPolicy == .interval {
            Stepper(
                value: Binding(
                    get: { libraryStore.playbackCDNProbeRefreshIntervalMinutes },
                    set: { libraryStore.setPlaybackCDNProbeRefreshIntervalMinutes($0) }
                ),
                in: LibraryStore.playbackCDNProbeRefreshIntervalRange,
                step: 15
            ) {
                MineSettingsLabel(
                    "\u{6d4b}\u{901f}\u{95f4}\u{9694} \(playbackCDNProbeRefreshIntervalTitle)",
                    systemImage: "timer"
                )
            }
        } else {
            MineSettingsLabel("\u{542f}\u{52a8}\u{6216}\u{8fd4}\u{56de} App \u{65f6}\u{66f4}\u{65b0}\u{7ebf}\u{8def}\u{53c2}\u{8003}；\u{5b9e}\u{9645}\u{64ad}\u{653e}\u{7ed3}\u{679c}\u{4f18}\u{5148}。", systemImage: "bolt.horizontal")
                .piliFont(.sm)
                .foregroundStyle(.secondary)
        }
    }

    private var playbackNetworkAddressFamilyPicker: some View {
        PiliSettingPicker(selection: Binding(
            get: { libraryStore.playbackNetworkAddressFamilyPreference },
            set: { libraryStore.setPlaybackNetworkAddressFamilyPreference($0) }
        )) {
            ForEach(PlaybackNetworkAddressFamilyPreference.allCases) { preference in
                Text(preference.title).tag(preference)
            }
        } label: {
            MineSettingsLabel("\u{7f51}\u{7edc}\u{534f}\u{8bae}", systemImage: "point.3.connected.trianglepath.dotted")
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private var playbackNetworkAddressFamilyNotice: some View {
        if libraryStore.playbackNetworkAddressFamilyPreference != .automatic,
           libraryStore.playbackCDNProbeSnapshotForCurrentContext == nil {
            MineSettingsLabel("\u{534f}\u{8bae}\u{5df2}\u{5207}\u{6362}，\u{8bf7}\u{91cd}\u{65b0}\u{6d4b}\u{901f}。", systemImage: "arrow.triangle.2.circlepath")
                .piliFont(.sm)
                .foregroundStyle(Color.cc.warning)
        }
    }

    private var playbackCDNProbeButton: some View {
        Button(action: probePlaybackCDN) {
            Text(isProbingPlaybackCDN ? "\u{6d4b}\u{901f}\u{4e2d}" : "\u{7acb}\u{5373}\u{6d4b}\u{901f}").frame(maxWidth: .infinity, alignment: .trailing)
        }
        .disabled(isProbingPlaybackCDN)
    }

    @ViewBuilder
    private var playbackCDNProbeMessageText: some View {
        if let playbackCDNProbeMessage {
            Text(playbackCDNProbeMessage)
                .piliFont(.sm)
                .foregroundStyle(.secondary)
        }
    }

    private var defaultPlaybackRatePicker: some View {
        PiliSettingPicker(selection: Binding(
            get: { libraryStore.defaultPlaybackRate },
            set: { libraryStore.setDefaultPlaybackRate($0) }
        )) {
            ForEach(BiliPlaybackRate.allCases) { rate in
                Text(rate.title).tag(rate.rawValue)
            }
        } label: {
            MineSettingsLabel("\u{9ed8}\u{8ba4}\u{500d}\u{901f}", systemImage: "speedometer")
        }
        .pickerStyle(.menu)
    }
}
