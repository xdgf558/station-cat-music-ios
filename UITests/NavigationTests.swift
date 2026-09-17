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
