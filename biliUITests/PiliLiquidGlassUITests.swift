import XCTest

final class PiliLiquidGlassUITests: XCTestCase {
    @MainActor
    func testSearchHistoryTapSubmitsAndKeepsCategoriesSeparate() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "searchHistory"]
        app.launch()
        let history = app.buttons["search.history.History demo"]
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        let clear = app.buttons["search.history.clear"]
        let heading = app.staticTexts["\u{641c}\u{7d22}\u{5386}\u{53f2}"]
        XCTAssertEqual(clear.frame.midY, heading.frame.midY, accuracy: 2)
        let historyScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        historyScreenshot.name = "Search history single header row"
        historyScreenshot.lifetime = .keepAlways
        add(historyScreenshot)
        app.searchFields.firstMatch.tap()
        XCTAssertTrue(history.isHittable)
        history.tap()
        XCTAssertTrue(app.staticTexts["History demo video"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "History demo")
        XCTAssertTrue(app.buttons["search.tab.video"].isSelected)
        XCTAssertFalse(app.staticTexts["History demo uploader"].exists)
        app.buttons["search.tab.user"].tap()
        XCTAssertTrue(app.staticTexts["History demo uploader"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.staticTexts["History demo video"].exists)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Search history submission and category tabs"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testGlassSheetsNestReopenReplaceAndProtectBusyWork() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "glassAudit"]
        app.launch()
        let open = app.buttons["glass.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()
        let nested = app.buttons["glass.nested"]
        XCTAssertTrue(nested.waitForExistence(timeout: 10), app.debugDescription)
        nested.tap()
        let innerClose = app.buttons["glass.inner.close"]
        XCTAssertTrue(innerClose.waitForExistence(timeout: 10), app.debugDescription)
        innerClose.tap()
        XCTAssertTrue(nested.waitForExistence(timeout: 10))
        app.buttons["glass.close"].tap()
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        XCTAssertTrue(nested.waitForExistence(timeout: 10))
        app.buttons["glass.replace"].tap()
        XCTAssertTrue(app.navigationBars["\u{64ad}\u{653e}\u{8bbe}\u{7f6e} 2"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["glass.busy"].tap()
        app.navigationBars["\u{64ad}\u{653e}\u{8bbe}\u{7f6e} 2"].swipeDown()
        XCTAssertTrue(app.buttons["glass.busy"].exists)
        XCTAssertFalse(app.buttons["glass.close"].isEnabled)
        app.buttons["glass.busy"].tap()
        app.buttons["glass.expand"].tap()
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "ChunUI nested glass sheet"; screenshot.lifetime = .keepAlways; add(screenshot)
        let note = app.textFields["glass.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        note.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        note.typeText("glass")
        XCTAssertEqual(note.value as? String, "glass")
        XCTAssertLessThanOrEqual(note.frame.maxY, app.keyboards.firstMatch.frame.minY + 1,
                                 "The full-height sheet must still keep its editor above the keyboard")
        app.buttons["glass.close"].tap()
        XCTAssertTrue(open.waitForExistence(timeout: 10))
    }

    @MainActor
    func testGlassConfirmationPreservesTargetAndExecutesOnce() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "glassAudit"]
        app.launch()
        let remove = app.buttons["glass.delete"]
        XCTAssertTrue(remove.waitForExistence(timeout: 15))
        app.buttons["glass.settings"].tap()
        let swatches = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\u{9009}\u{62e9}\u{989c}\u{8272} #"))
        let theme = app.buttons["settings.theme"]
        XCTAssertTrue(theme.waitForExistence(timeout: 10))
        XCTAssertFalse(swatches.firstMatch.exists, "The parent settings page keeps the color editor collapsed")
        theme.tap()
        XCTAssertTrue(swatches.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(swatches.count, 8)
        let rowY = swatches.firstMatch.frame.midY
        for swatch in swatches.allElementsBoundByIndex {
            XCTAssertTrue(swatch.isHittable)
            XCTAssertEqual(swatch.frame.midY, rowY, accuracy: 1, "All eight colors must fit one row")
        }
        app.buttons["\u{9009}\u{62e9}\u{989c}\u{8272} #AF52DE"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["\u{754c}\u{9762}\u{8bbe}\u{7f6e}"].waitForExistence(timeout: 10))
        XCTAssertEqual(theme.value as? String, "#AF52DE", "The parent row must expose the selected color")
        app.navigationBars.buttons.firstMatch.tap()
        remove.tap()
        XCTAssertTrue(app.buttons["\u{53d6}\u{6d88}"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["\u{53d6}\u{6d88}"].firstMatch.tap()
        XCTAssertTrue(remove.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["glass.deleted"].label, "\u{5df2}\u{5220}\u{9664} 0 \u{6b21}")
        remove.tap()
        XCTAssertTrue(app.buttons["\u{786e}\u{8ba4}\u{5220}\u{9664}"].waitForExistence(timeout: 10))
        let themedAlert = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        themedAlert.name = "Confirmation follows the selected purple theme"
        themedAlert.lifetime = .keepAlways
        add(themedAlert)
        app.buttons["\u{786e}\u{8ba4}\u{5220}\u{9664}"].tap()
        let once = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "\u{5df2}\u{5220}\u{9664} 1 \u{6b21}"), object: app.staticTexts["glass.deleted"])
        XCTAssertEqual(XCTWaiter.wait(for: [once], timeout: 10), .completed)
        remove.tap()
        XCTAssertTrue(app.buttons["\u{53d6}\u{6d88}"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["\u{53d6}\u{6d88}"].firstMatch.tap()
        XCTAssertEqual(app.staticTexts["glass.deleted"].label, "\u{5df2}\u{5220}\u{9664} 1 \u{6b21}")
        remove.tap()
        XCTAssertTrue(app.buttons["\u{786e}\u{8ba4}\u{5220}\u{9664}"].waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["\u{786e}\u{8ba4}\u{5220}\u{9664}"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)
        remove.tap()
        XCTAssertTrue(app.buttons["\u{53d6}\u{6d88}"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["\u{53d6}\u{6d88}"].firstMatch.tap()
        XCTAssertEqual(app.staticTexts["glass.deleted"].label, "\u{5df2}\u{5220}\u{9664} 1 \u{6b21}")
        app.buttons["glass.settings"].tap()
        XCTAssertTrue(theme.waitForExistence(timeout: 10))
        theme.tap()
        XCTAssertTrue(app.buttons["\u{9009}\u{62e9}\u{989c}\u{8272} #3264F0"].waitForExistence(timeout: 10))
        app.buttons["\u{9009}\u{62e9}\u{989c}\u{8272} #3264F0"].tap()
    }

    @MainActor
    func testRecommendationMenuDoesNotStartPlaybackAndOpensExistingActions() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "glassFeed"]
        app.launch()
        let menu = app.buttons["video.menu.BV1fixture001"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15), app.debugDescription)
        let second = app.buttons["video.menu.BV1fixture002"]
        XCTAssertEqual(menu.frame.midY, second.frame.midY, accuracy: 1)
        XCTAssertLessThan(menu.frame.maxX, second.frame.minX)
        menu.tap()
        XCTAssertTrue(app.buttons["\u{590d}\u{5236} BV \u{53f7}"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["\u{4e0d}\u{611f}\u{5174}\u{8da3}"].exists)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Recommendation card overflow menu"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["\u{590d}\u{5236} BV \u{53f7}"].tap()
        XCTAssertEqual(app.staticTexts["glass.feed.activity"].label, "\u{64ad}\u{653e} 0 · \u{9884}\u{70ed} 0")
        menu.tap()
        app.buttons["\u{8bbf}\u{95ee} UP \u{4e3b}"].tap()
        XCTAssertTrue(app.staticTexts["glass.feed.owner"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["glass.feed.activity"].label, "\u{64ad}\u{653e} 0 · \u{9884}\u{70ed} 0")
        menu.tap()
        app.buttons["\u{4e0d}\u{611f}\u{5174}\u{8da3}"].tap()
        XCTAssertTrue(app.navigationBars["\u{63a8}\u{8350}\u{4e0e}\u{89c6}\u{9891}\u{53cd}\u{9988}"].waitForExistence(timeout: 10))
        app.buttons["\u{5b8c}\u{6210}"].tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        app.buttons["video.open.BV1fixture001"].tap()
        XCTAssertTrue(app.staticTexts["glass.feed.activity"].label.hasPrefix("\u{64ad}\u{653e} 1"))
    }

    @MainActor
    func testGlassSelectionAndAccessibleSettingsNavigation() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "glassAudit", "--glass-reduce-transparency",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let list = app.buttons["\u{591a}\u{9009}\u{5217}\u{8868}"]
        XCTAssertTrue(list.waitForExistence(timeout: 15), app.debugDescription)
        list.tap()
        app.staticTexts["\u{4e0b}\u{8f7d}\u{4e00}"].tap()
        XCTAssertTrue(app.navigationBars["\u{5df2}\u{9009}\u{62e9} 1 \u{9879}"].waitForExistence(timeout: 10), app.debugDescription)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["glass.settings"].tap()
        XCTAssertTrue(app.navigationBars["\u{754c}\u{9762}\u{8bbe}\u{7f6e}"].waitForExistence(timeout: 10))
        let iconTitle = app.staticTexts["\u{5e94}\u{7528}\u{56fe}\u{6807}"].firstMatch
        XCTAssertTrue(iconTitle.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(iconTitle.frame.width, iconTitle.frame.height,
                             "Large text must not force a short setting title into a vertical column")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Settings with large text and reduced transparency"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    @MainActor
    func testLiveSuperChatRetainsExpiredMessagesInHistory() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "superChat"]
        app.launch()
        XCTAssertTrue(app.staticTexts["\u{6e05}\u{6670}\u{7684}\u{753b}\u{9762}，\u{4e5f}\u{8981}\u{6e05}\u{6670}\u{5730}\u{5448}\u{73b0}\u{6bcf}\u{4e00}\u{6761}\u{7559}\u{8a00}。"].waitForExistence(timeout: 15))
        let expired = app.staticTexts["\u{8fd9}\u{6761}\u{7559}\u{8a00}\u{5df2}\u{7ecf}\u{7ed3}\u{675f}\u{5c55}\u{793a}，\u{4ecd}\u{53ef}\u{5728}\u{5386}\u{53f2}\u{4e2d}\u{67e5}\u{770b}。"]
        XCTAssertFalse(expired.exists)
        app.segmentedControls.buttons["\u{5168}\u{90e8}"].tap()
        XCTAssertTrue(expired.waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Live Super Chat cards and history"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.segmentedControls.buttons["\u{5173}\u{95ed}"].tap()
        XCTAssertTrue(app.staticTexts["\u{9192}\u{76ee}\u{7559}\u{8a00}\u{5df2}\u{5173}\u{95ed}"].waitForExistence(timeout: 10))
        XCTAssertFalse(expired.exists)
        app.segmentedControls.buttons["\u{6709}\u{6548}"].tap()
    }

    @MainActor
    func testCompleteContentExportCreatesShareablePages() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "contentExport"]
        app.launch()
        let save = app.buttons["\u{4fdd}\u{5b58}\u{5168}\u{90e8}\u{5230}\u{76f8}\u{518c}"]
        XCTAssertTrue(save.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(app.buttons["\u{5206}\u{4eab}\u{56fe}\u{7247}"].exists)
        XCTAssertFalse(app.buttons["\u{91cd}\u{8bd5}"].exists)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Complete content image export"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    @MainActor
    func testDynamicComposerEditsTitleMentionsAndSubmitsThroughFixtureTransport() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "dynamicComposer"]
        app.launch()
        let title = app.textFields["\u{6807}\u{9898}（\u{53ef}\u{9009}）"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        title.tap(); title.typeText("Simulator draft")
        app.buttons["\u{63d0}\u{53ca}\u{7528}\u{6237}"].tap()
        let user = app.buttons["\u{6d4b}\u{8bd5}\u{7528}\u{6237}"]
        XCTAssertTrue(user.waitForExistence(timeout: 10), app.debugDescription)
        user.tap()
        let publish = app.buttons["pili.dynamic.publish"]
        XCTAssertTrue(publish.waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Native dynamic composer with mention"; screenshot.lifetime = .keepAlways; add(screenshot)
        publish.tap()
        XCTAssertTrue(app.staticTexts["fixture.dynamic.published"].waitForExistence(timeout: 15), app.debugDescription)
    }

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
        XCTAssertEqual(app.staticTexts["ui.interactive.variables"].label, "\u{79ef}\u{5206}：1")
        app.buttons["ui.interactive.revisit"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["ui.interactive.variables"].label, "\u{79ef}\u{5206}：0")
        start.tap()
        XCTAssertTrue(hotspot.waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Interactive video glass hotspot choices"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        hotspot.tap()
        XCTAssertTrue(app.staticTexts["ui.interactive.finished"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["ui.interactive.revisit"].isEnabled)
        app.buttons["\u{91cd}\u{65b0}\u{5f00}\u{59cb}"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["ui.interactive.variables"].label, "\u{79ef}\u{5206}：0")
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
        app.buttons["\u{52a0}\u{8f7d}\u{4e0b}\u{4e00}\u{9875}"].tap()
        XCTAssertTrue(app.staticTexts["ui.tree.reply.6"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["\u{4e0a}\u{7ea7}\u{56de}\u{590d}\u{5c1a}\u{672a}\u{52a0}\u{8f7d}\u{6216}\u{5df2}\u{5220}\u{9664}"].exists)
        app.segmentedControls.buttons["\u{5e73}\u{94fa}"].tap()
        app.terminate()
        app.launchArguments = ["--ui-test-fixture", "commentTree"]
        app.launch()
        XCTAssertTrue(app.segmentedControls.buttons["\u{5e73}\u{94fa}"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.segmentedControls.buttons["\u{5e73}\u{94fa}"].isSelected)
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
        app.buttons["ui.player.glass.more"].tap()
        XCTAssertTrue(app.buttons["ui.player.glass.forward"].waitForExistence(timeout: 5))
        app.buttons["ui.player.glass.forward"].tap()
        let time = app.descendants(matching: .any)["player.playback.time"].firstMatch
        let seekCompleted = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "0:52"), object: time
        )
        XCTAssertEqual(XCTWaiter.wait(for: [seekCompleted], timeout: 5), .completed, app.debugDescription)
        play.tap()
        XCTAssertEqual(play.label, "\u{6682}\u{505c}")
        app.buttons["ui.player.glass.more"].tap()
        XCTAssertTrue(app.navigationBars["\u{66f4}\u{591a}\u{64ad}\u{653e}\u{64cd}\u{4f5c}"].waitForExistence(timeout: 5))
        let settings = app.buttons["ui.player.more.settings"]
        for _ in 0..<4 where !settings.isHittable { app.swipeUp() }
        XCTAssertTrue(settings.isHittable)
        let timer = app.buttons["ui.player.more.timer"]
        for _ in 0..<4 where !timer.isHittable { app.swipeUp() }
        XCTAssertTrue(timer.isHittable)
        XCTAssertTrue(app.buttons["ui.player.more.share"].exists)
        let actionsPanel = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        actionsPanel.name = "Fullscreen player action panel"
        actionsPanel.lifetime = .keepAlways
        add(actionsPanel)
        app.buttons["\u{5b8c}\u{6210}"].tap()
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        app.buttons["ui.player.glass.more"].tap()
        let cast = app.buttons["ui.player.more.cast"]
        for _ in 0..<4 where !cast.isHittable { app.swipeUp() }
        XCTAssertTrue(cast.isHittable)
        cast.tap()
        XCTAssertTrue(app.buttons["\u{597d}"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["\u{6295}\u{5c4f}"].exists)
        app.buttons["\u{597d}"].tap()
        XCTAssertTrue(app.buttons["ui.player.glass.lock"].waitForExistence(timeout: 5))
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
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: toggle)
        if XCTWaiter.wait(for: [enabled], timeout: 3) != .completed {
            // A hosted simulator can lose the first touch while presenting the Form.
            // Drag the actual thumb; never change the fixture's state from the test.
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: control.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        }
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
