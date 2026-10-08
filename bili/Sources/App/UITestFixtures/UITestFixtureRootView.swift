import Foundation
import SwiftUI
import ChunUI

/// A network-free host for production UI components used by XCUITest.
struct UITestFixtureRootView: View {
    let scenario: UITestFixtureScenario
    @StateObject private var dependencies = AppDependencies()

    var body: some View {
        Group {
            switch scenario {
            case .danmaku:
                UITestDanmakuFixtureView(libraryStore: dependencies.libraryStore)
            case .dynamicDetail:
                UITestDynamicDetailFixtureView(
                    api: dependencies.api
                )
            case .fullscreen:
                UITestPlayerFixtureView()
            case .subtitles:
                PiliSubtitlePreviewFixture()
            case .glassPlayer:
                PiliGlassPlayerPreviewFixture()
            case .commentTree:
                PiliCommentTreeFixture()
            case .interactive:
                PiliInteractiveFixture()
            case .superChat:
                PiliSuperChatFixture(api: dependencies.api)
            case .contentExport:
                PiliContentExportFixture()
            case .glassAudit:
                PiliGlassAuditFixture()
            case .glassFeed:
                PiliGlassFeedFixture()
            case .glassSettings:
                NavigationStack {
                    if ProcessInfo.processInfo.arguments.contains("--glass-preview-theme") {
                        MineThemeColorSettingsView(libraryStore: dependencies.libraryStore)
                    } else {
                        MineInterfaceSettingsView(libraryStore: dependencies.libraryStore)
                    }
                }
            case .dynamicComposer:
                PiliDynamicComposerFixture()
            case .layoutSearch:
                PiliSearchLayoutFixture(api: dependencies.api)
            case .searchHistory:
                PiliSearchHistoryFixture(api: dependencies.api)
            case .layoutMine:
                PiliMineLayoutFixture(dependencies: dependencies, settings: false)
            case .layoutSettings:
                PiliMineLayoutFixture(dependencies: dependencies, settings: true)
            case .layoutComments:
                PiliCommentToolbarLayoutFixture()
            case .layoutVideo:
                PiliVideoLayoutFixture(dependencies: dependencies)
            }
        }
        .modifier(PiliAppChrome())
        .environment(\.piliReduceTransparencyPreview, ProcessInfo.processInfo.arguments.contains("--glass-reduce-transparency"))
        .environmentObject(dependencies.homeRecommendDiagnosticsStore)
        .environmentObject(dependencies)
        .environmentObject(dependencies.libraryStore)
        .environmentObject(dependencies.sessionStore)
    }
}

private struct UITestDynamicDetailFixtureView: View {
    let api: BiliAPIClient
    @State private var homeNavigationPath = NavigationPath()
    @State private var dynamicNavigationPath = NavigationPath()
    @State private var liveNavigationPath = NavigationPath()
    @State private var searchNavigationPath = NavigationPath()
    @State private var mineNavigationPath = NavigationPath()
    @State private var selectedTab: UITestRootTab = .dynamic
    @State private var searchQuery = ""
    @State private var isSearchFocused = false

    var body: some View {
        ZStack {
            Group {
                if UITestFixtureScenario.usesRootTabShell {
                    rootTabShell
                } else {
                    standaloneNavigationShell
                }
            }

        }
        .task {
            guard UITestFixtureScenario.autoOpensDynamicDetail,
                  activeNavigationPath.wrappedValue.isEmpty else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled,
                  activeNavigationPath.wrappedValue.isEmpty else { return }
            activeNavigationPath.wrappedValue.append(DynamicDetailTarget.loaded(Self.imageItem))
        }
    }

    private var rootTabShell: some View {
        TabView(selection: $selectedTab) {
            ForEach(
                [
                    UITestRootTab.home,
                    .dynamic,
                    .live,
                    .search,
                    .mine,
                ],
                id: \.self
            ) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    rootTabNavigationStack(
                        for: tab,
                        detailPath: navigationPathBinding(for: tab)
                    )
                }
            }
        }
        .tabBarMinimizeBehavior(.never)
    }

    @ViewBuilder
    private func rootTabNavigationStack(
        for tab: UITestRootTab,
        detailPath: Binding<NavigationPath>
    ) -> some View {
        NavigationStack(path: detailPath) {
            rootTabContent(for: tab)
                .nativeNavigationSearch(
                    text: $searchQuery,
                    isPresented: $isSearchFocused,
                    isEnabled: tab == .search
                        && selectedTab == .search
                        && detailPath.wrappedValue.isEmpty,
                    prompt: "\u{641c}\u{7d22}",
                    title: "\u{641c}\u{7d22}"
                ) {}
                .toolbar {
                    if tab == .home {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("\u{63a8}\u{8350}/\u{70ed}\u{95e8}") {}
                                .accessibilityIdentifier("fixture.home.mode")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("\u{8d26}\u{53f7}\u{6d88}\u{606f}", systemImage: "bell.fill") {}
                                .accessibilityIdentifier("fixture.home.messages")
                        }
                    }
                }
                .navigationTitle(tab.title)
                .toolbarTitleDisplayMode(.inline)
                .dynamicDetailDestinations(
                    path: detailPath,
                    api: api,
                    preloadedOriginalDetails: [Self.originalDetailItem.idStr: Self.originalDetailItem]
                )
                .navigationDestination(for: VideoOwner.self) { owner in
                    UploaderView(owner: owner)
                        .accessibilityIdentifier("fixture.uploader.root")
                }
        }
        .coordinatesRootTabBarTransitions(
            isDetailPresented: !detailPath.wrappedValue.isEmpty
        )
    }

    @ViewBuilder
    private func rootTabContent(for tab: UITestRootTab) -> some View {
        switch tab {
        case .home, .live, .mine:
            Color.clear
        case .dynamic:
            dynamicFeed
        case .search:
            searchRootContent
        }
    }

    private var searchRootContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                Button("\u{6253}\u{5f00}\u{641c}\u{7d22}\u{7ed3}\u{679c}\u{8be6}\u{60c5}") {
                    isSearchFocused = false
                    DispatchQueue.main.async {
                        activeNavigationPath.wrappedValue.append(
                            DynamicDetailTarget.loaded(Self.imageItem)
                        )
                    }
                }
                .accessibilityIdentifier("fixture.search.openDetail")

                Text(searchQuery)
                    .accessibilityIdentifier("fixture.search.queryValue")
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var standaloneNavigationShell: some View {
        NavigationStack(path: $dynamicNavigationPath) {
            dynamicFeed
                .dynamicDetailDestinations(
                    path: $dynamicNavigationPath,
                    api: api,
                    preloadedOriginalDetails: [Self.originalDetailItem.idStr: Self.originalDetailItem]
                )
        }
    }

    private var dynamicFeed: some View {
        ScrollView {
            VStack(spacing: 0) {
                Button("\u{6253}\u{5f00} UP \u{4e2a}\u{4eba}\u{9875}") {
                    activeNavigationPath.wrappedValue.append(Self.uploaderOwner)
                }
                .accessibilityIdentifier("fixture.dynamic.openUploader")
                .padding(.vertical, 16)

                Divider()

                ForEach(Self.items) { item in
                    DynamicFeedCard(item: item, api: api)
                        .padding(.vertical, 16)

                    Divider()
                }
            }
        }
        .accessibilityIdentifier("dynamic.feed.scroll")
        .nativeTopScrollEdgeEffect()
    }

    private static let items = [imageItem, pureTextItem, forwardItem]
    private static let uploaderOwner = VideoOwner(mid: 1001, name: "\u{52a8}\u{6001}\u{6d4b}\u{8bd5}\u{7528}\u{6237}", face: nil)

    private var activeNavigationPath: Binding<NavigationPath> {
        navigationPathBinding(for: selectedTab)
    }

    private func navigationPathBinding(for tab: UITestRootTab) -> Binding<NavigationPath> {
        switch tab {
        case .home:
            return $homeNavigationPath
        case .dynamic:
            return $dynamicNavigationPath
        case .live:
            return $liveNavigationPath
        case .search:
            return $searchNavigationPath
        case .mine:
            return $mineNavigationPath
        }
    }

    private static let imageItem: DynamicFeedItem = {
        let data = Data(
            #"""
            {
              "id_str": "123456789",
              "type": "DYNAMIC_TYPE_DRAW",
              "basic": {
                "comment_id_str": "123456789",
                "comment_type": 17
              },
              "modules": {
                "module_author": {
                  "mid": 1001,
                  "name": "\u{52a8}\u{6001}\u{6d4b}\u{8bd5}\u{7528}\u{6237}",
                  "face": "https://example.com/avatar.jpg",
                  "pub_time": "\u{521a}\u{521a}"
                },
                "module_dynamic": {
                  "desc": {
                    "text": "\u{56fe}\u{6587}\u{52a8}\u{6001}\u{6d4b}\u{8bd5}\u{5185}\u{5bb9}"
                  },
                  "major": {
                    "draw": {
                      "items": [
                        {
                          "src": "https://example.com/dynamic-image.jpg",
                          "width": 1200,
                          "height": 800
                        },
                        {
                          "src": "https://example.com/dynamic-image-2.jpg",
                          "width": 1200,
                          "height": 800
                        },
                        {
                          "src": "https://example.com/dynamic-image-3.jpg",
                          "width": 1200,
                          "height": 800
                        },
                        {
                          "src": "https://example.com/dynamic-image-4.jpg",
                          "width": 1200,
                          "height": 800
                        },
                        {
                          "src": "https://example.com/dynamic-image-5.jpg",
                          "width": 1200,
                          "height": 800
                        },
                        {
                          "src": "https://example.com/dynamic-image-6.jpg",
                          "width": 1200,
                          "height": 800
                        },
                        {
                          "src": "https://example.com/dynamic-image-7.jpg",
                          "width": 1200,
                          "height": 800
                        },
                        {
                          "src": "https://example.com/dynamic-image-8.jpg",
                          "width": 1200,
                          "height": 800
                        }
                      ]
                    }
                  }
                },
                "module_stat": {
                  "comment": { "count": 2 },
                  "forward": { "count": 1 },
                  "like": { "count": 3, "status": false }
                }
              }
            }
            """#.utf8
        )
        return try! JSONDecoder.bili.decode(DynamicFeedItem.self, from: data)
    }()

    private static let pureTextItem: DynamicFeedItem = {
        let data = Data(
            #"""
            {
              "id_str": "223456789",
              "type": "DYNAMIC_TYPE_WORD",
              "basic": {
                "comment_id_str": "223456789",
                "comment_type": 17
              },
              "modules": {
                "module_author": {
                  "mid": 1002,
                  "name": "\u{7eaf}\u{6587}\u{672c}\u{6d4b}\u{8bd5}\u{7528}\u{6237}",
                  "face": "https://example.com/avatar-2.jpg",
                  "pub_time": "1\u{5206}\u{949f}\u{524d}"
                },
                "module_dynamic": {
                  "desc": {
                    "text": "\u{7eaf}\u{6587}\u{672c}\u{52a8}\u{6001}\u{6d4b}\u{8bd5}\u{5185}\u{5bb9}"
                  }
                },
                "module_stat": {
                  "comment": { "count": 4 },
                  "forward": { "count": 0 },
                  "like": { "count": 5, "status": false }
                }
              }
            }
            """#.utf8
        )
        return try! JSONDecoder.bili.decode(DynamicFeedItem.self, from: data)
    }()

    private static let forwardItem: DynamicFeedItem = {
        let data = Data(
            #"""
            {
              "id_str": "323456789",
              "type": "DYNAMIC_TYPE_FORWARD",
              "basic": {
                "comment_id_str": "323456789",
                "comment_type": 17
              },
              "modules": {
                "module_author": {
                  "mid": 1003,
                  "name": "\u{8f6c}\u{53d1}\u{6d4b}\u{8bd5}\u{7528}\u{6237}",
                  "face": "https://example.com/avatar-3.jpg",
                  "pub_time": "2\u{5206}\u{949f}\u{524d}"
                },
                "module_dynamic": {
                  "desc": {
                    "text": "\u{8f6c}\u{53d1}\u{52a8}\u{6001}\u{6d4b}\u{8bd5}\u{5185}\u{5bb9}"
                  }
                },
                "module_stat": {
                  "comment": { "count": 6 },
                  "forward": { "count": 7 },
                  "like": { "count": 8, "status": false }
                }
              },
              "orig": {
                "id_str": "423456789",
                "type": "DYNAMIC_TYPE_WORD",
                "visible": true,
                "modules": {
                  "module_author": {
                    "mid": 1004,
                    "name": "\u{539f}\u{52a8}\u{6001}\u{6d4b}\u{8bd5}\u{7528}\u{6237}",
                    "face": "https://example.com/avatar-4.jpg"
                  },
                  "module_dynamic": {
                    "desc": {
                      "text": "\u{88ab}\u{8f6c}\u{53d1}\u{7684}\u{539f}\u{52a8}\u{6001}\u{5185}\u{5bb9}"
                    }
                  }
                }
              }
            }
            """#.utf8
        )
        return try! JSONDecoder.bili.decode(DynamicFeedItem.self, from: data)
    }()

    private static let originalDetailItem: DynamicFeedItem = {
        let data = Data(
            #"""
            {
              "id_str": "423456789",
              "type": "DYNAMIC_TYPE_WORD",
              "basic": {
                "comment_id_str": "423456789",
                "comment_type": 17
              },
              "modules": {
                "module_author": {
                  "mid": 1004,
                  "name": "\u{539f}\u{52a8}\u{6001}\u{6d4b}\u{8bd5}\u{7528}\u{6237}",
                  "face": "https://example.com/avatar-4.jpg",
                  "pub_time": "3\u{5206}\u{949f}\u{524d}"
                },
                "module_dynamic": {
                  "desc": {
                    "text": "\u{88ab}\u{8f6c}\u{53d1}\u{7684}\u{539f}\u{52a8}\u{6001}\u{5185}\u{5bb9}"
                  }
                },
                "module_stat": {
                  "comment": { "count": 9 },
                  "forward": { "count": 10 },
                  "like": { "count": 11, "status": false }
                }
              }
            }
            """#.utf8
        )
        return try! JSONDecoder.bili.decode(DynamicFeedItem.self, from: data)
    }()
}

private enum UITestRootTab: Hashable {
    case home
    case dynamic
    case live
    case search
    case mine

    var title: String {
        switch self {
        case .home: "\u{9996}\u{9875}"
        case .dynamic: "\u{52a8}\u{6001}"
        case .live: "\u{76f4}\u{64ad}"
        case .search: "\u{641c}\u{7d22}"
        case .mine: "\u{6211}\u{7684}"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .dynamic: "bolt.horizontal"
        case .live: "play.tv"
        case .search: "magnifyingglass"
        case .mine: "person"
        }
    }
}

private struct UITestDanmakuFixtureView: View {
    @ObservedObject var libraryStore: LibraryStore
    @State private var isShowingSettings = false
    @StateObject private var store = VideoDetailDanmakuSettingsRenderStore()

    var body: some View {
        PlaybackDetailPageHost(
            hidesSystemChrome: .constant(false),
            background: .black,
            statusBarStyle: .lightContent
        ) {
            VStack(spacing: 20) {
                Text("UI Test Video Detail")
                    .accessibilityIdentifier("ui.videoDetail.ready")
                Text(libraryStore.danmakuSettings.displayArea.rawValue)
                    .accessibilityIdentifier("ui.videoDetail.danmakuSettings.persistedValue")
                Button("Open Danmaku Settings") {
                    isShowingSettings = true
                }
                .accessibilityIdentifier("ui.videoDetail.danmakuSettings")
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            if UITestFixtureScenario.resetsPersistedState {
                libraryStore.setDanmakuEnabled(true)
                libraryStore.setDanmakuSettings(.default)
            }
            synchronizeRenderStore()
        }
        .piliSheet(isPresented: $isShowingSettings) {
            DanmakuSettingsSheet(
                store: store,
                toggleDanmaku: toggleDanmaku,
                updateDanmakuSettings: updateDanmakuSettings
            )
            .piliPresentationDetents([.medium])
        }
    }

    private func toggleDanmaku() {
        libraryStore.setDanmakuEnabled(!store.isDanmakuEnabled)
        synchronizeRenderStore()
    }

    private func updateDanmakuSettings(_ settings: DanmakuSettings) {
        libraryStore.setDanmakuSettings(settings)
        synchronizeRenderStore()
    }

    private func synchronizeRenderStore() {
        var snapshot = VideoDetailDanmakuSettingsRenderSnapshot()
        snapshot.isDanmakuEnabled = libraryStore.danmakuEnabled
        snapshot.danmakuSettings = libraryStore.danmakuSettings
        store.update(snapshot)
    }
}

private struct UITestPlayerFixtureView: View {
    @StateObject private var fixture = UITestPlayerFixtureController()
    @State private var isFullscreen = false
    @State private var hidesSystemChrome = false
    @State private var isShowingPlayer = true

    var body: some View {
        PlaybackDetailPageHost(
            hidesSystemChrome: $hidesSystemChrome,
            background: .black,
            statusBarStyle: .lightContent
        ) {
            if isShowingPlayer {
                VStack(spacing: 16) {
                    ZStack {
                        BiliPlayerView(
                            viewModel: fixture.player,
                            presentation: isFullscreen ? .fullScreen : .embedded,
                            showsNavigationChrome: false,
                            showsStartupLoadingIndicator: false,
                            pausesOnDisappear: true,
                            isSecondaryControlsPresented: true,
                            embeddedAspectRatio: 16 / 9,
                            ignoresContainerSafeArea: isFullscreen,
                            keepsPlayerSurfaceStable: true,
                            fullscreenMode: isFullscreen ? .landscape(.landscapeRight) : nil,
                            showsRotationTransitionSnapshot: false,
                            onRequestFullscreen: {
                                isFullscreen = true
                                hidesSystemChrome = true
                            },
                            onExitFullscreen: {
                                isFullscreen = false
                                hidesSystemChrome = false
                            }
                        )
                    }

                    Text(isFullscreen ? "Fullscreen Player" : "Player Ready")
                        .piliFont(.sm)
                        .accessibilityIdentifier(
                            isFullscreen ? "ui.player.fullscreenSurface" : "ui.player.ready"
                        )

                    if !isFullscreen {
                        Text(fixture.player.isTerminated ? "terminated" : "active")
                            .accessibilityIdentifier("ui.player.lifecycleState")
                        HStack {
                            Button("Simulate Failure") {
                                fixture.simulateFailure()
                            }
                            .accessibilityIdentifier("ui.player.simulateFailure")

                            Button("Retry") {
                                fixture.retry()
                            }
                            .accessibilityIdentifier("ui.player.retry")

                            Button("Close Player") {
                                isShowingPlayer = false
                            }
                            .accessibilityIdentifier("ui.player.close")
                        }
                    }
                }
                .foregroundStyle(.white)
            } else {
                VStack(spacing: 12) {
                    Text("Player Closed")
                        .accessibilityIdentifier("ui.player.navigationReturned")
                    Text(fixture.didSuspendForNavigation ? "suspended" : "pending")
                        .accessibilityIdentifier("ui.player.navigationState")
                }
                .foregroundStyle(.white)
            }
        }
    }
}
