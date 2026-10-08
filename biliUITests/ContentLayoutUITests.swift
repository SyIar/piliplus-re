import XCTest

extension PiliLiquidGlassUITests {
    @MainActor
    func testSearchFiltersFitCollapsedAccessoryAndApplyTogether() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "layoutSearch"]
        app.launch()
        let filters = app.buttons["search.filters.open"]
        XCTAssertTrue(filters.waitForExistence(timeout: 15))
        app.scrollViews.firstMatch.swipeUp()
        XCTAssertTrue(filters.isHittable)
        XCTAssertGreaterThanOrEqual(filters.frame.height, 44)
        XCTAssertGreaterThanOrEqual(filters.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(filters.frame.maxX, app.frame.maxX)
        saveLayoutScreenshot("Search compact filters")
        filters.tap()
        XCTAssertTrue(app.buttons["search.filters.apply"].waitForExistence(timeout: 5))
        saveLayoutScreenshot("Search filter panel")
        app.buttons["search.filters.cancel"].tap()
        XCTAssertTrue(filters.waitForExistence(timeout: 5))
        filters.tap()
        let video = app.buttons["\u{89c6}\u{9891}"].firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 5), app.debugDescription)
        video.tap()
        app.buttons["search.filters.apply"].tap()
        XCTAssertTrue(filters.waitForExistence(timeout: 5))
        XCTAssertTrue((filters.value as? String ?? "").contains("\u{89c6}\u{9891}"), app.debugDescription)
    }

    @MainActor
    func testVideoActionsHaveEqualColumnsAndToolsRemainReachable() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "layoutVideo"]
        app.launch()
        let actions = ["video.actions.like", "video.actions.coin", "video.actions.favorite", "video.tools.more"].map { app.buttons[$0] }
        XCTAssertTrue(actions[0].waitForExistence(timeout: 15))
        for (index, button) in actions.enumerated() {
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            XCTAssertEqual(button.frame.midY, actions[0].frame.midY, accuracy: 1)
            XCTAssertEqual(button.frame.width, actions[0].frame.width, accuracy: 1)
            if index > 0 { XCTAssertGreaterThanOrEqual(button.frame.minX, actions[index - 1].frame.maxX) }
        }
        let follow = app.buttons["video.actions.follow"]
        XCTAssertGreaterThanOrEqual(follow.frame.height, 44)
        XCTAssertLessThan(follow.frame.width, 110)
        saveLayoutScreenshot("Video detail grouped actions")
        let more = app.buttons["video.tools.more"]
        XCTAssertTrue(more.isHittable)
        more.tap()
        XCTAssertTrue(app.buttons["video.tools.close"].waitForExistence(timeout: 5))
        saveLayoutScreenshot("Video detail tools panel")
        XCTAssertTrue(app.buttons["\u{79bb}\u{7ebf}\u{4e0b}\u{8f7d}"].exists)
        app.buttons["video.tools.close"].tap()
        XCTAssertTrue(more.waitForExistence(timeout: 5))
    }

    @MainActor
    func testVideoActionsReflowAtAccessibilityTextSize() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-fixture", "layoutVideo",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        let like = app.buttons["video.actions.like"]
        XCTAssertTrue(like.waitForExistence(timeout: 15))
        app.scrollViews.firstMatch.swipeUp()
        let favorite = app.buttons["video.actions.favorite"]
        XCTAssertTrue(favorite.exists)
        XCTAssertEqual(favorite.frame.minY, like.frame.minY, accuracy: 1)
        XCTAssertGreaterThanOrEqual(favorite.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(favorite.frame.maxX, app.frame.maxX)
        saveLayoutScreenshot("Video detail accessible actions")
        let more = app.buttons["video.tools.more"]
        for _ in 0..<3 where !more.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(more.isHittable)
        more.tap()
        XCTAssertTrue(app.buttons["video.tools.close"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testMineShortcutsAndSettingsDirectoryRemainReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "layoutMine"]
        app.launch()
        let shortcuts = ["offline", "history", "subscriptions", "watchLater"].map { app.buttons["mine.\($0)"] }
        XCTAssertTrue(shortcuts[0].waitForExistence(timeout: 15))
        for shortcut in shortcuts {
            XCTAssertTrue(shortcut.isHittable)
            XCTAssertGreaterThanOrEqual(shortcut.frame.height, 44)
            XCTAssertEqual(shortcut.frame.midY, shortcuts[0].frame.midY, accuracy: 1)
        }
        saveLayoutScreenshot("Mine dashboard")
        app.buttons["mine.settings"].tap()
        let privacy = app.buttons["settings.open.privacy"]
        XCTAssertTrue(privacy.waitForExistence(timeout: 5))
        saveLayoutScreenshot("Settings directory")
        let audio = app.buttons["settings.open.audioVideo"]
        let player = app.buttons["settings.open.player"]
        XCTAssertLessThan(audio.frame.minY, player.frame.minY)
        player.tap()
        XCTAssertTrue(app.switches.firstMatch.waitForExistence(timeout: 5))
        saveLayoutScreenshot("Player settings directory")
    }

    @MainActor
    func testCommentToolbarHasSeparateReachableActions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "layoutComments"]
        app.launch()
        let refresh = app.buttons["video.detail.toolbar-comment-refresh"]
        let compose = app.buttons["video.detail.toolbar-comment-compose"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 15))
        XCTAssertTrue(compose.isHittable)
        XCTAssertLessThan(refresh.frame.maxX, compose.frame.minX)
        XCTAssertEqual(refresh.frame.midY, compose.frame.midY, accuracy: 1)
        XCTAssertGreaterThanOrEqual(refresh.frame.height, 44)
        saveLayoutScreenshot("Comment toolbar single surfaces")
        refresh.tap(); compose.tap()
        XCTAssertEqual(app.staticTexts["fixture.comment.actions"].label, "1 / 1")
    }

    @MainActor
    private func saveLayoutScreenshot(_ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
