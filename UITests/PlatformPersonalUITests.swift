import XCTest

@MainActor final class PlatformPersonalUITests: XCTestCase {
    private let ids = ["bbbbbbbb-0000-4000-8000-000000000010", "bbbbbbbb-0000-4000-8000-000000000020"]
    private func launch(locale: String = "zh-Hans", large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--platform-music-fixture", "-AppleLanguages", "(\(locale))", "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launchEnvironment["STATION_PLATFORM_FIXTURE"] = "catalog-categories"
        app.launchEnvironment["STATION_PERSONAL_TEST_NAMESPACE"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        return app
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<12 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func seed(_ app: XCUIApplication) {
        app.tabBars.buttons.element(boundBy: 1).tap()
        for id in ids {
            let track = app.buttons["track." + id]; reveal(track, app: app); track.tap()
            let favorite = app.buttons["platformFavorite"]
            XCTAssertTrue(favorite.waitForExistence(timeout: 5))
            // Wait for the verified listening action, not the removed section heading.
            XCTAssertTrue(app.buttons["platformLink.netease"].waitForExistence(timeout: 5))
            if favorite.value as? String != "开启" && favorite.value as? String != "On" { favorite.tap() }
            app.buttons["platformDetailClose"].tap()
        }
        app.tabBars.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(app.buttons["favoritesEntry"].waitForExistence(timeout: 5))
    }
    func testPersonalHubNavigationPrivacyPreferenceAndNotes() {
        let app = launch()
        seed(app)
        capture(app, "My-Hub-zh-Hans")
        XCTAssertFalse(app.buttons["accountEntry"].exists); XCTAssertFalse(app.buttons["historyEntry"].exists)
        XCTAssertFalse(app.buttons["offlineEntry"].exists); XCTAssertFalse(app.buttons["miniPlayer"].exists)
        app.buttons["viewedEntry"].tap()
        XCTAssertTrue(app.buttons["viewed.track." + ids[0]].waitForExistence(timeout: 5))
        capture(app, "My-Recently-Viewed")
        let clear = app.buttons["clearViewed"]; reveal(clear, app: app); clear.tap()
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["viewed.track." + ids[0]].exists)
        let toggle = app.switches["saveViewed"]; reveal(toggle, app: app)
        XCTAssertEqual(toggle.value as? String, "1")
        // SwiftUI exposes a labelled row and the actual switch as nested elements.
        // Tapping the row centre can hit its label instead of changing the switch.
        let control = toggle.switches.firstMatch
        if control.exists { control.tap() } else { toggle.tap() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '0'"), object: toggle)], timeout: 5), .completed)
        XCTAssertTrue(app.staticTexts["浏览记录已关闭。"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["viewed.track." + ids[0]].exists)
        app.navigationBars.buttons.firstMatch.tap()
        let preferred = app.buttons["platformPreferenceEntry"]; reveal(preferred, app: app); preferred.tap()
        app.buttons["platformPreference.spotify"].tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '开启'"), object: app.buttons["platformPreference.spotify"])], timeout: 5), .completed)
        capture(app, "My-Platform-Preference")
        app.navigationBars.buttons.firstMatch.tap()
        reveal(app.buttons["settingsHelpEntry"], app: app); app.buttons["settingsHelpEntry"].tap()
        XCTAssertFalse(app.buttons["offlineEntry"].exists); XCTAssertFalse(app.buttons["accountEntry"].exists)
        app.buttons["helpEntry"].tap(); app.buttons["releaseNotesEntry"].tap()
        XCTAssertTrue(app.staticTexts["Station Cat Music · 1.0.2 (15)"].waitForExistence(timeout: 5))
        capture(app, "My-1.0.2-Build15-Notes")
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10)); app.tabBars.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(app.staticTexts["Spotify"].exists)
        XCTAssertTrue(app.staticTexts["浏览记录已关闭。"].exists)
        app.buttons["favoritesEntry"].tap()
        XCTAssertTrue(app.buttons["library.track." + ids[0]].exists)
    }
    func testBrowsingRelaunchOfflineStillShowsEntriesWithoutListeningLinks() {
        let app = launch(); seed(app); app.terminate()
        app.launchEnvironment["STATION_STARTUP_PREVIEW"] = "failure"
        app.launch(); XCTAssertTrue(app.buttons["startupContinue"].waitForExistence(timeout: 10)); app.buttons["startupContinue"].tap()
        app.tabBars.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(app.buttons["viewed.track." + ids[0]].exists)
        capture(app, "My-Offline")
        app.buttons["viewed.track." + ids[0]].tap()
        XCTAssertTrue(app.buttons["platformDetailRetry"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["platformLink.netease"].exists); XCTAssertFalse(app.buttons["miniPlayer"].exists)
    }
    func testHubFourLanguagesAndAccessibilityText() {
        for locale in ["zh-Hans", "zh-Hant", "en", "ja"] {
            let app = launch(locale: locale, large: true)
            app.tabBars.buttons.element(boundBy: 2).tap()
            XCTAssertTrue(app.buttons["favoritesEntry"].waitForExistence(timeout: 5))
            capture(app, "My-Empty-" + locale + "-AXXXL")
            app.buttons["favoritesEntry"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["favoritesPage"].firstMatch.waitForExistence(timeout: 5))
            app.navigationBars.buttons.firstMatch.tap()
            reveal(app.buttons["platformPreferenceEntry"], app: app); app.buttons["platformPreferenceEntry"].tap()
            reveal(app.buttons["platformPreference.spotify"], app: app)
            capture(app, "My-Preference-" + locale + "-AXXXL")
            XCTAssertTrue(app.tabBars.buttons.element(boundBy: 2).isHittable)
            app.terminate()
        }
    }
}
