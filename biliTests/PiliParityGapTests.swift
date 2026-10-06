import XCTest
@testable import bili

@MainActor
final class PiliParityGapTests: XCTestCase {
    func testDanmakuUIDHashAndRulesUseUnmergedContent() throws {
        XCTAssertEqual(PiliDanmakuRule.userHash(123), "884863d2")
        XCTAssertEqual(try PiliDanmakuRule.input(" 123 ", type: 2), "884863d2")
        let matcher = PiliDanmakuRuleMatcher([
            .init(id: 1, type: 0, filter: "广告"), .init(id: 2, type: 1, filter: "^测试\\d+$"),
            .init(id: 3, type: 2, filter: "884863d2")])
        func item(_ text: String, hash: String? = nil) -> DanmakuItem {
            .init(id: text, time: 1, mode: 1, fontSize: 25, color: 0xffffff, text: text, senderHash: hash, mergeCount: 3)
        }
        XCTAssertTrue(matcher.blocks(item("这是广告")))
        XCTAssertTrue(matcher.blocks(item("测试123")))
        XCTAssertTrue(matcher.blocks(item("正常内容", hash: "884863D2")))
        XCTAssertFalse(matcher.blocks(item("测试文字")))
        XCTAssertFalse(matcher.blocks(item("正常内容")))
        XCTAssertThrowsError(try PiliDanmakuRule.input("[", type: 1))
        XCTAssertThrowsError(try PiliDanmakuRule.input("0", type: 2))
        XCTAssertThrowsError(try PiliDanmakuRule.input(" ", type: 0))
    }

    func testAppRecommendationMetadataSurvivesConversionCacheAndDetailMerge() throws {
        let json = #"{"param":"123","card_goto":"av","title":"测试","rcmd_reason":"已关注","args":{"up_id":42,"tname":"单机游戏","rname":"游戏"},"three_point_v2":[{"type":"dislike","reasons":[{"id":1,"name":"不感兴趣"},{"id":1,"name":"重复"}]},{"type":"feedback","reasons":[{"id":2,"name":"标题问题"}]}]}"#
        let feed = try JSONDecoder().decode(RecommendFeedItem.self, from: Data(json.utf8))
        let video = try XCTUnwrap(feed.asVideoItem())
        XCTAssertNil(video.recommendReason)
        XCTAssertEqual(video.piliRecommendation?.followed, true)
        XCTAssertEqual(video.piliRecommendation?.zone, "单机游戏 游戏")
        XCTAssertEqual(video.piliRecommendation?.reasons.map(\.parameter), ["reason_id", "feedback_id"])
        let cached = try JSONDecoder().decode(HomeFeedCachedVideo.self, from: JSONEncoder().encode(HomeFeedCachedVideo(video: video)))
        XCTAssertEqual(cached.videoItem.piliRecommendation, video.piliRecommendation)
        let full = try JSONDecoder().decode(VideoItem.self, from: Data(#"{"bvid":"BVfull","title":"完整详情"}"#.utf8))
        XCTAssertEqual(video.mergingFilledValues(from: full).piliRecommendation, video.piliRecommendation)
    }

    func testFollowExemptionDoesNotOverrideBlacklistOrRelatedFilters() throws {
        let feed = try JSONDecoder().decode(RecommendFeedItem.self, from: Data(#"{"param":"123","title":"广告123","duration":5,"is_followed":1,"args":{"up_id":42,"tname":"游戏"}}"#.utf8))
        let video = try XCTUnwrap(feed.asVideoItem())
        var config = VideoRecommendationFilterConfiguration(minimumDurationSeconds: 60, minimumViewCount: 0,
            minimumLikeRatioPercent: 0, blockedKeywords: [], appliesToRelatedVideos: true,
            advanced: .init(titlePattern: "广告\\d+", zonePattern: "游戏", exemptsFollowed: true))
        XCTAssertEqual(VideoRecommendationFilter.filtered([video], configuration: config, context: .feed).count, 1)
        XCTAssertTrue(VideoRecommendationFilter.filtered([video], configuration: config, context: .related).isEmpty)
        config.blockedUserIDs = [42]
        XCTAssertTrue(VideoRecommendationFilter.filtered([video], configuration: config, context: .feed).isEmpty)
    }

    func testZoneAndTitleRegularExpressionsFilterIndependently() throws {
        let video = try XCTUnwrap(JSONDecoder().decode(RecommendFeedItem.self,
            from: Data(#"{"param":"123","title":"Sponsor 42","args":{"tname":"游戏"}}"#.utf8)).asVideoItem())
        for rule in [PiliAdvancedRecommendFilter(titlePattern: "sponsor\\s+\\d+"), .init(zonePattern: "游戏|娱乐")] {
            let config = VideoRecommendationFilterConfiguration(minimumDurationSeconds: 0, minimumViewCount: 0,
                minimumLikeRatioPercent: 0, blockedKeywords: [], appliesToRelatedVideos: false, advanced: rule)
            XCTAssertTrue(VideoRecommendationFilter.filtered([video], configuration: config, context: .feed).isEmpty)
            XCTAssertEqual(VideoRecommendationFilter.filtered([video], configuration: config, context: .related), [video])
        }
    }

    func testAIConclusionHandlesUnavailableAndMalformedTimePoints() throws {
        let raw = try JSONDecoder().decode(DynamicJSONValue.self, from: Data(#"{"code":0,"model_result":{"summary":"摘要","outline":[{"title":"第一章","part_outline":[{"timestamp":65,"content":"重点"},{"timestamp":-1,"content":"负数"},{"content":"缺少时间"}]}]}}"#.utf8))
        let result = try PiliAIConclusion(raw)
        XCTAssertEqual(result.summary, "摘要")
        XCTAssertEqual(result.outline.first?.points.map(\.seconds), [65])
        XCTAssertThrowsError(try PiliAIConclusion(.object(["code": .number("-1")])))
        XCTAssertTrue(try PiliAIConclusion(.object(["code": .number("0")])).isEmpty)
    }

    func testLiveCDNRetainsSignedPathQualityAndFallback() throws {
        let url = try XCTUnwrap(URL(string: "https://origin.example/live/stream.m3u8?token=a%2Bb&qn=400"))
        let candidate = LiveStreamURLCandidate(url: url, protocolName: "http_hls", formatName: "fmp4", codecName: "avc",
            currentQN: 400, qualityTitle: "蓝光", source: "web")
        let settings = PiliLivePlaybackPreferences(quality: 400, cellularQuality: 150, cdnHost: "cdn.example")
        let candidates = settings.candidates([candidate])
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates[0].url.host, "cdn.example")
        XCTAssertEqual(URLComponents(url: candidates[0].url, resolvingAgainstBaseURL: false)?.percentEncodedQuery, "token=a%2Bb&qn=400")
        XCTAssertEqual(candidates[0].currentQN, 400)
        XCTAssertEqual(candidates[1], candidate)
        XCTAssertEqual(settings.preferredQuality(cellular: true), 150)
        XCTAssertEqual(settings.preferredQuality(cellular: false), 400)
        for host in ["https://cdn.example", "cdn.example/path", "user@cdn.example", "cdn.example:443", "cdn.example?x=1"] {
            XCTAssertNil(PiliLivePlaybackPreferences.host(host))
        }
    }

    func testSettingsPersistPerAccountAndRejectInvalidRegexWithoutReplacement() throws {
        let suite = "PiliParityGapTests.\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LibraryStore(userDefaults: defaults)
        store.setQuickFavoriteFolder(12, account: 1); store.setQuickFavoriteFolder(34, account: 2)
        let rules = PiliAdvancedRecommendFilter(titlePattern: "^广告", zonePattern: "游戏", exemptsFollowed: true)
        try store.setAdvancedRecommendFilter(rules)
        XCTAssertThrowsError(try store.setAdvancedRecommendFilter(.init(titlePattern: "[")))
        try store.setLivePlaybackPreferences(.init(quality: 10000, cellularQuality: 150))
        let restored = LibraryStore(userDefaults: defaults)
        XCTAssertEqual(restored.quickFavoriteFolder(account: 1), 12)
        XCTAssertEqual(restored.quickFavoriteFolder(account: 2), 34)
        XCTAssertEqual(restored.quickFavoriteFolder(account: 0), 0)
        XCTAssertEqual(restored.advancedRecommendFilter, rules)
        XCTAssertEqual(restored.livePlaybackPreferences.cellularQuality, 150)
    }
}
