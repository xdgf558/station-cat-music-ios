import XCTest

@MainActor final class PlatformMusicUITests: XCTestCase {
    private let firstID = "11111111-1111-4111-8111-111111111111"
    private let secondID = "22222222-2222-4222-8222-222222222222"
    private func launch(locale: String = "en", fixture: String = "normal", largeText: Bool = false, failOpen: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--platform-music-fixture", "-AppleLanguages", "(\(locale))", "-UIPreferredContentSizeCategoryName",
            largeText ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launchEnvironment["STATION_PLATFORM_FIXTURE"] = fixture
        if failOpen { app.launchEnvironment["STATION_PLATFORM_OPEN_FAIL"] = "1" }
        app.launch()
        XCTAssertTrue(app.buttons["platformFeaturedOpen"].waitForExistence(timeout: 10))
        return app
    }
    private func assertNoPlaybackControls(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(app.buttons["miniPlayer"].exists, file: file, line: line)
        XCTAssertFalse(app.buttons["playerQueue"].exists, file: file, line: line)
        XCTAssertFalse(app.buttons["saveOffline"].exists, file: file, line: line)
        XCTAssertFalse(app.staticTexts["playbackUnavailable"].exists, file: file, line: line)
        XCTAssertEqual(app.sliders.count, 0, file: file, line: line)
    }
    private func scrollUntilVisible(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
    func testPlatformDiscoveryAndDetailsDoNotOfferNativePlayback() {
        let app = launch()
        assertNoPlaybackControls(app)
        capture(app, "Platform-Discover")
        scrollUntilVisible(app.buttons["platformFeaturedOpen"], in: app); app.buttons["platformFeaturedOpen"].tap()
        XCTAssertTrue(app.scrollViews["platformDetailScreen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["platformLink.netease"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["platformLink.spotify"].exists)
        XCTAssertTrue(app.buttons["platformPreviewWebsite"].exists)
        XCTAssertTrue(app.buttons["platformShare"].exists)
        assertNoPlaybackControls(app)
        capture(app, "Platform-Work-Detail")
        app.buttons["platformDetailClose"].tap()
        app.tabBars.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["track.\(secondID)"].waitForExistence(timeout: 5))
        app.buttons["track.\(secondID)"].tap()
        XCTAssertTrue(app.staticTexts["platformLinksPending"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["platformLink.netease"].exists)
        assertNoPlaybackControls(app)
    }
    func testFavoriteEntryOpensTheSamePlatformDetailAndKeepsLibraryHierarchy() {
        let app = launch()
        scrollUntilVisible(app.buttons["platformFeaturedOpen"], in: app); app.buttons["platformFeaturedOpen"].tap()
        let favorite = app.buttons["platformFavorite"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 5))
        if favorite.value as? String == "On" {
            favorite.tap()
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'Off'"), object: favorite)], timeout: 5), .completed)
        }
        favorite.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'On'"), object: favorite)], timeout: 5), .completed)
        app.buttons["platformDetailClose"].tap()
        app.tabBars.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(app.buttons["accountEntry"].exists)
        XCTAssertTrue(app.buttons["favoritesEntry"].exists)
        app.buttons["favoritesEntry"].tap()
        XCTAssertTrue(app.buttons["library.track.\(firstID)"].waitForExistence(timeout: 5))
        app.buttons["library.track.\(firstID)"].tap()
        XCTAssertTrue(app.buttons["platformLink.netease"].waitForExistence(timeout: 5))
        assertNoPlaybackControls(app)
        app.buttons["platformDetailClose"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        scrollUntilVisible(app.buttons["offlineEntry"], in: app)
        app.buttons["offlineEntry"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["offlinePage"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["Automatically save free songs"].exists)
        assertNoPlaybackControls(app)
    }
    func testFavoritesSurviveTerminatedOfflineLaunch() {
        let app = launch()
        scrollUntilVisible(app.buttons["platformFeaturedOpen"], in: app); app.buttons["platformFeaturedOpen"].tap()
        let favorite = app.buttons["platformFavorite"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 5))
        if favorite.value as? String != "On" { favorite.tap() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'On'"), object: favorite)], timeout: 5), .completed)
        app.buttons["platformDetailClose"].tap()
        app.tabBars.buttons.element(boundBy: 2).tap(); app.buttons["favoritesEntry"].tap()
        XCTAssertTrue(app.buttons["library.track.\(firstID)"].waitForExistence(timeout: 5))
        app.terminate()
        // Bundled Mock 503; this test changes no device/network setting or live service.
        app.launchEnvironment["STATION_STARTUP_PREVIEW"] = "failure"
        app.launch()
        XCTAssertTrue(app.buttons["startupContinue"].waitForExistence(timeout: 5)); app.buttons["startupContinue"].tap()
        app.tabBars.buttons.element(boundBy: 2).tap(); app.buttons["favoritesEntry"].tap()
        let saved = app.buttons["library.track.\(firstID)"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertTrue(saved.label.contains("A Slower Day"))
        XCTAssertTrue(saved.label.contains("connect to update"))
        capture(app, "Platform-Offline-Favorites")
        saved.tap()
        XCTAssertTrue(app.buttons["platformDetailRetry"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["platformLink.netease"].exists)
        assertNoPlaybackControls(app)
    }
    func testDetailFailureRetriesAndRejectedExternalOpenHasCopyFallback() {
        let app = launch(fixture: "detail-failure")
        scrollUntilVisible(app.buttons["platformFeaturedOpen"], in: app); app.buttons["platformFeaturedOpen"].tap()
        XCTAssertTrue(app.buttons["platformDetailRetry"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["platformLink.netease"].exists)
        app.buttons["platformDetailRetry"].tap()
        XCTAssertTrue(app.buttons["platformLink.netease"].waitForExistence(timeout: 5))
        assertNoPlaybackControls(app)
        app.terminate()

        let refused = launch(failOpen: true)
        scrollUntilVisible(refused.buttons["platformFeaturedOpen"], in: refused); refused.buttons["platformFeaturedOpen"].tap()
        let provider = refused.buttons["platformLink.netease"]
        XCTAssertTrue(provider.waitForExistence(timeout: 5))
        scrollUntilVisible(provider, in: refused); provider.tap()
        let copy = refused.buttons["platformCopyLink"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        scrollUntilVisible(copy, in: refused); copy.tap()
        XCTAssertEqual(copy.value as? String, "copied")
        XCTAssertTrue(refused.scrollViews["platformDetailScreen"].exists)
        assertNoPlaybackControls(refused)
        capture(refused, "Platform-Open-Fallback")
    }
    func testPlatformFourLocalesAndLargestDynamicType() {
        for locale in ["zh-Hans", "zh-Hant", "en", "ja"] {
            let app = launch(locale: locale, largeText: true)
            XCTAssertEqual(app.tabBars.buttons.count, 3)
            let open = app.buttons["platformFeaturedOpen"]
            scrollUntilVisible(open, in: app); open.tap()
            let provider = app.buttons["platformLink.netease"]
            XCTAssertTrue(provider.waitForExistence(timeout: 5))
            scrollUntilVisible(provider, in: app)
            XCTAssertTrue(provider.isHittable)
            assertNoPlaybackControls(app)
            capture(app, "Platform-" + locale + "-AXXXL")
            app.buttons["platformDetailClose"].tap()
            app.tabBars.buttons.element(boundBy: 2).tap()
            XCTAssertTrue(app.buttons["accountEntry"].exists)
            XCTAssertTrue(app.buttons["favoritesEntry"].exists)
            assertNoPlaybackControls(app)
            app.terminate()
        }
    }
}
