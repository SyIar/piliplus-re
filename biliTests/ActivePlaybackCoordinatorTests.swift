import XCTest
import UIKit
@testable import bili

@MainActor
final class ActivePlaybackCoordinatorTests: XCTestCase {
    func testCancelledNavigationRestoresActivePlayerIntent() {
        let coordinator = ActivePlaybackCoordinator.shared
        coordinator.stopActivePlayback()
        defer { coordinator.stopActivePlayback() }

        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "Navigation recovery",
            referer: "https://www.bilibili.com"
        )
        let surface = VideoSurfaceContainerView()
        player.attachSurface(surface, prefersNativePlaybackControls: false)
        player.play()

        XCTAssertTrue(coordinator.isActive(player))
        XCTAssertTrue(player.wantsAutoplay)

        coordinator.pauseActivePlaybackForNavigation()

        XCTAssertFalse(player.wantsAutoplay)
        let pendingResumeState = player.pendingNavigationResumeState()
        XCTAssertNotNil(pendingResumeState)
        XCTAssertTrue(pendingResumeState?.shouldResumePlayback == true)
        XCTAssertTrue(coordinator.resumeActivePlaybackAfterCancelledNavigation())
        XCTAssertTrue(coordinator.isActive(player))
        XCTAssertTrue(player.wantsAutoplay)
    }

    func testCancelledNavigationWithoutActivePlayerDoesNothing() {
        let coordinator = ActivePlaybackCoordinator.shared
        coordinator.stopActivePlayback()

        XCTAssertFalse(coordinator.resumeActivePlaybackAfterCancelledNavigation())
    }

    func testGlobalAppBackgroundPreservesRecordedVideoWithoutRecovery() {
        let coordinator = ActivePlaybackCoordinator.shared
        coordinator.stopActivePlayback()
        defer { coordinator.stopActivePlayback() }

        let engine = PlayerLifecycleEngineSpy(isPlaying: true)
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "Global background playback",
            referer: "https://www.bilibili.com",
            engine: engine
        )
        let surface = VideoSurfaceContainerView()
        player.attachSurface(surface, prefersNativePlaybackControls: false)
        coordinator.activate(player)
        player.setPlaybackIntent(true)
        engine.onFirstFrame?(12)

        XCTAssertFalse(coordinator.pauseActivePlaybackForAppBackground())
        XCTAssertTrue(player.wantsAutoplay)
        XCTAssertTrue(engine.hasMedia)
        XCTAssertEqual(engine.backgroundPauseCallCount, 0)
        XCTAssertEqual(engine.pauseCallCount, 0)
        XCTAssertFalse(player.resumePlaybackAfterAppBackgroundIfNeeded())
        XCTAssertFalse(player.prepareStoppedPlaybackAfterAppBackgroundIfNeeded())
        XCTAssertEqual(engine.videoOutputRefreshCallCount, 0)
        XCTAssertEqual(engine.pausedPlaybackWarmCallCount, 0)
        XCTAssertEqual(engine.playerItemRecoveryCallCount, 0)
        XCTAssertEqual(engine.seekCallCount, 0)
        XCTAssertTrue(player.wantsAutoplay)
    }

    func testAppDelegateBackgroundCallbacksPreservePlayingAndPausedIntent() {
        let coordinator = ActivePlaybackCoordinator.shared
        coordinator.stopActivePlayback()
        defer { coordinator.stopActivePlayback() }

        let engine = PlayerLifecycleEngineSpy(isPlaying: true)
        let player = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "App delegate background playback",
            referer: "https://www.bilibili.com",
            engine: engine
        )
        let surface = VideoSurfaceContainerView()
        player.attachSurface(surface, prefersNativePlaybackControls: false)
        coordinator.activate(player)
        player.setPlaybackIntent(true)

        let appDelegate = AppDelegate()
        appDelegate.applicationDidEnterBackground(UIApplication.shared)
        appDelegate.applicationProtectedDataWillBecomeUnavailable(UIApplication.shared)

        XCTAssertEqual(engine.backgroundPauseCallCount, 0)
        XCTAssertEqual(engine.pauseCallCount, 0)
        XCTAssertTrue(player.wantsAutoplay)
        XCTAssertTrue(engine.hasMedia)

        player.pause()
        let playCalls = engine.playCallCount
        appDelegate.applicationDidEnterBackground(UIApplication.shared)
        appDelegate.applicationProtectedDataWillBecomeUnavailable(UIApplication.shared)

        XCTAssertFalse(player.wantsAutoplay)
        XCTAssertEqual(engine.playCallCount, playCalls)
        XCTAssertEqual(engine.pauseCallCount, 1)
        XCTAssertEqual(engine.backgroundPauseCallCount, 0)
        XCTAssertEqual(engine.seekCallCount, 0)
        XCTAssertEqual(engine.playerItemRecoveryCallCount, 0)
        XCTAssertFalse(player.resumePlaybackAfterAppBackgroundIfNeeded())
    }
}
