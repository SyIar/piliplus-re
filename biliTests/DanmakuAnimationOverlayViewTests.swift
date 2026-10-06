import XCTest
import UIKit
@testable import bili

final class DanmakuAnimationOverlayViewTests: XCTestCase {
    @MainActor
    func testMergingCanBeToggledWithoutReloadingItems() {
        let view = DanmakuAnimationOverlayView(frame: CGRect(x: 0, y: 0, width: 640, height: 360))
        view.layoutIfNeeded()
        let items = [
            DanmakuItem(id: "one", time: 1, mode: 5, fontSize: 25, color: 0xFFFFFF, text: "相同弹幕", senderHash: "a"),
            DanmakuItem(id: "two", time: 2, mode: 5, fontSize: 25, color: 0xFFFFFF, text: "相同弹幕", senderHash: "b")
        ]
        var settings = DanmakuSettings.default
        settings.mergesDuplicates = true
        func apply() {
            view.apply(items: items, itemsRevision: 1, currentTime: 3, isPlaying: false, playbackRate: 1,
                       isEnabled: true, hasPresentedPlayback: true, isLoadShedding: false,
                       settings: settings, topInset: 8, bottomInset: 54)
        }
        apply()
        XCTAssertTrue(view.subviews.compactMap { ($0 as? UILabel)?.text }.contains("相同弹幕 ×2"))
        settings.mergesDuplicates = false
        apply()
        XCTAssertFalse(view.subviews.compactMap { ($0 as? UILabel)?.text }.contains("相同弹幕 ×2"))
        XCTAssertTrue(view.subviews.compactMap { ($0 as? UILabel)?.text }.contains("相同弹幕"))
        view.stop()
    }

    @MainActor
    func testLayoutTransitionPreservesActiveLabelAndAnimation() throws {
        let view = DanmakuAnimationOverlayView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        view.layoutIfNeeded()
        view.apply(
            items: [DanmakuItem(id: "rotation", time: 1, mode: 5, fontSize: 25, color: 0x00FF_FFFF, text: "rotation")],
            itemsRevision: 1,
            currentTime: 2,
            isPlaying: true,
            playbackRate: 1,
            isEnabled: true,
            hasPresentedPlayback: true,
            isLoadShedding: false,
            settings: .default,
            topInset: 8,
            bottomInset: 54
        )

        let label = try XCTUnwrap(view.subviews.compactMap { $0 as? UILabel }.first)
        let portraitCenter = label.center
        XCTAssertNotNil(label.layer.animation(forKey: "danmaku.opacity"))

        view.setLayoutTransitioning(true)
        view.frame = CGRect(x: 0, y: 0, width: 640, height: 360)
        view.layoutIfNeeded()

        XCTAssertEqual(label.center, portraitCenter)

        view.setLayoutTransitioning(false)

        XCTAssertTrue(view.subviews.contains { $0 === label })
        XCTAssertEqual(label.center, portraitCenter)
        XCTAssertNotNil(label.layer.animation(forKey: "danmaku.opacity"))
    }
}
