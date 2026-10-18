import XCTest

@MainActor final class PlatformContentUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private func launch(locale: String = "zh-Hans", failure: Bool = false, large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--platform-music-fixture", "-platformLyricsFontSize", "18", "-AppleLanguages", "(\(locale))", "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launchEnvironment["STATION_PLATFORM_FIXTURE"] = failure ? "song-content-failure" : "song-content"
        app.launchEnvironment["STATION_PERSONAL_TEST_NAMESPACE"] = UUID().uuidString
        app.launch()
        let open = app.buttons["platformFeaturedOpen"]
        XCTAssertTrue(open.waitForExistence(timeout: 10)); reveal(open, app); open.tap()
        XCTAssertTrue(app.buttons["contentTab.lyrics"].waitForExistence(timeout: 10))
        return app
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<10 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    private func top(_ app: XCUIApplication) { for _ in 0..<6 { app.swipeDown() } }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testSelectedContentLayoutReadingSizeAndEmptyClips() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["lyricStanza.0"].waitForExistence(timeout: 5))
        capture(app, "Content-Lyrics-zh-Hans")
        XCTAssertTrue(app.buttons["platformLink.netease"].isHittable)
        XCTAssertTrue(app.buttons["platformShare"].exists)
        XCTAssertEqual(app.sliders.count, 0); XCTAssertFalse(app.buttons["miniPlayer"].exists)
        reveal(app.buttons["lyricTextSize"], app); app.buttons["lyricTextSize"].tap()
        app.buttons["更大"].tap()
        XCTAssertTrue(app.staticTexts["lyricStanza.0"].exists)
        capture(app, "Content-Lyrics-Large")
        reveal(app.buttons["lyricsExpand"], app); app.buttons["lyricsExpand"].tap()
        XCTAssertTrue(app.staticTexts["lyricStanza.2"].exists)
        top(app); reveal(app.buttons["contentTab.clips"], app); app.buttons["contentTab.clips"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["clipsEmpty"].firstMatch.waitForExistence(timeout: 5))
        capture(app, "Content-Clips-Empty")
        app.buttons["contentTab.story"].tap()
        XCTAssertTrue(app.staticTexts["contentStoryText"].waitForExistence(timeout: 5))
        capture(app, "Content-Story")
        app.buttons["platformDetailClose"].tap()
        XCTAssertTrue(app.buttons["platformFeaturedOpen"].waitForExistence(timeout: 5))
    }
    func testLyricsFailureCanRetryWithoutLosingListeningOrOtherTabs() {
        let app = launch(failure: true)
        XCTAssertTrue(app.buttons["lyricsRetry"].waitForExistence(timeout: 5))
        capture(app, "Content-Lyrics-Retry")
        XCTAssertTrue(app.buttons["platformLink.netease"].exists)
        app.buttons["contentTab.clips"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["clipsEmpty"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["contentTab.lyrics"].tap()
        reveal(app.buttons["lyricsRetry"], app); app.buttons["lyricsRetry"].tap()
        XCTAssertTrue(app.staticTexts["lyricStanza.0"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["lyricsRetry"].exists)
    }
    func testFourLocalesAndAccessibilitySizesKeepTabsReachable() {
        for locale in ["zh-Hans", "zh-Hant", "en", "ja"] {
            let app = launch(locale: locale, large: true)
            reveal(app.buttons["platformLink.netease"], app)
            capture(app, "Content-" + locale + "-Large-Header")
            reveal(app.buttons["contentTab.clips"], app); app.buttons["contentTab.clips"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["clipsEmpty"].firstMatch.waitForExistence(timeout: 5))
            reveal(app.buttons["contentTab.story"], app); app.buttons["contentTab.story"].tap()
            XCTAssertTrue(app.staticTexts["contentStoryText"].waitForExistence(timeout: 5))
            reveal(app.staticTexts["contentStoryText"], app)
            capture(app, "Content-" + locale + "-Large-Story")
            app.buttons["platformDetailClose"].tap(); app.terminate()
        }
    }
}
