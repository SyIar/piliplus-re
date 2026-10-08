import SwiftUI
import ChunUI

/// Deterministic data, using the production search accessory and detail controls.
private enum PiliLayoutFixtureData {
    static let video = VideoItem(
        bvid: "BV1layout001", aid: 101,
        title: "\u{4e09}\u{5341}\u{5206}\u{949f}\u{8bfb}\u{61c2}\u{5386}\u{53f2}：\u{57ce}\u{5e02}、\u{4eba}\u{6587}\u{4e0e}\u{65f6}\u{4ee3}\u{7684}\u{53d8}\u{8fc1}",
        pic: nil, desc: "\u{901a}\u{8fc7}\u{5730}\u{56fe}\u{4e0e}\u{5f71}\u{50cf}，\u{4e86}\u{89e3}\u{5386}\u{53f2}\u{7684}\u{6545}\u{4e8b}。",
        duration: 1773, pubdate: 1_759_000_000,
        owner: .init(mid: 123, name: "\u{5386}\u{53f2}\u{5f71}\u{50cf}\u{4e0e}\u{4eba}\u{6587}\u{9891}\u{9053}", face: nil),
        stat: nil, cid: nil, pages: nil, dimension: nil
    )
}

struct PiliSearchLayoutFixture: View {
    @StateObject private var model: SearchViewModel
    @State private var selectedTab = 1
    @State private var focused = false
    @State private var keyboardVisible = false

    init(api: BiliAPIClient) {
        let model = SearchViewModel(api: api)
        model.query = "\u{5386}\u{53f2}"
        model.results = (0..<12).map { index in
            let source = PiliLayoutFixtureData.video
            let video = VideoItem(
                bvid: "BV1layout\(index)", aid: source.aid, title: source.title,
                pic: nil, desc: source.desc, duration: source.duration, pubdate: source.pubdate,
                owner: source.owner, stat: nil, cid: nil, pages: nil, dimension: nil
            )
            return .video(video)
        }
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("\u{9996}\u{9875}", systemImage: "house", value: 0) { Color.clear }
            Tab("\u{641c}\u{7d22}", systemImage: "magnifyingglass", value: 1, role: .search) {
                NavigationStack {
                    SearchListView(viewModel: model, showsHotSearches: false)
                        .navigationTitle("\u{641c}\u{7d22}")
                        .navigationBarTitleDisplayMode(.inline)
                        .nativeNavigationSearch(
                            text: $model.query, isPresented: $focused,
                            isKeyboardVisible: $keyboardVisible, isEnabled: true,
                            prompt: "\u{641c}\u{7d22}", title: "\u{641c}\u{7d22}", onSubmit: {}
                        )
                }
            }
        }
        .tabViewBottomAccessory {
            SearchFilterButton(viewModel: model).padding(.horizontal, 12)
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

struct PiliVideoLayoutFixture: View {
    @StateObject private var model: VideoDetailViewModel

    init(dependencies: AppDependencies) {
        let model = VideoDetailViewModel(
            seedVideo: PiliLayoutFixtureData.video,
            api: dependencies.api, libraryStore: dependencies.libraryStore,
            sessionStore: dependencies.sessionStore, sponsorBlockService: dependencies.sponsorBlockService
        )
        model.hasResolvedDetailMetadata = true
        model.syncAllRenderStores()
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 16) {
                        ZStack {
                            Rectangle().fill(.black.gradient)
                            PiliIcon(systemName: "play.circle", size: 48).foregroundStyle(.white)
                        }
                        .frame(height: 180)
                        .accessibilityHidden(true)
                        VideoDetailSummaryCard(
                            viewModel: model, contentWidth: max(1, geometry.size.width - 32),
                            showsNetworkDiagnosticsButton: false,
                            onShowNetworkDiagnostics: {}, onShowFavoriteFolders: {}, onShowCoinPicker: {}
                        )
                        Text("\u{76f8}\u{5173}\u{63a8}\u{8350}")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                        SearchVideoResultRow(video: PiliLayoutFixtureData.video)
                            .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 24)
                }
                .background(Color.cc.background)
            }
            .navigationTitle("\u{89c6}\u{9891}")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
