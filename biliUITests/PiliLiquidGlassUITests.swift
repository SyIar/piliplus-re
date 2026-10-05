import XCTest

final class PiliLiquidGlassUITests: XCTestCase {
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
        // Tap the nested UISwitch, as a user does, and verify it changed state.
        let control = toggle.switches.firstMatch
        XCTAssertTrue(control.isHittable, app.debugDescription)
        control.tap()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 3), .completed, app.debugDescription)
        XCTAssertTrue(app.staticTexts["ui.subtitle.secondary"].waitForExistence(timeout: 3), app.debugDescription)
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
