import XCTest
import UIKit
import PiliPlaybackCore
@testable import bili

@MainActor
final class PiliSubtitleAndOrientationTests: XCTestCase {
    func testExactDirectionLockSurvivesPolicyUpdatesAndRejectsRotation() {
        let coordinator = PlaybackRotationCoordinator()
        defer { coordinator.deactivate(in: nil) }
        coordinator.activate(isLandscape: true)
        coordinator.allowLandscape(in: nil)
        coordinator.setControlsLocked(true, orientation: .landscapeLeft)
        XCTAssertEqual(AppOrientationLock.supportedOrientations, .landscapeLeft)
        coordinator.updateOrientationLock(isPortraitVideo: false, isCurrentlyLandscape: true, in: nil)
        XCTAssertEqual(AppOrientationLock.supportedOrientations, .landscapeLeft)
        XCTAssertFalse(coordinator.requestGeometryUpdate(to: .landscapeRight, in: nil))
        XCTAssertFalse(coordinator.requestGeometryUpdate(to: .portrait, in: nil))
        coordinator.setControlsLocked(false)
        XCTAssertEqual(AppOrientationLock.supportedOrientations, .allButUpsideDown)
        coordinator.setControlsLocked(true, locksOrientation: false, orientation: .landscapeRight)
        XCTAssertNil(coordinator.lockedOrientation)
        coordinator.deactivate(in: nil)
        XCTAssertEqual(AppOrientationLock.supportedOrientations, .portrait)
    }

    func testBilingualTimelinesSelectionPersistenceAndReset() throws {
        let name = "subtitle-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let zh = PiliSubtitleTrack(lan: "zh", lanDoc: "中文", subtitleURL: nil, type: 0)
        let en = PiliSubtitleTrack(lan: "en", lanDoc: "English", subtitleURL: nil, type: 0)
        let values = [PiliCachedSubtitle(track: zh, cues: [.init(from: 0, to: 2, content: "你好")]),
                      PiliCachedSubtitle(track: en, cues: [.init(from: 1, to: 3, content: "Hello")])]
        let controller = PiliSubtitleController(defaults: defaults)
        controller.loadOffline(values)
        controller.setDualEnabled(true)
        controller.selectSecondary(en.id)
        XCTAssertEqual(controller.selectedID, zh.id)
        XCTAssertEqual(controller.secondaryID, en.id)
        XCTAssertEqual(controller.timeline.active(at: 0.5).map(\.content), ["你好"])
        XCTAssertTrue(controller.secondaryTimeline.active(at: 0.5).isEmpty)
        XCTAssertEqual(controller.secondaryTimeline.active(at: 2).map(\.content), ["Hello"])
        XCTAssertTrue(controller.timeline.active(at: 2).isEmpty)
        let exported = try controller.export(vtt: true, secondary: true)
        defer { try? FileManager.default.removeItem(at: exported) }
        XCTAssertTrue(try String(contentsOf: exported, encoding: .utf8).contains("Hello"))
        let restored = PiliSubtitleController(defaults: defaults)
        restored.loadOffline(values)
        XCTAssertTrue(restored.dualEnabled)
        XCTAssertEqual(restored.secondaryID, en.id)
        restored.select(en.id)
        XCTAssertNotEqual(restored.selectedID, restored.secondaryID)
        restored.select(nil)
        XCTAssertNil(restored.secondaryID)
        XCTAssertTrue(restored.secondaryTimeline.cues.isEmpty)
        restored.loadOffline([])
        XCTAssertTrue(restored.timeline.cues.isEmpty)
        XCTAssertTrue(restored.secondaryTimeline.cues.isEmpty)
    }

    func testDualSubtitlesDoNotEnableAIUnderNonAIPreferenceOrDuplicateOneTrack() throws {
        let name = "subtitle-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let controller = PiliSubtitleController(defaults: defaults)
        controller.loadOffline([
            .init(track: .init(lan: "zh", lanDoc: "中文", subtitleURL: nil, type: 0), cues: []),
            .init(track: .init(lan: "ai-en", lanDoc: "English", subtitleURL: nil, type: 1), cues: [])
        ])
        controller.setDualEnabled(true)
        XCTAssertNotNil(controller.selectedID)
        XCTAssertNil(controller.secondaryID)
        controller.setDualEnabled(false)
        XCTAssertTrue(controller.secondaryTimeline.cues.isEmpty)
    }
}
