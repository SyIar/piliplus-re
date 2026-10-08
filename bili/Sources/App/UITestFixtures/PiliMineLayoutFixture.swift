import SwiftUI

struct PiliMineLayoutFixture: View {
    let dependencies: AppDependencies
    let settings: Bool
    @StateObject private var model: MineViewModel
    @StateObject private var messages: AccountMessageCenterViewModel
    @State private var path = NavigationPath()

    init(dependencies: AppDependencies, settings: Bool) {
        self.dependencies = dependencies; self.settings = settings
        let session = dependencies.sessionStore
        try? session.saveLoginCookies(["SESSDATA": "ui-fixture", "DedeUserID": "123"])
        let user = try! JSONDecoder().decode(NavUserInfo.self, from: Data(#"{"isLogin":true,"mid":123,"uname":"PiliPlus","money":637,"level_info":{"current_level":4,"current_exp":5205,"next_exp":10800}}"#.utf8))
        session.updateUser(user)
        let model = MineViewModel(api: dependencies.api, sessionStore: session)
        model.statistics = MineStatistics(following: 128, follower: 64, dynamicCount: 12)
        model.favoriteFolders = try! JSONDecoder().decode([FavoriteFolder].self, from: Data(#"[{"id":1,"title":"Film and history","media_count":9,"attr":0},{"id":2,"title":"Music collection","media_count":4,"attr":0}]"#.utf8))
        model.favoriteState = .loaded
        _model = StateObject(wrappedValue: model)
        _messages = StateObject(wrappedValue: AccountMessageCenterViewModel(service: dependencies.accountMessageService, sessionStore: session))
    }
    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if settings { settingsPage }
                else {
                    MineContentView(viewModel: model, accountMessageViewModel: messages,
                        sessionStore: dependencies.sessionStore, libraryStore: dependencies.libraryStore,
                        onQRCodeLogin: {}, onSMSLogin: {}, onWebLogin: {}, onOpenRoute: { path.append($0) })
                        .navigationTitle("\u{6211}\u{7684}").navigationBarTitleDisplayMode(.inline)
                }
            }
            .navigationDestination(for: MineOverlayRoute.self) { route in
                if route == .settings { settingsPage }
                else { Text(String(describing: route)) }
            }
        }
    }
    private var settingsPage: some View {
        PiliSettingsHomeView(viewModel: model, sessionStore: dependencies.sessionStore, libraryStore: dependencies.libraryStore)
    }
}

struct PiliCommentToolbarLayoutFixture: View {
    @State private var selection = VideoDetailContentTab.comments
    @State private var refreshes = 0
    @State private var compositions = 0
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VideoDetailNativeContentTabView(selection: $selection, layoutWidth: geometry.size.width,
                    topInset: 0, mountsSecondaryContent: true,
                    onOpenCommentComposer: { compositions += 1 }, onRefreshComments: { refreshes += 1 },
                    onScrollOffsetChange: nil) { tab, _ in
                        VStack(alignment: .leading, spacing: 24) {
                            Text("\(refreshes) / \(compositions)").accessibilityIdentifier("fixture.comment.actions")
                            ForEach(0..<10) { index in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Reader \(index + 1)").font(.headline)
                                    Text("A clear layout keeps the conversation easy to follow.")
                                    Divider()
                                }
                            }
                        }.padding(20)
                    }
            }.navigationTitle("\u{8bc4}\u{8bba}").navigationBarTitleDisplayMode(.inline)
        }
    }
}
