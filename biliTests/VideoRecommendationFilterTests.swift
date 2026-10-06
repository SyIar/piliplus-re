import XCTest
@testable import bili

final class VideoRecommendationFilterTests: XCTestCase {
    func testInactiveConfigurationKeepsVideosInFeedAndRelated() {
        let videos = [
            video("BV1", title: "短视频", duration: 20, view: 10, like: 0),
            video("BV2", title: "正常视频", duration: 120, view: 1_000, like: 40)
        ]
        let configuration = VideoRecommendationFilterConfiguration(
            minimumDurationSeconds: 0,
            minimumViewCount: 0,
            minimumLikeRatioPercent: 0,
            blockedKeywords: [],
            appliesToRelatedVideos: false
        )

        XCTAssertEqual(
            VideoRecommendationFilter.filtered(videos, configuration: configuration, context: .feed),
            videos
        )
        XCTAssertEqual(
            VideoRecommendationFilter.filtered(videos, configuration: configuration, context: .related),
            videos
        )
    }

    func testFeedFiltersByDurationViewsLikeRatioAndTitleKeyword() {
        let videos = [
            video("BV1", title: "太短", duration: 30, view: 1_000, like: 50),
            video("BV2", title: "播放太低", duration: 120, view: 100, like: 50),
            video("BV3", title: "点赞太低", duration: 120, view: 1_000, like: 10),
            video("BV4", title: "广告合集", duration: 120, view: 1_000, like: 50),
            video("BV5", title: "保留", duration: 120, view: 1_000, like: 50)
        ]
        let configuration = VideoRecommendationFilterConfiguration(
            minimumDurationSeconds: 60,
            minimumViewCount: 500,
            minimumLikeRatioPercent: 2,
            blockedKeywords: ["广告"],
            appliesToRelatedVideos: false
        )

        XCTAssertEqual(
            VideoRecommendationFilter.filtered(videos, configuration: configuration, context: .feed).map(\.bvid),
            ["BV5"]
        )
    }

    func testRelatedFilteringRequiresRelatedToggle() {
        let videos = [
            video("BV1", title: "播放太低", duration: 120, view: 100, like: 50),
            video("BV2", title: "保留", duration: 120, view: 1_000, like: 50)
        ]
        let disabledConfiguration = VideoRecommendationFilterConfiguration(
            minimumDurationSeconds: 0,
            minimumViewCount: 500,
            minimumLikeRatioPercent: 0,
            blockedKeywords: [],
            appliesToRelatedVideos: false
        )
        let enabledConfiguration = VideoRecommendationFilterConfiguration(
            minimumDurationSeconds: 0,
            minimumViewCount: 500,
            minimumLikeRatioPercent: 0,
            blockedKeywords: [],
            appliesToRelatedVideos: true
        )

        XCTAssertEqual(
            VideoRecommendationFilter.filtered(videos, configuration: disabledConfiguration, context: .related).map(\.bvid),
            ["BV1", "BV2"]
        )
        XCTAssertEqual(
            VideoRecommendationFilter.filtered(videos, configuration: enabledConfiguration, context: .related).map(\.bvid),
            ["BV2"]
        )
    }

    func testBlacklistedAuthorsRemainHiddenWhenOtherRelatedFiltersAreOff() throws {
        let videos = try JSONDecoder().decode([VideoItem].self, from: Data(#"[{"bvid":"BV-blocked","title":"blocked","owner":{"mid":9,"name":"blocked"}},{"bvid":"BV-kept","title":"kept","owner":{"mid":10,"name":"kept"}}]"#.utf8))
        let configuration = VideoRecommendationFilterConfiguration(minimumDurationSeconds: 0, minimumViewCount: 0,
            minimumLikeRatioPercent: 0, blockedKeywords: [], appliesToRelatedVideos: false, blockedUserIDs: [9])
        XCTAssertEqual(VideoRecommendationFilter.filtered(videos, configuration: configuration, context: .feed).map(\.bvid), ["BV-kept"])
        XCTAssertEqual(VideoRecommendationFilter.filtered(videos, configuration: configuration, context: .related).map(\.bvid), ["BV-kept"])
        let privacy = try XCTUnwrap(PiliSpacePrivacyField.all.first { $0.id == "disable_following" })
        XCTAssertTrue(privacy.isOn(0)); XCTAssertEqual(privacy.value(true), 0); XCTAssertEqual(privacy.value(false), 1)
    }

    @MainActor
    func testStaleFeedCommitRechecksFiltersAndRemapsSeenBoundary() throws {
        let suiteName = "PiliFeedCommitTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let library = LibraryStore(userDefaults: defaults)
        let session = SessionStore(keychain: KeychainStore(service: suiteName))
        let api = BiliAPIClient(sessionStore: session, libraryStore: library, homeRecommendDiagnosticsStore: .shared)
        let model = HomeViewModel(api: api, libraryStore: library, sessionStore: session)
        let snapshot = try JSONDecoder().decode([VideoItem].self, from: Data(#"[{"bvid":"BV-new","title":"new","owner":{"mid":10}},{"bvid":"BV-ad-new","title":"广告 new","owner":{"mid":9}},{"bvid":"BV-new2","title":"new2","owner":{"mid":11}},{"bvid":"BV-ad-old","title":"广告 old","owner":{"mid":9}},{"bvid":"BV-old","title":"old","owner":{"mid":12}}]"#.utf8))

        model.updateFeed(snapshot, lastSeenMarkerIndex: 3, blockedUserIDs: [])
        XCTAssertEqual(model.videos.count, 5)
        XCTAssertEqual(model.lastSeenMarkerIndex, 3)

        // An earlier request/cached snapshot arrives after the user changes filtering.
        library.setBlockedRecommendKeywords(["广告"])
        model.updateFeed(snapshot, lastSeenMarkerIndex: 3, blockedUserIDs: [])
        XCTAssertEqual(model.videos.map(\.bvid), ["BV-new", "BV-new2", "BV-old"])
        XCTAssertEqual(model.videoCells.count, 3)
        XCTAssertEqual(model.lastSeenMarkerIndex, 2)

        // The @Published blacklist callback carries the next value before storage updates.
        library.setBlockedRecommendKeywords([])
        model.updateFeed(snapshot, lastSeenMarkerIndex: 3, blockedUserIDs: [9])
        XCTAssertEqual(model.videos.map(\.bvid), ["BV-new", "BV-new2", "BV-old"])
        XCTAssertEqual(model.lastSeenMarkerIndex, 2)
        model.updateFeed(snapshot, lastSeenMarkerIndex: 3, blockedUserIDs: [9, 10, 11])
        XCTAssertEqual(model.videos.map(\.bvid), ["BV-old"])
        XCTAssertNil(model.lastSeenMarkerIndex)
    }

    private func video(
        _ bvid: String,
        title: String,
        duration: Int,
        view: Int,
        like: Int
    ) -> VideoItem {
        VideoItem(
            bvid: bvid,
            aid: nil,
            title: title,
            pic: nil,
            desc: nil,
            duration: duration,
            pubdate: nil,
            owner: nil,
            stat: VideoStat(view: view, reply: nil, like: like, coin: nil, favorite: nil),
            cid: nil,
            pages: nil,
            dimension: nil
        )
    }
}
