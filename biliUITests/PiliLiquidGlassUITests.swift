import XCTest

final class PiliLiquidGlassUITests: XCTestCase {
    @MainActor
    func testInteractiveChoicesHotspotsAndCheckpointRestore() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "interactive"]
        app.launch()
        let start = app.buttons["ui.interactive.choice.2"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["ui.interactive.choice.3"].exists, "Locked choices must stay hidden")
        start.tap()
        let hotspot = app.buttons["ui.interactive.choice.4"]
        XCTAssertTrue(hotspot.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(hotspot.isHittable, app.debugDescription)
        XCTAssertEqual(app.staticTexts["ui.interactive.variables"].label, "积分：1")
        app.buttons["ui.interactive.revisit"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["ui.interactive.variables"].label, "积分：0")
        start.tap()
        XCTAssertTrue(hotspot.waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Interactive video glass hotspot choices"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        hotspot.tap()
        XCTAssertTrue(app.staticTexts["ui.interactive.finished"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["ui.interactive.revisit"].isEnabled)
        app.buttons["重新开始"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["ui.interactive.variables"].label, "积分：0")
    }

    @MainActor
    func testCommentTreeFoldingPaginationAndLayoutPreference() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "commentTree", "--ui-test-reset-state"]
        app.launch()
        let child = app.staticTexts["ui.tree.reply.4"]
        XCTAssertTrue(child.waitForExistence(timeout: 15))
        app.buttons["ui.comments.tree.fold.2"].tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: child)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 10), .completed)
        app.buttons["ui.comments.tree.fold.2"].tap()
        XCTAssertTrue(child.waitForExistence(timeout: 10))
        app.buttons["加载下一页"].tap()
        XCTAssertTrue(app.staticTexts["ui.tree.reply.6"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["上级回复尚未加载或已删除"].exists)
        app.segmentedControls.buttons["平铺"].tap()
        app.terminate()
        app.launchArguments = ["--ui-test-fixture", "commentTree"]
        app.launch()
        XCTAssertTrue(app.segmentedControls.buttons["平铺"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.segmentedControls.buttons["平铺"].isSelected)
    }

    @MainActor
    func testFullscreenGlassControlsLockAndSeek() {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launchArguments = ["--ui-test-fixture", "glassPlayer"]
        app.launch()
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 10), .completed)
        XCUIDevice.shared.orientation = .landscapeRight
        let play = app.buttons["ui.player.glass.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["ui.player.glass.lock"].isHittable)
        app.buttons["ui.player.glass.forward"].tap()
        XCTAssertTrue(app.staticTexts["00:52"].waitForExistence(timeout: 3) || app.staticTexts["0:52"].exists)
        play.tap()
        XCTAssertEqual(play.label, "暂停")
        app.buttons["ui.player.glass.lock"].tap()
        let unlock = app.buttons["ui.player.glass.unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 3))
        XCTAssertFalse(play.exists)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.frame.width > app.frame.height, "Lock must prevent device rotation from leaving fullscreen")
        unlock.tap()
        let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.height > app.frame.width }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [portrait], timeout: 8), .completed)
        XCUIDevice.shared.orientation = .landscapeRight
        let landscapeAgain = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscapeAgain], timeout: 8), .completed)
        XCTAssertTrue(play.waitForExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Liquid Glass fullscreen controls"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
    @MainActor
    func testBilingualSubtitleControlsAndColorPersistence() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "subtitles", "--ui-test-reset-state"]
        app.launch()
        XCTAssertTrue(app.staticTexts["ui.subtitle.primary"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["ui.subtitle.secondary"].exists)
        let toggle = app.switches["ui.subtitle.dual"]
        for _ in 0..<4 where !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.isHittable)
        // SwiftUI exposes the entire Form row as a switch; its center is blank.
        // Tap the nested UISwitch, as a user does, and verify the visible result.
        let control = toggle.switches.firstMatch
        XCTAssertTrue(control.isHittable, app.debugDescription)
        control.tap()
        // On a cold hosted simulator, resolving the SwiftUI switch row can take
        // longer than three seconds. Await the rendered subtitle instead of the
        // row's accessibility value; this also verifies that the track loaded.
        XCTAssertTrue(app.staticTexts["ui.subtitle.secondary"].waitForExistence(timeout: 10), app.debugDescription)
        let yellow = app.buttons["ui.subtitle.yellow"]
        for _ in 0..<4 where !yellow.isHittable { app.swipeUp() }
        yellow.tap()
        app.terminate()
        app.launchArguments = ["--ui-test-fixture", "subtitles"]
        app.launch()
        XCTAssertTrue(app.staticTexts["ui.subtitle.secondary"].waitForExistence(timeout: 10))
        let preview = app.descendants(matching: .any)["ui.subtitle.colorPreview"].firstMatch
        for _ in 0..<5 where !preview.isHittable { app.swipeUp() }
        XCTAssertEqual(preview.value as? String, "#FFE080")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Bilingual subtitle colors"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

}
