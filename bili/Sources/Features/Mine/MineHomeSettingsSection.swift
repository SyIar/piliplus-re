import SwiftUI
import ChunUI

struct MineHomeSettingsSection: View {
    @EnvironmentObject private var homeRecommendDiagnosticsStore: HomeRecommendDiagnosticsStore
    @EnvironmentObject private var sessionStore: SessionStore
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        Section("\u{9996}\u{9875}") {
            PiliSettingPicker(selection: Binding(
                get: { libraryStore.homeRecommendFeedSourcePreference },
                set: { libraryStore.setHomeRecommendFeedSourcePreference($0) }
            )) {
                ForEach(HomeRecommendFeedSourcePreference.allCases) { source in
                    Text(source.title).tag(source)
                }
            } label: {
                MineSettingsLabel("\u{63a8}\u{8350}\u{6765}\u{6e90}", systemImage: "sparkles.tv")
            }
            .pickerStyle(.menu)

            Text(recommendSourceHint)
                .piliFont(.sm)
                .foregroundStyle(.secondary)

            Toggle(isOn: Binding(
                get: { libraryStore.nativePullRefreshEnabled },
                set: { libraryStore.setNativePullRefreshEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("\u{539f}\u{751f}\u{4e0b}\u{62c9}\u{5237}\u{65b0}", systemImage: "arrow.clockwise.circle")

                    Text("\u{5173}\u{95ed}\u{540e}\u{53ef}\u{8c03}\u{6574}\u{5237}\u{65b0}\u{8ddd}\u{79bb}。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            MineHomeRefreshDistanceControl(libraryStore: libraryStore)
        }
    }

    private var recommendSourceHint: String {
        switch libraryStore.homeRecommendFeedSourcePreference {
        case .web:
            return "\u{4f7f}\u{7528}\u{7f51}\u{9875}\u{7aef}\u{63a8}\u{8350}。"
        case .app:
            if libraryStore.guestModeEnabled { return "\u{4f7f}\u{7528}\u{6e38}\u{5ba2}\u{63a8}\u{8350}，\u{4e0d}\u{4f7f}\u{7528}\u{8d26}\u{53f7}\u{504f}\u{597d}。" }
            if sessionStore.appAccessKey() != nil { return "\u{4f7f}\u{7528}\u{8d26}\u{53f7}\u{7684}\u{4e2a}\u{6027}\u{5316}\u{63a8}\u{8350}。" }
            return "\u{77ed}\u{4fe1}\u{767b}\u{5f55}\u{540e}\u{53ef}\u{83b7}\u{5f97}\u{66f4}\u{51c6}\u{786e}\u{7684}\u{4e2a}\u{6027}\u{5316}\u{63a8}\u{8350}。"
        }
    }
}

private struct MineHomeRefreshDistanceControl: View {
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                MineSettingsLabel("\u{5237}\u{65b0}\u{8ddd}\u{79bb}", systemImage: "arrow.down.circle")
                Spacer()
                Text(
                    libraryStore.nativePullRefreshEnabled
                        ? "\u{7cfb}\u{7edf}\u{9ed8}\u{8ba4}"
                        : "\(Int(libraryStore.homeRefreshTriggerDistance)) pt"
                )
                    .piliFont(.base).monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            if libraryStore.nativePullRefreshEnabled {
                Text(refreshDistanceHint)
                    .piliFont(.sm)
                    .foregroundStyle(.secondary)
            } else {
                Slider(
                    value: Binding(
                        get: { libraryStore.homeRefreshTriggerDistance },
                        set: { libraryStore.setHomeRefreshTriggerDistance($0) }
                    ),
                    in: LibraryStore.homeRefreshDistanceRange,
                    step: 5
                ) {
                    Text("\u{5237}\u{65b0}\u{8ddd}\u{79bb}")
                } minimumValueLabel: {
                    Text("\u{8fd1}")
                } maximumValueLabel: {
                    Text("\u{8fdc}")
                }

                HStack {
                    Text(refreshDistanceHint)
                        .piliFont(.sm)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Button("\u{9ed8}\u{8ba4}") {
                        libraryStore.setHomeRefreshTriggerDistance(
                            LibraryStore.defaultHomeRefreshTriggerDistance
                        )
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var refreshDistanceHint: String {
        if libraryStore.nativePullRefreshEnabled {
            return "\u{5173}\u{95ed}\u{539f}\u{751f}\u{5237}\u{65b0}\u{540e}\u{53ef}\u{8c03}\u{6574}。"
        }
        return "\u{4e0b}\u{62c9}\u{5230}\u{6307}\u{5b9a}\u{8ddd}\u{79bb}\u{540e}\u{5237}\u{65b0}。"
    }
}
