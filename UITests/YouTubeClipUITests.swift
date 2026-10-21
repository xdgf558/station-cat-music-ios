import XCTest

@MainActor final class YouTubeClipUITests: XCTestCase {
    private let clip = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
    override func setUp() { continueAfterFailure = false }
    private func launch(locale: String = "zh-Hans", failure: Bool = false, large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--platform-music-fixture", "-AppleLanguages", "(\(locale))", "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launchEnvironment["STATION_PLATFORM_FIXTURE"] = failure ? "youtube-error" : "youtube-clips"
        app.launchEnvironment["STATION_PERSONAL_TEST_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["STATION_PLATFORM_OPEN_FAIL"] = "1" // Never leaves the local fixture.
        app.launch()
        let open = app.buttons["platformFeaturedOpen"]
        XCTAssertTrue(open.waitForExistence(timeout: 10)); reveal(open, app); open.tap()
        let tab = app.buttons["contentTab.clips"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10)); reveal(tab, app); tab.tap()
        capture(app, "YouTube-Initial-" + locale)
        let found = app.buttons["youtubeLoad." + clip].waitForExistence(timeout: 5)
        if !found { print(app.debugDescription) }
        XCTAssertTrue(found)
        return app
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<12 {
            // Accessibility layout keeps listening above the tabs. Scroll in
            // either direction, and do not tap underneath the navigation bar.
            let frame = element.frame
            if element.isHittable && frame.midY > 140 && frame.midY < app.frame.height - 40 { return }
            if frame.midY < 140 { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }
    private func top(_ app: XCUIApplication) { for _ in 0..<5 { app.swipeDown() } }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let item = XCTAttachment(screenshot: app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
    func testSelectedLayoutClickToLoadAndTabBackgroundDismissTeardown() {
        let app = launch()
        XCTAssertFalse(app.webViews.firstMatch.exists)
        XCTAssertFalse(app.buttons["miniPlayer"].exists)
        XCTAssertTrue(app.buttons["youtubeOpen." + clip].isHittable, "External fallback should fit above the listening footer at the standard text size")
        XCTAssertLessThanOrEqual(app.buttons["youtubeOpen." + clip].frame.maxY, app.buttons["platformLink.netease"].frame.minY)
        capture(app, "YouTube-Selected-Layout-zh-Hans")
        app.buttons["youtubePrivacyInfo"].tap()
        XCTAssertTrue(app.buttons["youtubePrivacyClose"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews.firstMatch.exists)
        capture(app, "YouTube-Privacy-Notice")
        app.buttons["youtubePrivacyClose"].tap()
        let load = app.buttons["youtubeLoad." + clip]
        reveal(load, app); load.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.webViews.staticTexts["未连接 YouTube · 无真实视频"].waitForExistence(timeout: 10))
        capture(app, "YouTube-Local-Player-Fixture")
        top(app); app.buttons["contentTab.story"].tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["contentStoryText"].waitForExistence(timeout: 5))
        app.buttons["contentTab.clips"].tap(); reveal(load, app); load.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.webViews.firstMatch.waitForNonExistence(timeout: 5))
        reveal(load, app); load.tap(); XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        app.buttons["platformDetailClose"].tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["platformFeaturedOpen"].waitForExistence(timeout: 5))
    }
    func testEmbedFailureOffersRetryAndExternalFallbackWithoutBreakingSong() {
        let app = launch(failure: true)
        let load = app.buttons["youtubeLoad." + clip]; reveal(load, app); load.tap()
        XCTAssertTrue(app.buttons["youtubeRetry"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.webViews.firstMatch.exists)
        reveal(app.buttons["youtubeRetry"], app); capture(app, "YouTube-Embedding-Unavailable")
        let external = app.buttons["youtubeOpen." + clip]; reveal(external, app); external.tap()
        XCTAssertTrue(app.buttons["platformCopyLink"].waitForExistence(timeout: 5))
        top(app); app.buttons["contentTab.lyrics"].tap()
        XCTAssertTrue(app.staticTexts["lyricStanza.0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["platformLink.netease"].exists)
    }
    func testFourLocalesLargeTextCanReachSourceFallbackAndListening() {
        for locale in ["zh-Hans", "zh-Hant", "en", "ja"] {
            let app = launch(locale: locale, large: true)
            let load = app.buttons["youtubeLoad." + clip]; reveal(load, app)
            capture(app, "YouTube-" + locale + "-Accessibility")
            reveal(app.buttons["youtubeOpen." + clip], app)
            reveal(app.buttons["platformLink.netease"], app)
            XCTAssertTrue(app.buttons["platformLink.netease"].isHittable)
            XCTAssertFalse(app.webViews.firstMatch.exists)
            let info = app.buttons["youtubePrivacyInfo"]; reveal(info, app); info.tap()
            XCTAssertTrue(app.buttons["youtubePrivacyClose"].waitForExistence(timeout: 5))
            reveal(app.buttons["youtubePrivacy"], app)
            XCTAssertTrue(app.buttons["youtubePrivacy"].isHittable)
            capture(app, "YouTube-Privacy-" + locale + "-Accessibility")
            app.buttons["youtubePrivacyClose"].tap()
            app.terminate()
        }
    }
}
