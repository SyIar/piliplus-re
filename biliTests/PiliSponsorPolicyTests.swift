import XCTest
@testable import bili

final class PiliSponsorPolicyTests: XCTestCase {
    func testMutePoliciesRespectEndBoundariesPreviewAndManualSelection() {
        let segment = SponsorBlockSegment(uuid: "1", category: "sponsor", actionType: "mute", startTime: 10, endTime: 20, videoDuration: nil, votes: nil)
        XCTAssertFalse(PiliSponsorRules.shouldMute(at: 9.99, segments: [segment], automaticCategories: ["sponsor"]))
        XCTAssertTrue(PiliSponsorRules.shouldMute(at: 10, segments: [segment], automaticCategories: ["sponsor"]))
        XCTAssertFalse(PiliSponsorRules.shouldMute(at: 20, segments: [segment], automaticCategories: ["sponsor"]))
        XCTAssertFalse(PiliSponsorRules.shouldMute(at: 15, segments: [segment], automaticCategories: []))
        XCTAssertTrue(PiliSponsorRules.shouldMute(at: 15, segments: [segment], automaticCategories: [], manualIDs: ["1"]))
        XCTAssertFalse(PiliSponsorRules.shouldMute(at: 15, segments: [segment], automaticCategories: ["sponsor"], ignoredIDs: ["1"]))
        XCTAssertFalse(PiliSponsorRules.shouldMute(at: .nan, segments: [segment], automaticCategories: ["sponsor"]))
    }
    @MainActor
    func testTemporaryMuteNeverChangesUserMuteIntentAndRestoresOnDisable() {
        let preferences = PiliSponsorPreferences.shared
        let previous = preferences.mode("sponsor")
        defer { preferences.set(previous, category: "sponsor") }
        preferences.set(.automatic, category: "sponsor")
        let engine = PlayerLifecycleEngineSpy(isPlaying: false)
        let player = PlayerStateViewModel(videoURL: nil, audioURL: nil, title: "Sponsor test", referer: "https://www.bilibili.com", engine: engine)
        defer { player.stop() }
        let segment = SponsorBlockSegment(uuid: "1", category: "sponsor", actionType: "mute", startTime: 0, endTime: 100, videoDuration: nil, votes: nil)
        player.setSponsorBlockSegments([segment], isEnabled: true)
        XCTAssertTrue(engine.isMuted)
        XCTAssertFalse(player.isMuted)
        player.setSponsorBlockEnabled(false)
        XCTAssertFalse(engine.isMuted)
        player.setMuted(true)
        player.setSponsorBlockEnabled(true)
        player.setSponsorBlockEnabled(false)
        XCTAssertTrue(engine.isMuted)
        XCTAssertTrue(player.isMuted)
        player.setMuted(false)
        preferences.set(.manual, category: "sponsor")
        player.setSponsorBlockSegments([segment], isEnabled: true)
        XCTAssertFalse(engine.isMuted)
        player.manuallyMuteSponsorBlockSegment(segment)
        XCTAssertTrue(engine.isMuted)
        XCTAssertFalse(player.isMuted)
        player.setSponsorBlockEnabled(false)
        XCTAssertFalse(engine.isMuted)
    }
    @MainActor
    func testFullscreenFontIsIndependentAndDefaultKeepsExistingPreferences() {
        var settings = DanmakuSettings.default
        settings.fontScale = 0.8
        XCTAssertEqual(settings.usingFullscreenFont(1.4, enabled: false, isFullscreen: true).fontScale, 0.8)
        XCTAssertEqual(settings.usingFullscreenFont(1.4, enabled: true, isFullscreen: false).fontScale, 0.8)
        XCTAssertEqual(settings.usingFullscreenFont(1.4, enabled: true, isFullscreen: true).fontScale, 1.4)
        XCTAssertEqual(settings.usingFullscreenFont(.nan, enabled: true, isFullscreen: true).fontScale, 0.8)
        XCTAssertEqual(settings.fontScale, 0.8)
    }
    func testExplicitFullscreenDirectionTakesPriorityAndAutomaticKeepsOrientation() {
        let policy = VideoDetailRotationPolicy()
        XCTAssertEqual(policy.preferredLandscapeInterfaceOrientation(currentInterfaceOrientation: .landscapeLeft, deviceOrientation: .portrait, preference: .landscapeRight), .landscapeRight)
        XCTAssertEqual(policy.preferredLandscapeInterfaceOrientation(currentInterfaceOrientation: .portrait, deviceOrientation: .landscapeLeft, preference: .landscapeLeft), .landscapeLeft)
        XCTAssertEqual(policy.preferredLandscapeInterfaceOrientation(currentInterfaceOrientation: .landscapeLeft, deviceOrientation: .portrait), .landscapeLeft)
        XCTAssertEqual(policy.preferredLandscapeInterfaceOrientation(currentInterfaceOrientation: .portrait, deviceOrientation: .landscapeLeft), .landscapeRight)
    }
}
