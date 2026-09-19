import XCTest

@MainActor final class NavigationTests: XCTestCase {
    func testThreeTabsAndPlayerNeverAutoPlays() {
        let app = XCUIApplication(); app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]; app.launch()
        XCTAssertTrue(app.buttons["track.sample-night-window"].waitForExistence(timeout: 10))
        let home = XCTAttachment(screenshot: app.screenshot()); home.name = "M1-English-Discover"; home.lifetime = .keepAlways; add(home)
        app.buttons["track.sample-night-window"].tap()
        XCTAssertTrue(app.staticTexts["playbackUnavailable"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["Fictional local preview. Live music and accounts are not connected."].exists)
        let catalog = app.scrollViews["catalogScreen"]
        XCTAssertTrue(catalog.waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Night")
        let filtered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: catalog.buttons["track.sample-slow-morning"])
        XCTAssertEqual(XCTWaiter.wait(for: [filtered], timeout: 5), .completed)
        XCTAssertEqual(search.value as? String, "Night")
        XCTAssertTrue(catalog.buttons["track.sample-night-window"].exists)
        let closeSearch = app.buttons["Close"].exists ? app.buttons["Close"] : app.buttons["Cancel"]
        closeSearch.tap()
        app.tabBars.buttons["You"].tap()
        XCTAssertTrue(app.staticTexts["Listening as a guest"].exists)
        XCTAssertTrue(app.buttons["miniPlayer"].exists)
        XCTAssertLessThanOrEqual(app.buttons["miniPlayer"].frame.maxY, app.tabBars.firstMatch.frame.minY + 1, "Mini player must not obscure the tab bar")
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "M1-English-You"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testHistoryPreferencePersistsAndClearRequiresConfirmation() {
        let app = XCUIApplication(); app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["You"].waitForExistence(timeout: 10)); app.tabBars.buttons["You"].tap()
        let toggle = app.switches["Save listening history"]
        for _ in 0..<5 { if toggle.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(toggle.isHittable)
        let original = toggle.value as? String
        if original == "1" { toggle.switches.firstMatch.tap() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '0'"), object: toggle)], timeout: 5), .completed, "Wait for durable setting before terminating")
        app.terminate(); app.launch(); app.tabBars.buttons["You"].tap()
        for _ in 0..<5 { if toggle.isHittable { break }; app.swipeUp() }
        XCTAssertEqual(toggle.value as? String, "0")
        app.buttons["Clear listening history"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5)); app.buttons["Cancel"].tap()
        if original == "1" {
            toggle.switches.firstMatch.tap()
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: toggle)], timeout: 5), .completed)
        }
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "M5-Settings"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testFourLocalesAndLargestDynamicType() {
        for locale in ["zh-Hans", "zh-Hant", "en", "ja"] {
            let app = XCUIApplication(); app.launchArguments = ["-AppleLanguages", "(\(locale))", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
            XCTAssertTrue(app.buttons["track.sample-night-window"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.tabBars.buttons.count, 3)
            let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "M1-\(locale)-AXXXL"; attachment.lifetime = .keepAlways; add(attachment)
            app.terminate()
        }
    }
}
