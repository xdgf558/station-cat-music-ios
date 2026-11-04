import XCTest

@MainActor final class NetEaseListeningUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private func closeListeningChooser(_ app: XCUIApplication) {
        let close = app.buttons["platformPickerClose"]
        if close.waitForExistence(timeout: 2) { close.tap() }
    }

    private func launch(mode: String = "ready", locale: String = "zh-Hans", large: Bool = false, externalOnly: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--platform-music-fixture", "-AppleLanguages", "(\(locale))",
                               "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launchEnvironment["STATION_PLATFORM_FIXTURE"] = "song-content"
        app.launchEnvironment["STATION_NETEASE_BROWSER_FIXTURE"] = mode
        app.launchEnvironment["STATION_PLATFORM_OPEN_FAIL"] = "1"
        if externalOnly { app.launchEnvironment["STATION_EXTERNAL_ONLY_FIXTURE"] = "YES" }
        app.launchEnvironment["STATION_PERSONAL_TEST_NAMESPACE"] = UUID().uuidString
        app.launch()
        let featured = app.buttons["platformFeaturedOpen"]
        XCTAssertTrue(featured.waitForExistence(timeout: 10)); reveal(featured, app); featured.tap(); closeListeningChooser(app)
        let listen = app.buttons["platformLink.netease"]
        XCTAssertTrue(listen.waitForExistence(timeout: 10)); reveal(listen, app); listen.tap()
        XCTAssertTrue(app.buttons[externalOnly ? "platformCopyLink" : "neteaseBrowserClose"].waitForExistence(timeout: 10))
        return app
    }
    func testExternalOnlyListeningDoesNotPresentTheBrowserEvenWithAnOldFixtureMarker() {
        let app = launch(externalOnly: true)
        XCTAssertFalse(app.buttons["neteaseBrowserClose"].exists)
        XCTAssertFalse(app.webViews.firstMatch.exists)
        XCTAssertTrue(app.buttons["platformCopyLink"].exists)
        XCTAssertTrue(app.buttons["contentTab.lyrics"].exists)
    }

    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<8 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testLocalDocumentCloseAndReopenKeepSongDetail() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["neteaseBrowserLoaded"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.webViews.firstMatch.exists)
        capture(app, "NetEase-Test-Document-Not-Real-Playback")
        app.buttons["neteaseBrowserClose"].tap()
        XCTAssertTrue(app.buttons["contentTab.lyrics"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews.firstMatch.exists)
        let listen = app.buttons["platformLink.netease"]; reveal(listen, app); listen.tap()
        XCTAssertTrue(app.staticTexts["neteaseBrowserLoaded"].waitForExistence(timeout: 15))
        app.buttons["neteaseBrowserClose"].tap()
    }
    func testBlockedNavigationCanRetryAndExternalRejectionRemainsVisible() {
        let app = launch(mode: "blocked")
        XCTAssertTrue(app.staticTexts["neteaseBrowserLoaded"].waitForExistence(timeout: 15))
        let blocked = app.webViews.links["测试受限导航"]
        XCTAssertTrue(blocked.waitForExistence(timeout: 5)); reveal(blocked, app); blocked.tap()
        XCTAssertTrue(app.staticTexts["neteaseBrowserFailure"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.webViews.firstMatch.exists)
        XCTAssertTrue(app.staticTexts["neteaseBrowserDiagnostic"].exists)
        app.buttons["neteaseBrowserRetry"].tap()
        XCTAssertTrue(app.staticTexts["neteaseBrowserLoaded"].waitForExistence(timeout: 15))
        let external = app.buttons["neteaseBrowserExternal"]; reveal(external, app); external.tap()
        XCTAssertTrue(app.staticTexts["neteaseExternalFailure"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["neteaseBrowserCopy"].exists)
        XCTAssertTrue(app.buttons["neteaseBrowserRetry"].exists)
        capture(app, "NetEase-Test-External-Rejected")
        app.buttons["neteaseBrowserClose"].tap()
    }
    func testApprovedMobileDocumentLoadsFromLocalFixture() {
        let app = launch(mode: "mobile")
        XCTAssertTrue(app.staticTexts["neteaseBrowserLoaded"].waitForExistence(timeout: 15))
        // Document completion can precede WebKit's accessibility tree.
        XCTAssertTrue(app.webViews.staticTexts["官方分享域名本机夹具"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["neteaseBrowserFailure"].exists)
        app.buttons["neteaseBrowserClose"].tap()
    }
    func testInitialBlockedDocumentKeepsErrorWindowAndRedactedDiagnostic() {
        let app = launch(mode: "initial-blocked")
        XCTAssertTrue(app.staticTexts["neteaseBrowserFailure"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.webViews.firstMatch.exists)
        XCTAssertTrue(app.staticTexts["neteaseBrowserDiagnostic"].exists)
        XCTAssertTrue(app.buttons["neteaseBrowserRetry"].exists)
        XCTAssertTrue(app.buttons["neteaseBrowserClose"].isHittable)
        app.buttons["neteaseBrowserClose"].tap()
        XCTAssertTrue(app.buttons["contentTab.lyrics"].waitForExistence(timeout: 5))
    }
    func testBackgroundDestroysDocumentAndDoesNotAutomaticallyResume() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["neteaseBrowserLoaded"].waitForExistence(timeout: 15))
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.buttons["neteaseBrowserRetry"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.webViews.firstMatch.exists)
        app.buttons["neteaseBrowserRetry"].tap()
        XCTAssertTrue(app.staticTexts["neteaseBrowserLoaded"].waitForExistence(timeout: 15))
        app.buttons["neteaseBrowserClose"].tap()
    }
    func testFourLocalesAtLargeTextKeepCloseAndFallbackReachable() {
        for locale in ["zh-Hans", "zh-Hant", "en", "ja"] {
            let app = launch(locale: locale, large: true)
            XCTAssertTrue(app.staticTexts["neteaseBrowserLoaded"].waitForExistence(timeout: 15))
            reveal(app.buttons["neteaseBrowserExternal"], app)
            XCTAssertTrue(app.buttons["neteaseBrowserClose"].isHittable)
            capture(app, "NetEase-Test-" + locale + "-Large")
            app.buttons["neteaseBrowserClose"].tap(); app.terminate()
        }
    }
}
