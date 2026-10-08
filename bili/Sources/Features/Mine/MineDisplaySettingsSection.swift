import SwiftUI
import ChunUI

struct MineDisplaySettingsSection: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var libraryStore: LibraryStore
    @AppStorage(VideoCoverBadgeContrastBacking.storageKey) private var videoCoverBadgeContrastBackingOpacity = VideoCoverBadgeContrastBacking.defaultOpacity

    var body: some View {
        Section("\u{5916}\u{89c2}") {
            PiliSettingPicker(selection: Binding(
                get: { libraryStore.appearanceMode },
                set: { libraryStore.setAppearanceMode($0) }
            )) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                MineSettingsLabel("\u{5916}\u{89c2}", systemImage: "sun.max")
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
                MineSettingsLabel("\u{5e94}\u{7528}\u{56fe}\u{6807}", systemImage: "app")
            }
            .pickerStyle(.menu)

            NavigationLink {
                MineThemeColorSettingsView(libraryStore: libraryStore)
            } label: {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\u{4e3b}\u{8272}\u{8c03}")
                        themeColorValue.frame(maxWidth: .infinity, alignment: .trailing)
                    }
                } else {
                    HStack(spacing: 16) {
                        Text("\u{4e3b}\u{8272}\u{8c03}")
                        Spacer(minLength: 8)
                        themeColorValue
                    }
                }
            }
            .accessibilityIdentifier("settings.theme")
            .accessibilityLabel("\u{4e3b}\u{8272}\u{8c03}")
            .accessibilityValue(libraryStore.appTintColorHex)

            Toggle(isOn: Binding(
                get: { libraryStore.followsSystemFontSize },
                set: { libraryStore.setFollowsSystemFontSize($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("\u{8ddf}\u{968f}\u{7cfb}\u{7edf}\u{5b57}\u{53f7}", systemImage: "textformat.size")

                    Text("\u{5173}\u{95ed}\u{540e}\u{53ef}\u{624b}\u{52a8}\u{8bbe}\u{7f6e}\u{5b57}\u{53f7}。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !libraryStore.followsSystemFontSize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        MineSettingsLabel("\u{624b}\u{52a8}\u{5b57}\u{53f7}", systemImage: "textformat")
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
                        Text("\u{624b}\u{52a8}\u{5b57}\u{53f7}")
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

        Section("\u{5185}\u{5bb9}\u{4e0e}\u{5bfc}\u{822a}") {
            PiliSettingPicker(selection: Binding(
                get: { libraryStore.homeFeedLayout },
                set: { libraryStore.setHomeFeedLayout($0) }
            )) {
                ForEach(HomeFeedLayout.allCases) { layout in
                    Text(layout.title).tag(layout)
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("\u{9996}\u{9875}\u{5e03}\u{5c40}", systemImage: "rectangle.grid.1x2")
                    Text("\u{53cc}\u{5217}\u{5e03}\u{5c40}\u{5728} iPad \u{4e0a}\u{968f}\u{7a97}\u{53e3}\u{5bbd}\u{5ea6}\u{8c03}\u{6574}。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .pickerStyle(.menu)


            Toggle(isOn: Binding(
                get: { libraryStore.showsVideoCoverDurationBadges },
                set: { libraryStore.setShowsVideoCoverDurationBadges($0) }
            )) {
                MineSettingsLabel("\u{5c01}\u{9762}\u{65f6}\u{957f}", systemImage: "timer")
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    MineSettingsLabel("\u{89d2}\u{6807}\u{5e95}\u{8272}\u{6d53}\u{5ea6}", systemImage: "circle.lefthalf.filled")
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
                MineSettingsLabel("\u{6eda}\u{52a8}\u{6536}\u{8d77}\u{5e95}\u{680f}", systemImage: "arrow.down.right.and.arrow.up.left")
            }

            PiliSettingPicker(selection: Binding(
                get: { libraryStore.videoDetailSegmentedPickerGlassStyle },
                set: { libraryStore.setVideoDetailSegmentedPickerGlassStyle($0) }
            )) {
                ForEach(VideoDetailSegmentedPickerGlassStyle.allCases) { glassStyle in
                    Text(glassStyle.title).tag(glassStyle)
                }
            } label: {
                MineSettingsLabel("\u{5e95}\u{680f}\u{73bb}\u{7483}", systemImage: "circle.lefthalf.filled")
            }
            .pickerStyle(.menu)
        }

        Section("\u{56fe}\u{7247}\u{4e0e}\u{5b58}\u{50a8}") {
            PiliSettingPicker(selection: Binding(
                get: { libraryStore.remoteImageQualityPreference },
                set: { libraryStore.setRemoteImageQualityPreference($0) }
            )) {
                ForEach(RemoteImageQualityPreference.allCases) { preference in
                    Text(preference.title).tag(preference)
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("\u{56fe}\u{7247}\u{8d28}\u{91cf}", systemImage: "photo")

                    Text(libraryStore.remoteImageQualityPreference.detail)
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .pickerStyle(.menu)

            MineImageCacheControl()
        }

        Section("\u{5237}\u{65b0}\u{7387}") {
            Toggle(isOn: Binding(
                get: { libraryStore.force120HzScrollingEnabled },
                set: { libraryStore.setForce120HzScrollingEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("120Hz \u{6ed1}\u{52a8}", systemImage: "speedometer")

                    Text("\u{53ef}\u{80fd}\u{589e}\u{52a0}\u{8017}\u{7535}。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

        }
    }

    private var themeColorValue: some View {
        HStack(spacing: 8) {
            Circle().fill(libraryStore.appTintColor).frame(width: 16, height: 16)
            Text(libraryStore.appTintColorHex)
                .piliFont(.sm).monospaced().foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
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
                Text("\u{7528}\u{4e8e}\u{9009}\u{4e2d}\u{72b6}\u{6001}\u{4e0e}\u{63a7}\u{4ef6}\u{9ad8}\u{4eae}。")
            }
        }
        .tint(libraryStore.appTintColor)
        .navigationTitle("\u{4e3b}\u{8272}\u{8c03}")
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
            Picker("\u{9009}\u{62e9}\u{65b9}\u{5f0f}", selection: $selectionMode) {
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
                    .accessibilityLabel("\u{9009}\u{62e9}\u{989c}\u{8272} \(hex)")
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
                        MineSettingsLabel("\u{81ea}\u{9009}\u{989c}\u{8272}", systemImage: "eyedropper")
                }

                HStack(spacing: 10) {
                    Text("\u{8272}\u{53f7}")
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
                        MineSettingsLabel("\u{5e94}\u{7528}", systemImage: "checkmark.circle")
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
        Button("\u{6062}\u{590d}\u{9ed8}\u{8ba4}") {
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
                MineSettingsLabel("\u{56fe}\u{7247}\u{7f13}\u{5b58}", systemImage: "photo.on.rectangle")
                Text(summaryTitle).piliFont(.sm).monospacedDigit().foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isWorking { ProgressView().controlSize(.small) }
            Button("\u{6e05}\u{7406}", role: .destructive) { Task { await clearImageCache() } }
                .buttonStyle(.borderless).disabled(isWorking)
                .accessibilityLabel("\u{6e05}\u{7406}\u{56fe}\u{7247}\u{7f13}\u{5b58}")
        }
        .task {
            await reload()
        }
    }

    private var summaryTitle: String {
        guard let statistics else { return "\u{8bfb}\u{53d6}\u{4e2d}" }
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
            "\u{8272}\u{8c03}"
        case .palette:
            "\u{8272}\u{677f}"
        }
    }
}
