import XCTest
@testable import bili

final class PlayerPlaybackControlsVisibilityModelTests: XCTestCase {
    @MainActor
    func testSecondaryMenuSuspendsAutoHideAndClosingItResumesTheTimer() async throws {
        let model = PlayerPlaybackControlsVisibilityModel()
        model.showAndSchedule(showsPlaybackControls: true, isLayoutTransitioning: false)
        model.syncSecondaryControlsPresentation(true, showsPlaybackControls: true, isLayoutTransitioning: false)
        // A playback interaction while the menu is open must not rearm hiding.
        model.markInteraction(showsPlaybackControls: true, isLayoutTransitioning: false)
        try await Task.sleep(for: .milliseconds(3600))
        XCTAssertTrue(model.isVisible)
        XCTAssertEqual(model.opacity, 1)

        model.syncSecondaryControlsPresentation(false, showsPlaybackControls: true, isLayoutTransitioning: false)
        for _ in 0..<50 where model.isVisible { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertFalse(model.isVisible)
        XCTAssertFalse(model.acceptsHitTesting)
    }

    @MainActor
    func testImmediateHideRemovesControlsWithoutTransitionDelay() {
        let model = PlayerPlaybackControlsVisibilityModel()

        model.hide(animated: false)

        XCTAssertFalse(model.isVisible)
        XCTAssertEqual(model.opacity, 0)
        XCTAssertFalse(model.acceptsHitTesting)
    }

    @MainActor
    func testAnimatedHideKeepsControlsTouchableDuringFade() async throws {
        let model = PlayerPlaybackControlsVisibilityModel()

        model.hide(animated: true)

        XCTAssertTrue(model.isVisible)
        XCTAssertEqual(model.opacity, 0)
        XCTAssertTrue(model.acceptsHitTesting)

        for _ in 0..<12 where model.isVisible {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTAssertFalse(model.isVisible)
        XCTAssertFalse(model.acceptsHitTesting)
    }

    @MainActor
    func testShowCancelsPendingAnimatedHideRemoval() async throws {
        let model = PlayerPlaybackControlsVisibilityModel()

        model.hide(animated: true)
        model.show(
            scheduleAutoHide: false,
            animated: false,
            showsPlaybackControls: true
        )

        try await Task.sleep(nanoseconds: 420_000_000)

        XCTAssertTrue(model.isVisible)
        XCTAssertEqual(model.opacity, 1)
        XCTAssertTrue(model.acceptsHitTesting)
    }
}
