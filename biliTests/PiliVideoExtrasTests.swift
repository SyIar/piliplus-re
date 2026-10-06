import XCTest
@testable import bili

@MainActor
final class PiliVideoExtrasTests: XCTestCase {
    func testHighRefreshStopsForBackgroundPowerHeatAndUnsupportedDisplays() {
        XCTAssertEqual(PiliRefreshRatePolicy.preferred(enabled: true, active: true, maximum: 120, lowPower: false, thermal: .nominal), 120)
        XCTAssertNil(PiliRefreshRatePolicy.preferred(enabled: true, active: false, maximum: 120, lowPower: false, thermal: .nominal))
        XCTAssertNil(PiliRefreshRatePolicy.preferred(enabled: true, active: true, maximum: 60, lowPower: false, thermal: .nominal))
        XCTAssertNil(PiliRefreshRatePolicy.preferred(enabled: true, active: true, maximum: 120, lowPower: true, thermal: .nominal))
        XCTAssertNil(PiliRefreshRatePolicy.preferred(enabled: true, active: true, maximum: 120, lowPower: false, thermal: .serious))
        XCTAssertNil(PiliRefreshRatePolicy.preferred(enabled: false, active: true, maximum: 120, lowPower: false, thermal: .nominal))
    }
    func testSearchHistoryIsBoundedPrivateAndDeduplicated() throws {
        let name = "PiliSearchTests.\(UUID().uuidString)"
        // Use a unique domain so tests cannot modify the user's search history.
        let isolated = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { isolated.removePersistentDomain(forName: name) }
        let history = PiliSearchHistory(defaults: isolated)
        for index in 0..<40 { history.record("term \(index)", enabled: true) }
        XCTAssertEqual(history.values.count, 30)
        history.record("term 20", enabled: true)
        XCTAssertEqual(history.values.first, "term 20"); XCTAssertEqual(history.values.filter { $0 == "term 20" }.count, 1)
        history.record("private", enabled: false); XCTAssertFalse(history.values.contains("private"))
        history.record(String(repeating: "a", count: 1_025), enabled: true); XCTAssertEqual(history.values.count, 30)
        history.remove("term 20"); XCTAssertFalse(history.values.contains("term 20"))
        history.clear(); XCTAssertTrue(history.values.isEmpty)
    }
    func testEnergyBucketsLargeInputsAndRejectsInvalidMetadata() throws {
        let values = (0..<10_000).map { DynamicJSONValue.number(String($0)) }
        let raw: DynamicJSONValue = .object(["step_sec": .number("1"), "events": .object(["default": .array(values)])])
        let wrapped: DynamicJSONValue = .object(["modules": .array([.object(["params": .object(["data": raw])])])])
        let energy = try XCTUnwrap(PiliVideoEnergy(wrapped))
        XCTAssertLessThanOrEqual(energy.values.count, 400); XCTAssertEqual(energy.values.last, 1)
        XCTAssertTrue(energy.values.allSatisfy { $0.isFinite && (0...1).contains($0) })
        XCTAssertNil(PiliVideoEnergy(.object(["step_sec": .number("0"), "events": .object(["default": .array(values)])])))
    }
    func testPGCClipParsingIsTolerantAndSurvivesStreamMerge() throws {
        let data = try JSONDecoder().decode(PlayURLData.self, from: Data(#"{"quality":80,"clip_info_list":[{"start":0,"end":90,"clipType":"CLIP_TYPE_OP"},{"start":"bad","clipType":"CLIP_TYPE_ED"},{"start":80,"end":50,"clipType":"CLIP_TYPE_ED"}]}"#.utf8))
        XCTAssertEqual(data.clipInfoList?.filter(\.isValid).count, 1)
        let empty = try JSONDecoder().decode(PlayURLData.self, from: Data("{}".utf8))
        XCTAssertEqual(empty.mergingPlayableStreams(from: data).removingHistoryMetadata().clipInfoList?.first?.end, 90)
        XCTAssertEqual(empty.mergingDisplayFormats(from: data).clipInfoList?.first?.title, "片头")
    }
    func testGesturesSeparateMiddleFullscreenFromSideAdjustmentAndSeeking() {
        let size = CGSize(width: 400, height: 240)
        XCTAssertEqual(PiliPlaybackGesturePolicy.seekOffset(x: 30, width: 400, enabled: true), -10)
        XCTAssertEqual(PiliPlaybackGesturePolicy.seekOffset(x: 370, width: 400, enabled: true), 10)
        XCTAssertNil(PiliPlaybackGesturePolicy.seekOffset(x: 200, width: 400, enabled: true))
        XCTAssertNil(PiliPlaybackGesturePolicy.seekOffset(x: 370, width: 400, enabled: false))
        XCTAssertTrue(PiliPlaybackGesturePolicy.changesFullscreen(startX: 200, size: size, translation: .init(width: 2, height: -100), fullscreen: false))
        XCTAssertFalse(PiliPlaybackGesturePolicy.changesFullscreen(startX: 20, size: size, translation: .init(width: 2, height: -100), fullscreen: false))
        XCTAssertFalse(PiliPlaybackGesturePolicy.changesFullscreen(startX: 200, size: size, translation: .init(width: 90, height: -100), fullscreen: false))
        XCTAssertTrue(PiliPlaybackGesturePolicy.changesFullscreen(startX: 200, size: size, translation: .init(width: 2, height: 100), fullscreen: true))
    }
    func testCommentBadgesNeverTreatMissingVerificationAsOfficial() throws {
        let plain = try JSONDecoder().decode(CommentMember.self, from: Data(#"{"mid":"1","uname":"User"}"#.utf8))
        XCTAssertNil(plain.verificationType); XCTAssertFalse(plain.isVIP)
        let verified = try JSONDecoder().decode(CommentMember.self, from: Data(#"{"mid":"2","vip":{"vipStatus":1},"official_verify":{"type":0},"level_info":{"current_level":6}}"#.utf8))
        XCTAssertEqual(verified.verificationType, 0); XCTAssertTrue(verified.isVIP)
        XCTAssertEqual(verified.levelInfo?.currentLevel, 6)
    }
    func testTripleConfirmationKeepsAlreadyCompletedReactionsAndConfirmedCoinCount() {
        let confirmation = VideoDetailInteractionMutationConfirmation(kind: .triple, state: .init(isLiked: false, coinCount: 2))
        let reconciled = confirmation.reconciling(.init(isLiked: true, coinCount: 1, isFavorited: true))
        XCTAssertTrue(reconciled.isLiked); XCTAssertTrue(reconciled.isFavorited); XCTAssertEqual(reconciled.coinCount, 2)
    }
}
