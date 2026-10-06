import SwiftUI
import ChunUI

struct MineContentFilterSettingsView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @AppStorage("piliplus.filter.blacklistedCreators") private var blocksCreators = true
    @AppStorage("piliplus.display.videoWarnings") private var videoWarnings = true
    @AppStorage("piliplus.display.dynamicWarnings") private var dynamicWarnings = true
    @ObservedObject private var blacklisted = PiliBlacklistedCreators.shared
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        PiliForm {
            Section {
                NavigationLink("弹幕屏蔽") { PiliDanmakuRulesView(api: dependencies.api) }
                NavigationLink { PiliCommentKeywordSettingsView() } label: { PiliLabel("评论关键词", systemImage: "text.bubble.badge.minus") }
                Toggle(isOn: Binding(
                    get: { libraryStore.blocksAdDynamics },
                    set: { libraryStore.setBlocksAdDynamics($0) }
                )) {
                    MineSettingsLabel("屏蔽广告动态", systemImage: "megaphone.badge.minus")
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.blocksGoodsDynamics },
                    set: { libraryStore.setBlocksGoodsDynamics($0) }
                )) {
                    MineSettingsLabel("屏蔽带货动态", systemImage: "bag.badge.minus")
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.blocksGoodsComments },
                    set: { libraryStore.setBlocksGoodsComments($0) }
                )) {
                    MineSettingsLabel("屏蔽带货评论", systemImage: "text.bubble.badge.minus")
                }

                NavigationLink {
                    DynamicKeywordFilterSettingsView(libraryStore: libraryStore)
                } label: {
                    PlainSettingsNavigationRow(
                        title: "动态关键词",
                        subtitle: "\(libraryStore.blockedDynamicKeywords.count) 个关键词",
                    )
                }

                Text("关键词匹配正文、标题和转发内容；广告与带货按内容自动过滤。")
                    .piliFont(.sm)
                    .foregroundStyle(.secondary)
            }

            Section("内容提示") {
                Toggle("视频争议提示", isOn: $videoWarnings)
                Toggle("动态争议提示", isOn: $dynamicWarnings)
            }
            Section("推荐过滤") {
                NavigationLink("正则、分区与关注豁免") { PiliAdvancedRecommendFilterView(libraryStore: libraryStore) }
                Toggle("屏蔽黑名单视频", isOn: $blocksCreators)
                PiliSettingAction(title: "黑名单 · \(blacklisted.ids.count) 位") {
                    Button("同步") { Task { await blacklisted.refresh(api: dependencies.api, force: true) } }
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
                    MineSettingsLabel("最短时长", systemImage: "timer")
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
                    MineSettingsLabel("最低播放量", systemImage: "play.circle")
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
                    MineSettingsLabel("最低点赞率", systemImage: "hand.thumbsup")
                }
                .pickerStyle(.menu)

                NavigationLink {
                    RecommendKeywordFilterSettingsView(libraryStore: libraryStore)
                } label: {
                    PlainSettingsNavigationRow(
                        title: "标题关键词",
                        subtitle: "\(libraryStore.blockedRecommendKeywords.count) 个关键词",
                    )
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.appliesRecommendFiltersToRelatedVideos },
                    set: { libraryStore.setAppliesRecommendFiltersToRelatedVideos($0) }
                )) {
                    MineSettingsLabel("应用到相关推荐", systemImage: "rectangle.stack.badge.minus")
                }

                Text("开启后同时过滤详情页的相关推荐。")
                    .piliFont(.sm)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(libraryStore.appTintColor)
        .formStyle(.grouped)
        .nativeTopScrollEdgeEffect()
        .navigationTitle("内容过滤")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func recommendDurationTitle(_ seconds: Int) -> String {
        seconds == 0 ? "不过滤" : "\(seconds) 秒"
    }

    private func recommendViewTitle(_ count: Int) -> String {
        count == 0 ? "不过滤" : "\(count)"
    }

    private func recommendLikeRatioTitle(_ percent: Int) -> String {
        percent == 0 ? "不过滤" : "\(percent)%"
    }
}
