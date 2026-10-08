import SwiftUI
import ChunUI

enum MineContentFilterScope { case all, recommendation, community }

struct MineContentFilterSettingsView: View {
    var scope: MineContentFilterScope = .all
    @EnvironmentObject private var dependencies: AppDependencies
    @AppStorage("piliplus.filter.blacklistedCreators") private var blocksCreators = true
    @AppStorage("piliplus.display.videoWarnings") private var videoWarnings = true
    @AppStorage("piliplus.display.dynamicWarnings") private var dynamicWarnings = true
    @ObservedObject private var blacklisted = PiliBlacklistedCreators.shared
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        PiliForm {
            if scope != .recommendation {
            Section {
                NavigationLink { PiliCommentKeywordSettingsView() } label: { PiliLabel("\u{8bc4}\u{8bba}\u{5173}\u{952e}\u{8bcd}", systemImage: "text.bubble.badge.minus") }
                Toggle(isOn: Binding(
                    get: { libraryStore.blocksAdDynamics },
                    set: { libraryStore.setBlocksAdDynamics($0) }
                )) {
                    MineSettingsLabel("\u{5c4f}\u{853d}\u{5e7f}\u{544a}\u{52a8}\u{6001}", systemImage: "megaphone.badge.minus")
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.blocksGoodsDynamics },
                    set: { libraryStore.setBlocksGoodsDynamics($0) }
                )) {
                    MineSettingsLabel("\u{5c4f}\u{853d}\u{5e26}\u{8d27}\u{52a8}\u{6001}", systemImage: "bag.badge.minus")
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.blocksGoodsComments },
                    set: { libraryStore.setBlocksGoodsComments($0) }
                )) {
                    MineSettingsLabel("\u{5c4f}\u{853d}\u{5e26}\u{8d27}\u{8bc4}\u{8bba}", systemImage: "text.bubble.badge.minus")
                }

                NavigationLink {
                    DynamicKeywordFilterSettingsView(libraryStore: libraryStore)
                } label: {
                    PlainSettingsNavigationRow(
                        title: "\u{52a8}\u{6001}\u{5173}\u{952e}\u{8bcd}",
                        subtitle: "\(libraryStore.blockedDynamicKeywords.count) \u{4e2a}\u{5173}\u{952e}\u{8bcd}",
                    )
                }

                Text("\u{5173}\u{952e}\u{8bcd}\u{5339}\u{914d}\u{6b63}\u{6587}、\u{6807}\u{9898}\u{548c}\u{8f6c}\u{53d1}\u{5185}\u{5bb9}；\u{5e7f}\u{544a}\u{4e0e}\u{5e26}\u{8d27}\u{6309}\u{5185}\u{5bb9}\u{81ea}\u{52a8}\u{8fc7}\u{6ee4}。")
                    .piliFont(.sm)
                    .foregroundStyle(.secondary)
            }

            Section("\u{5185}\u{5bb9}\u{63d0}\u{793a}") {
                Toggle("\u{89c6}\u{9891}\u{4e89}\u{8bae}\u{63d0}\u{793a}", isOn: $videoWarnings)
                Toggle("\u{52a8}\u{6001}\u{4e89}\u{8bae}\u{63d0}\u{793a}", isOn: $dynamicWarnings)
            }
            }
            if scope != .community {
            Section("\u{63a8}\u{8350}\u{8fc7}\u{6ee4}") {
                NavigationLink("\u{6b63}\u{5219}、\u{5206}\u{533a}\u{4e0e}\u{5173}\u{6ce8}\u{8c41}\u{514d}") { PiliAdvancedRecommendFilterView(libraryStore: libraryStore) }
                Toggle("\u{5c4f}\u{853d}\u{9ed1}\u{540d}\u{5355}\u{89c6}\u{9891}", isOn: $blocksCreators)
                PiliSettingAction(title: "\u{9ed1}\u{540d}\u{5355} · \(blacklisted.ids.count) \u{4f4d}") {
                    Button("\u{540c}\u{6b65}") { Task { await blacklisted.refresh(api: dependencies.api, force: true) } }
                }
                if let error = blacklisted.error { Text(error).piliFont(.sm).foregroundStyle(.secondary) }
                PiliSettingPicker(selection: Binding(
                    get: { libraryStore.recommendMinimumDurationSeconds },
                    set: { libraryStore.setRecommendMinimumDurationSeconds($0) }
                )) {
                    ForEach(LibraryStore.supportedRecommendMinimumDurations, id: \.self) { seconds in
                        Text(recommendDurationTitle(seconds)).tag(seconds)
                    }
                } label: {
                    MineSettingsLabel("\u{6700}\u{77ed}\u{65f6}\u{957f}", systemImage: "timer")
                }
                .pickerStyle(.menu)

                PiliSettingPicker(selection: Binding(
                    get: { libraryStore.recommendMinimumViewCount },
                    set: { libraryStore.setRecommendMinimumViewCount($0) }
                )) {
                    ForEach(LibraryStore.supportedRecommendMinimumViews, id: \.self) { count in
                        Text(recommendViewTitle(count)).tag(count)
                    }
                } label: {
                    MineSettingsLabel("\u{6700}\u{4f4e}\u{64ad}\u{653e}\u{91cf}", systemImage: "play.circle")
                }
                .pickerStyle(.menu)

                PiliSettingPicker(selection: Binding(
                    get: { libraryStore.recommendMinimumLikeRatioPercent },
                    set: { libraryStore.setRecommendMinimumLikeRatioPercent($0) }
                )) {
                    ForEach(LibraryStore.supportedRecommendMinimumLikeRatios, id: \.self) { percent in
                        Text(recommendLikeRatioTitle(percent)).tag(percent)
                    }
                } label: {
                    MineSettingsLabel("\u{6700}\u{4f4e}\u{70b9}\u{8d5e}\u{7387}", systemImage: "hand.thumbsup")
                }
                .pickerStyle(.menu)

                NavigationLink {
                    RecommendKeywordFilterSettingsView(libraryStore: libraryStore)
                } label: {
                    PlainSettingsNavigationRow(
                        title: "\u{6807}\u{9898}\u{5173}\u{952e}\u{8bcd}",
                        subtitle: "\(libraryStore.blockedRecommendKeywords.count) \u{4e2a}\u{5173}\u{952e}\u{8bcd}",
                    )
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.appliesRecommendFiltersToRelatedVideos },
                    set: { libraryStore.setAppliesRecommendFiltersToRelatedVideos($0) }
                )) {
                    MineSettingsLabel("\u{5e94}\u{7528}\u{5230}\u{76f8}\u{5173}\u{63a8}\u{8350}", systemImage: "rectangle.stack.badge.minus")
                }

                Text("\u{5f00}\u{542f}\u{540e}\u{540c}\u{65f6}\u{8fc7}\u{6ee4}\u{8be6}\u{60c5}\u{9875}\u{7684}\u{76f8}\u{5173}\u{63a8}\u{8350}。")
                    .piliFont(.sm)
                    .foregroundStyle(.secondary)
            }
            }
        }
        .tint(libraryStore.appTintColor)
        .formStyle(.grouped)
        .nativeTopScrollEdgeEffect()
        .navigationTitle(scope == .recommendation ? "\u{63a8}\u{8350}\u{8fc7}\u{6ee4}" : "\u{52a8}\u{6001}\u{4e0e}\u{8bc4}\u{8bba}")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func recommendDurationTitle(_ seconds: Int) -> String {
        seconds == 0 ? "\u{4e0d}\u{8fc7}\u{6ee4}" : "\(seconds) \u{79d2}"
    }

    private func recommendViewTitle(_ count: Int) -> String {
        count == 0 ? "\u{4e0d}\u{8fc7}\u{6ee4}" : "\(count)"
    }

    private func recommendLikeRatioTitle(_ percent: Int) -> String {
        percent == 0 ? "\u{4e0d}\u{8fc7}\u{6ee4}" : "\(percent)%"
    }
}
