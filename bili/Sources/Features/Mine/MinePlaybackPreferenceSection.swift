import SwiftUI
import ChunUI

struct MinePlaybackPreferenceSection<ProbeSummary: View>: View {
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
            playbackPreferenceSummary
            playbackAutoOptimizationPicker
            videoDetailAutoplayToggle
            pictureInPictureToggle
            playbackHistorySyncThresholdPicker
            preferredVideoQualityPicker
            cellularPreferredVideoQualityPicker
            PiliSettingPicker("默认音质", selection: Binding(get: { libraryStore.audioQualityPreference }, set: { libraryStore.setAudioQualityPreference($0) })) {
                ForEach(PlaybackAudioQualityPreference.allCases) { Text($0.title).tag($0) }
            }
            PiliSettingPicker("蜂窝网络音质", selection: Binding(get: { libraryStore.cellularAudioQualityPreference }, set: { libraryStore.setAudioQualityPreference($0, cellular: true) })) {
                ForEach(PlaybackAudioQualityPreference.allCases) { Text($0.title).tag($0) }
            }
            Text("最佳音质按可用音轨选择无损、杜比或 AAC；播放失败时回退到兼容音轨。需要对应内容和账号权限，听视频手动选择的音轨优先。").piliFont(.sm).foregroundStyle(.secondary)
            av1HardwareDecodeProbeButton
            videoCodecPreferenceLink
            forceHardwareDecodeToggle
            dolbyVisionRenderingPolicyPicker
            defaultPlaybackRatePicker
        } header: {
            Text("播放体验")
        } footer: {
            Text("关闭详情自动播放后，进入视频详情页会先停在首帧，需手动点播放。播放满 \(libraryStore.playbackHistorySyncThresholdSeconds) 秒后同步观看记录并用于下次续播；未满不会上报。")
        }

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
            Text("高级播放设置")
        } footer: {
            Text(showsAdvancedPlaybackSettings ? "高级选项会影响播放线路、取流来源和诊断信息；不确定时保持自动即可。" : "遇到地区网络异常或需要诊断时再打开。")
        }
    }

    private var advancedPlaybackSettingsToggle: some View {
        Toggle(isOn: $showsAdvancedPlaybackSettings) {
            MineSettingsLabel("显示高级选项", systemImage: "slider.horizontal.3")
        }
        .animation(.easeInOut(duration: 0.2), value: showsAdvancedPlaybackSettings)
    }

    private var advancedPlaybackSummary: some View {
        HStack(spacing: 8) {
            MineSettingsLabel("当前线路", systemImage: "network")
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
            ? "智能选择"
            : libraryStore.playbackCDNPreference.title
        let networkTitle = libraryStore.playbackNetworkAddressFamilyPreference == .automatic
            ? "自动网络"
            : libraryStore.playbackNetworkAddressFamilyPreference.title
        let compatibilityTitle = libraryStore.cellularBiliTrafficCompatibilityExperimentEnabled
            ? "B站域名优先"
            : "常规线路"
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
            MineSettingsLabel("智能播放加速", systemImage: "wand.and.stars")
        }
        .pickerStyle(.menu)
    }

    private var pictureInPictureToggle: some View {
        Toggle(isOn: Binding(
            get: { libraryStore.pictureInPictureEnabled },
            set: { libraryStore.setPictureInPictureEnabled($0) }
        )) {
            MineSettingsLabel("画中画播放", systemImage: "pip")
        }
    }

    private var videoDetailAutoplayToggle: some View {
        Toggle(isOn: Binding(
            get: { libraryStore.videoDetailAutoplayEnabled },
            set: { libraryStore.setVideoDetailAutoplayEnabled($0) }
        )) {
            MineSettingsLabel("进入详情自动播放", systemImage: "play.circle")
        }
    }

    private var playbackHistorySyncThresholdPicker: some View {
        PiliSettingPicker(selection: Binding<Int>(
            get: { libraryStore.playbackHistorySyncThresholdSeconds },
            set: { libraryStore.setPlaybackHistorySyncThresholdSeconds($0) }
        )) {
            ForEach(LibraryStore.supportedPlaybackHistorySyncThresholdSeconds, id: \.self) { seconds in
                Text("\(seconds) 秒").tag(seconds)
            }
        } label: {
            MineSettingsLabel("历史同步门槛", systemImage: "clock.arrow.circlepath")
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
            MineSettingsLabel("默认画质", systemImage: "play.rectangle")
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
            MineSettingsLabel("蜂窝网络画质", systemImage: "antenna.radiowaves.left.and.right")
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
                MineSettingsLabel("视频编码", systemImage: "film.stack")
            }
        }
    }

    private var av1HardwareDecodeProbeButton: some View {
        Button {
            av1HardwareDecodeProbe = PlaybackCodecPolicy.av1HardwareDecodeProbe
            isShowingAV1HardwareDecodeResult = true
        } label: {
            HStack(spacing: 8) {
                MineSettingsLabel("检测 AV1 硬解", systemImage: "cpu")
                Spacer(minLength: 8)
                Text(av1HardwareDecodeProbe.settingsStatusTitle)
                    .foregroundStyle(.secondary)
            }
        }
        .piliAlert("AV1 硬解检测", isPresented: $isShowingAV1HardwareDecodeResult) {
            PiliAlertButton("好", role: .cancel) {}
        } message: { av1HardwareDecodeProbe.detail }
    }

    private var forceHardwareDecodeToggle: some View {
        Toggle(isOn: Binding(
            get: { libraryStore.forceHardwareDecodeEnabled },
            set: { libraryStore.setForceHardwareDecodeEnabled($0) }
        )) {
            MineSettingsLabel("硬解优先", systemImage: "cpu")
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
            MineSettingsLabel("杜比视界渲染", systemImage: "sparkles.tv")
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
            MineSettingsLabel("播放来源", systemImage: "antenna.radiowaves.left.and.right")
        }
        .pickerStyle(.menu)
    }

    private var cellularBiliTrafficCompatibilityExperimentToggle: some View {
        Toggle(isOn: Binding(
            get: { libraryStore.cellularBiliTrafficCompatibilityExperimentEnabled },
            set: { libraryStore.setCellularBiliTrafficCompatibilityExperimentEnabled($0) }
        )) {
            VStack(alignment: .leading, spacing: 3) {
                MineSettingsLabel("定向流量兼容（实验）", systemImage: "antenna.radiowaves.left.and.right")
                Text("蜂窝网络优先使用 B 站线路；失败时仍可能消耗普通流量。")
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
            MineSettingsLabel("CDN 线路", systemImage: "network")
        }
        .pickerStyle(.menu)
    }

    private var prefersBackupAudioURLToggle: some View {
        Toggle(isOn: Binding(
            get: { libraryStore.prefersBackupAudioURL },
            set: { libraryStore.setPrefersBackupAudioURL($0) }
        )) {
            MineSettingsLabel("优先备用音频线路", systemImage: "speaker.wave.2")
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
                LabeledContent("自定义 Host", value: normalizedCustomCDNHost)
                    .piliFont(.sm)
                    .foregroundStyle(.secondary)
            } else if !playbackCustomCDNHostDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                MineSettingsLabel("Host 格式无效", systemImage: "exclamationmark.triangle")
                    .piliFont(.sm)
                    .foregroundStyle(Color.cc.warning)
            }

            Button(action: commitPlaybackCustomCDNHost) {
                Text("应用线路").frame(maxWidth: .infinity, alignment: .trailing)
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
            MineSettingsLabel("CDN 自动测速", systemImage: "arrow.triangle.2.circlepath")
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
                    "测速间隔 \(playbackCDNProbeRefreshIntervalTitle)",
                    systemImage: "timer"
                )
            }
        } else {
            MineSettingsLabel("启动或返回 App 时更新线路参考；实际播放结果优先。", systemImage: "bolt.horizontal")
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
            MineSettingsLabel("网络协议", systemImage: "point.3.connected.trianglepath.dotted")
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private var playbackNetworkAddressFamilyNotice: some View {
        if libraryStore.playbackNetworkAddressFamilyPreference != .automatic,
           libraryStore.playbackCDNProbeSnapshotForCurrentContext == nil {
            MineSettingsLabel("协议已切换，请重新测速。", systemImage: "arrow.triangle.2.circlepath")
                .piliFont(.sm)
                .foregroundStyle(Color.cc.warning)
        }
    }

    private var playbackCDNProbeButton: some View {
        Button(action: probePlaybackCDN) {
            Text(isProbingPlaybackCDN ? "测速中" : "立即测速").frame(maxWidth: .infinity, alignment: .trailing)
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
            MineSettingsLabel("默认倍速", systemImage: "speedometer")
        }
        .pickerStyle(.menu)
    }
}
