import SwiftUI
import ChunUI

struct MineDisplaySettingsSection: View {
    @ObservedObject var libraryStore: LibraryStore
    @AppStorage(VideoCoverBadgeContrastBacking.storageKey) private var videoCoverBadgeContrastBackingOpacity = VideoCoverBadgeContrastBacking.defaultOpacity

    var body: some View {
        Section("外观") {
            PiliSettingPicker(selection: Binding(
                get: { libraryStore.appearanceMode },
                set: { libraryStore.setAppearanceMode($0) }
            )) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                MineSettingsLabel("外观", systemImage: "sun.max")
            }
            .tint(libraryStore.appTintColor)
            .pickerStyle(.menu)

            PiliSettingPicker(selection: Binding(
                get: { libraryStore.appIconPreference },
                set: { libraryStore.setAppIconPreference($0) }
            )) {
                ForEach(AppIconPreference.allCases) { preference in
                    Text(preference.title).tag(preference)
                }
            } label: {
                MineSettingsLabel("应用图标", systemImage: "app")
            }
            .pickerStyle(.menu)

            NavigationLink {
                MineThemeColorSettingsView(libraryStore: libraryStore)
            } label: {
                LabeledContent("主色调") {
                    HStack(spacing: 8) {
                        Circle().fill(libraryStore.appTintColor).frame(width: 16, height: 16)
                        Text(libraryStore.appTintColorHex)
                            .piliFont(.sm).monospaced().foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityIdentifier("settings.theme")

            Toggle(isOn: Binding(
                get: { libraryStore.followsSystemFontSize },
                set: { libraryStore.setFollowsSystemFontSize($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("跟随系统字号", systemImage: "textformat.size")

                    Text("关闭后可手动设置字号。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !libraryStore.followsSystemFontSize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        MineSettingsLabel("手动字号", systemImage: "textformat")
                        Spacer(minLength: 8)
                        Text(libraryStore.manualFontSize.title)
                            .piliFont(.sm).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: manualFontSizeBinding,
                        in: 0...Double(AppManualFontSize.allCases.count - 1),
                        step: 1
                    ) {
                        Text("手动字号")
                    } minimumValueLabel: {
                        Text("A").piliFont(.sm)
                    } maximumValueLabel: {
                        Text("A").piliFont(.baseBold)
                    }
                    .tint(libraryStore.appTintColor)
                    .accessibilityValue(libraryStore.manualFontSize.title)
                }
            }
        }

        Section("内容与导航") {
            Toggle(isOn: Binding(
                get: { libraryStore.showsVideoCoverDurationBadges },
                set: { libraryStore.setShowsVideoCoverDurationBadges($0) }
            )) {
                MineSettingsLabel("封面时长", systemImage: "timer")
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    MineSettingsLabel("角标底色浓度", systemImage: "circle.lefthalf.filled")
                    Spacer(minLength: 8)
                    Text(videoCoverBadgeContrastBackingOpacityTitle)
                        .piliFont(.sm).monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: Binding(
                        get: {
                            VideoCoverBadgeContrastBacking.normalized(videoCoverBadgeContrastBackingOpacity)
                        },
                        set: { value in
                            videoCoverBadgeContrastBackingOpacity = VideoCoverBadgeContrastBacking.normalized(value)
                        }
                    ),
                    in: VideoCoverBadgeContrastBacking.opacityRange,
                    step: 0.05
                )
            }
            .disabled(!libraryStore.showsVideoCoverDurationBadges)

            Toggle(isOn: Binding(
                get: { libraryStore.minimizesTabBarOnScroll },
                set: { libraryStore.setMinimizesTabBarOnScroll($0) }
            )) {
                MineSettingsLabel("滚动收起底栏", systemImage: "arrow.down.right.and.arrow.up.left")
            }

            PiliSettingPicker(selection: Binding(
                get: { libraryStore.videoDetailSegmentedPickerGlassStyle },
                set: { libraryStore.setVideoDetailSegmentedPickerGlassStyle($0) }
            )) {
                ForEach(VideoDetailSegmentedPickerGlassStyle.allCases) { glassStyle in
                    Text(glassStyle.title).tag(glassStyle)
                }
            } label: {
                MineSettingsLabel("底栏玻璃", systemImage: "circle.lefthalf.filled")
            }
            .pickerStyle(.menu)
        }

        Section("图片与存储") {
            PiliSettingPicker(selection: Binding(
                get: { libraryStore.remoteImageQualityPreference },
                set: { libraryStore.setRemoteImageQualityPreference($0) }
            )) {
                ForEach(RemoteImageQualityPreference.allCases) { preference in
                    Text(preference.title).tag(preference)
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("图片质量", systemImage: "photo")

                    Text(libraryStore.remoteImageQualityPreference.detail)
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .pickerStyle(.menu)

            MineImageCacheControl()
        }

        Section("高级与诊断") {
            Toggle(isOn: Binding(
                get: { libraryStore.force120HzScrollingEnabled },
                set: { libraryStore.setForce120HzScrollingEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("120Hz 滑动", systemImage: "speedometer")

                    Text("可能增加耗电。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Toggle(isOn: Binding(
                get: { libraryStore.remoteImageDiagnosticsEnabled },
                set: { libraryStore.setRemoteImageDiagnosticsEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("图片诊断", systemImage: "chart.bar.xaxis")

                    Text("记录加载统计，不含图片、链接或账号信息。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            NavigationLink {
                RemoteImageDiagnosticsView(libraryStore: libraryStore)
            } label: {
                MineSettingsLabel("查看图片诊断", systemImage: "chart.bar.xaxis")
            }

            Toggle(isOn: Binding(
                get: { libraryStore.dynamicCommentHitAreaVisualizationExperimentEnabled },
                set: { libraryStore.setDynamicCommentHitAreaVisualizationExperimentEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("显示评论点击区域", systemImage: "hand.tap")

                    Text("标记回复与操作的点击区域。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var videoCoverBadgeContrastBackingOpacityTitle: String {
        "\(Int((VideoCoverBadgeContrastBacking.normalized(videoCoverBadgeContrastBackingOpacity) * 100).rounded()))%"
    }

    private var manualFontSizeBinding: Binding<Double> {
        Binding(
            get: { Double(libraryStore.manualFontSize.rawValue) },
            set: { value in
                guard let size = AppManualFontSize(rawValue: Int(value.rounded())) else { return }
                libraryStore.setManualFontSize(size)
            }
        )
    }
}

struct MineThemeColorSettingsView: View {
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        PiliForm {
            Section {
                MineThemeColorControl(libraryStore: libraryStore)
            } footer: {
                Text("用于选中状态与控件高亮。")
            }
        }
        .tint(libraryStore.appTintColor)
        .navigationTitle("主色调")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MineThemeColorControl: View {
    @ObservedObject var libraryStore: LibraryStore
    @State private var selectionMode: ThemeColorSelectionMode = .tone
    @State private var tintHexDraft = ""

    private let swatchHexes = AppThemeTintColor.toneHexes

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("选择方式", selection: $selectionMode) {
                ForEach(ThemeColorSelectionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            selectedModeContent

            currentSelectionFooter
        }
        .onAppear {
            tintHexDraft = libraryStore.appTintColorHex
            selectionMode = mode(for: libraryStore.appTintColorHex)
        }
        .onChange(of: libraryStore.appTintColorHex) { _, hex in
            tintHexDraft = hex
        }
        .tint(libraryStore.appTintColor)
    }

    @ViewBuilder
    private var selectedModeContent: some View {
        switch selectionMode {
        case .tone:
            HStack(spacing: 0) {
                ForEach(swatchHexes, id: \.self) { hex in
                    Button {
                        libraryStore.setAppTintColorHex(hex)
                        tintHexDraft = libraryStore.appTintColorHex
                    } label: {
                        colorSwatch(hex)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("选择颜色 \(hex)")
                    .accessibilityAddTraits(libraryStore.appTintColorHex == hex ? .isSelected : [])
                }
            }
            .frame(maxWidth: 400, alignment: .leading)
        case .palette:
            VStack(alignment: .leading, spacing: 10) {
                ColorPicker(
                    selection: Binding(
                        get: { libraryStore.appTintColor },
                        set: { color in
                            libraryStore.setAppTintColor(color)
                            tintHexDraft = libraryStore.appTintColorHex
                        }
                    ),
                    supportsOpacity: false
                ) {
                        MineSettingsLabel("自选颜色", systemImage: "eyedropper")
                }

                HStack(spacing: 10) {
                    Text("色号")
                    Spacer(minLength: 8)
                    TextField(AppThemeTintColor.defaultHex, text: $tintHexDraft)
                        .piliFont(.base).monospaced()
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.done)
                        .onSubmit(commitDraftHex)

                    Button {
                        commitDraftHex()
                    } label: {
                        MineSettingsLabel("应用", systemImage: "checkmark.circle")
                    }
                    .disabled(normalizedDraftHex == nil)
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var currentSelectionFooter: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                currentColorIdentity
                Spacer(minLength: 12)
                resetColorButton
            }
            VStack(alignment: .leading, spacing: 12) {
                currentColorIdentity
                resetColorButton.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var currentColorIdentity: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(libraryStore.appTintColor)
                .frame(width: 18, height: 18)
                .overlay { Circle().stroke(Color(.separator).opacity(0.30), lineWidth: 0.8) }
            Text(libraryStore.appTintColorHex)
                .piliFont(.sm).monospaced()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var resetColorButton: some View {
        Button("恢复默认") {
            libraryStore.resetAppTintColor()
            tintHexDraft = libraryStore.appTintColorHex
            selectionMode = .tone
        }
        .buttonStyle(.borderless)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var normalizedDraftHex: String? {
        AppThemeTintColor.normalizedHex(tintHexDraft)
    }

    private func commitDraftHex() {
        guard let normalizedDraftHex else { return }
        libraryStore.setAppTintColorHex(normalizedDraftHex)
        tintHexDraft = libraryStore.appTintColorHex
    }

    private func mode(for hex: String) -> ThemeColorSelectionMode {
        swatchHexes.contains(hex) ? .tone : .palette
    }

    private func colorSwatch(_ hex: String) -> some View {
        let color = AppThemeTintColor.color(for: hex)
        let isSelected = libraryStore.appTintColorHex == hex
        return Circle()
            .fill(color)
            .frame(width: 24, height: 24)
            .overlay {
                if isSelected {
                    PiliIcon(systemName: "checkmark", size: 11)
                        .piliFont(.smBold)
                        .foregroundStyle(.white)
                }
            }
            .overlay {
                Circle()
                    .stroke(Color(.separator).opacity(0.30), lineWidth: 0.8)
            }
    }
}

private struct MineImageCacheControl: View {
    @State private var statistics: RemoteImageCacheStatistics?
    @State private var isWorking = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                MineSettingsLabel("图片缓存", systemImage: "photo.on.rectangle")
                Text(summaryTitle).piliFont(.sm).monospacedDigit().foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isWorking { ProgressView().controlSize(.small) }
            Button("清理", role: .destructive) { Task { await clearImageCache() } }
                .buttonStyle(.borderless).disabled(isWorking)
                .accessibilityLabel("清理图片缓存")
        }
        .task {
            await reload()
        }
    }

    private var summaryTitle: String {
        guard let statistics else { return "读取中" }
        return ResourceCacheByteFormatter.bytes(statistics.diskUsage)
    }

    @MainActor
    private func reload() async {
        statistics = await RemoteImageCache.shared.statistics()
    }

    @MainActor
    private func clearImageCache() async {
        isWorking = true
        await ResourceCacheCenter.clearImages(includeDisk: true)
        await reload()
        isWorking = false
    }
}

private enum ThemeColorSelectionMode: String, CaseIterable, Identifiable {
    case tone
    case palette

    var id: Self { self }

    var title: String {
        switch self {
        case .tone:
            "色调"
        case .palette:
            "色板"
        }
    }
}
