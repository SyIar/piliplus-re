import SwiftUI
import ChunUI

struct MineHomeSettingsSection: View {
    @EnvironmentObject private var homeRecommendDiagnosticsStore: HomeRecommendDiagnosticsStore
    @EnvironmentObject private var sessionStore: SessionStore
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        Section("首页") {
            PiliSettingPicker(selection: Binding(
                get: { libraryStore.homeFeedLayout },
                set: { libraryStore.setHomeFeedLayout($0) }
            )) {
                ForEach(HomeFeedLayout.allCases) { layout in
                    Text(layout.title).tag(layout)
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("首页布局", systemImage: "rectangle.grid.1x2")
                    Text("双列布局在 iPad 上随窗口宽度调整。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .pickerStyle(.menu)

            PiliSettingPicker(selection: Binding(
                get: { libraryStore.homeRecommendFeedSourcePreference },
                set: { libraryStore.setHomeRecommendFeedSourcePreference($0) }
            )) {
                ForEach(HomeRecommendFeedSourcePreference.allCases) { source in
                    Text(source.title).tag(source)
                }
            } label: {
                MineSettingsLabel("推荐来源", systemImage: "sparkles.tv")
            }
            .pickerStyle(.menu)

            Text(recommendSourceHint)
                .piliFont(.sm)
                .foregroundStyle(.secondary)

            NavigationLink {
                MineHomeRecommendDiagnosticsView()
            } label: {
                PlainSettingsNavigationRow(
                    title: "推荐诊断",
                    subtitle: MineHomeRecommendDiagnosticsSummary(
                        snapshot: homeRecommendDiagnosticsStore.snapshot
                    ).text,
                )
            }

            Toggle(isOn: Binding(
                get: { libraryStore.nativePullRefreshEnabled },
                set: { libraryStore.setNativePullRefreshEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("原生下拉刷新", systemImage: "arrow.clockwise.circle")

                    Text("关闭后可调整刷新距离。")
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
            return "使用网页端推荐。"
        case .app:
            if libraryStore.guestModeEnabled { return "使用游客推荐，不使用账号偏好。" }
            if sessionStore.appAccessKey() != nil { return "使用账号的个性化推荐。" }
            return "短信登录后可获得更准确的个性化推荐。"
        }
    }
}

private struct MineHomeRefreshDistanceControl: View {
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                MineSettingsLabel("刷新距离", systemImage: "arrow.down.circle")
                Spacer()
                Text(
                    libraryStore.nativePullRefreshEnabled
                        ? "系统默认"
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
                    Text("刷新距离")
                } minimumValueLabel: {
                    Text("近")
                } maximumValueLabel: {
                    Text("远")
                }

                HStack {
                    Text(refreshDistanceHint)
                        .piliFont(.sm)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Button("默认") {
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
            return "关闭原生刷新后可调整。"
        }
        return "下拉到指定距离后刷新。"
    }
}
