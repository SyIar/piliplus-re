import XCTest

final class PiliLiquidGlassUITests: XCTestCase {
    func testFullscreenGlassControlsLockAndSeek() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "glassPlayer"]
        app.launch()
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 10), .completed)
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
        unlock.tap()
        XCTAssertTrue(play.waitForExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Liquid Glass fullscreen controls"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
