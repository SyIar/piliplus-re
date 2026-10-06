import Foundation
import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var videos: [VideoItem] = []
    private(set) var videoCells: [HomeVideoCellModel] = []
    @Published private(set) var lastSeenMarkerIndex: Int?
    @Published var state: LoadingState = .loading
    @Published var mode: HomeFeedMode = .recommend
    @Published var isRefreshing = false
    @Published var isUserRefreshing = false

    static let userRefreshRecommendationCount = 10
    private let libraryStore: LibraryStore
    private let sessionStore: SessionStore
    var requestRevision = 0
    var lastUserRefreshDate: Date?
    var modeSwitchRefreshPending = false
    var retainedRecommendVideos = [VideoItem]()
    var retainedRecommendLastSeenMarkerIndex: Int?
    private var recommendContextCancellable: AnyCancellable?
    let pageCoordinator: HomeFeedPageCoordinator
    let snapshotCoordinator: HomeFeedSnapshotCoordinator
    let mediaPreloadCoordinator: HomeFeedMediaPreloadCoordinator
    let exposureRecorder: HomeFeedExposureRecorder
    var cellStore = HomeFeedCellStore()
    var recommendMetadataHydrationTasks: [String: Task<Void, Never>] = [:]

    init(
        api: BiliAPIClient,
        libraryStore: LibraryStore,
        sessionStore: SessionStore,
        initialMode: HomeFeedMode = .recommend
    ) {
        self.libraryStore = libraryStore
        self.sessionStore = sessionStore
        pageCoordinator = HomeFeedPageCoordinator(
            api: api,
            libraryStore: libraryStore
        )
        snapshotCoordinator = HomeFeedSnapshotCoordinator(
            libraryStore: libraryStore,
            sessionStore: sessionStore
        )
        mediaPreloadCoordinator = HomeFeedMediaPreloadCoordinator(
            api: api,
            libraryStore: libraryStore
        )
        exposureRecorder = HomeFeedExposureRecorder(pageCoordinator: pageCoordinator)
        mode = initialMode
        recommendContextCancellable = Publishers.CombineLatest4(
            libraryStore.$guestModeEnabled,
            libraryStore.$homeRecommendFeedSourcePreference,
            sessionStore.$sessdata,
            sessionStore.$accessKey
        )
            .removeDuplicates { lhs, rhs in
                lhs.0 == rhs.0 && lhs.1 == rhs.1 && lhs.2 == rhs.2 && lhs.3 == rhs.3
            }
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.reloadForRecommendContextChange() }
            }
    }

    deinit {
        recommendMetadataHydrationTasks.values.forEach { $0.cancel() }
    }

    func updateFeed(
        _ newVideos: [VideoItem],
        lastSeenMarkerIndex markerIndex: Int? = nil,
        blockedUserIDs: Set<Int>? = nil
    ) {
        // Refreshes, cached snapshots and metadata hydration can outlive a filter change.
        // Recheck at the commit boundary, including retained cards from older requests.
        var configuration = libraryStore.videoRecommendationFilterConfiguration
        if let blockedUserIDs { configuration.blockedUserIDs = blockedUserIDs }
        let dismissed = PiliFeedDismissals.shared.ids(account: pageCoordinator.api.requestSnapshot().currentUserMID ?? 0)
        let filtered = VideoRecommendationFilter.filtered(newVideos, configuration: configuration, context: .feed)
            .filter { !dismissed.contains($0.bvid) }
        let filteredMarker = markerIndex.flatMap { index -> Int? in
            guard index > 0, index < newVideos.count else { return nil }
            let retainedIDs = Set(filtered.map(\.id))
            return newVideos.prefix(index).filter { retainedIDs.contains($0.id) }.count
        }
        videoCells = cellStore.update(with: filtered)
        videos = filtered
        updateLastSeenMarkerIndex(filteredMarker)
        if !filtered.isEmpty {
            StageOneBaselineMetricsStore.shared.markHomeFirstData()
        }
    }

    func updateLastSeenMarkerIndex(_ index: Int?) {
        guard let index, index > 0, index < videos.count else {
            lastSeenMarkerIndex = nil
            return
        }
        lastSeenMarkerIndex = index
    }

    func recordRecommendExposure(_ video: VideoItem, index: Int) {
        guard mode == .recommend else { return }
        HomeRecommendFeedbackCenter.shared.recordExposure(
            video: video,
            index: index,
            source: libraryStore.homeRecommendFeedSourcePreference
        )
    }

    func updateImagePrefetchProfile(_ profile: HomeFeedCoverPrefetchProfile) {
        mediaPreloadCoordinator.updateImagePrefetchProfile(profile)
        mediaPreloadCoordinator.scheduleImagePrefetch(for: videos)
    }

    func scheduleImageLookahead(visibleIndex: Int) {
        mediaPreloadCoordinator.scheduleImageLookahead(for: videos, visibleIndex: visibleIndex)
    }

    func recordRecommendClick(_ video: VideoItem) {
        guard mode == .recommend else { return }
        HomeRecommendFeedbackCenter.shared.recordClick(
            video: video,
            source: libraryStore.homeRecommendFeedSourcePreference
        )
    }

}
