import XCTest

@MainActor final class DouyinClipUITests: XCTestCase {
    private let clip = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
    override func setUp() { continueAfterFailure = false }
    private func closeListeningChooser(_ app: XCUIApplication) {
        let close = app.buttons["platformPickerClose"]
        if close.waitForExistence(timeout: 2) { close.tap() }
    }

    private func launch(locale: String = "zh-Hans", failure: Bool = false, large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--platform-music-fixture", "-AppleLanguages", "(\(locale))", "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launchEnvironment["STATION_PLATFORM_FIXTURE"] = failure ? "douyin-error" : "douyin-clips"
        app.launchEnvironment["STATION_PERSONAL_TEST_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["STATION_PLATFORM_OPEN_FAIL"] = "1" // Never leaves the local fixture.
        app.launch()
        let open = app.buttons["platformFeaturedOpen"]
        XCTAssertTrue(open.waitForExistence(timeout: 10)); reveal(open, app); open.tap(); closeListeningChooser(app)
        let tab = app.buttons["contentTab.clips"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10)); reveal(tab, app); tab.tap()
        capture(app, "Douyin-Initial-" + locale)
        let found = app.buttons["douyinLoad." + clip].waitForExistence(timeout: 5)
        if !found { print(app.debugDescription) }
        XCTAssertTrue(found)
        return app
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        let detail = app.descendants(matching: .any)["platformDetailScreen"].firstMatch
        let footerControl = element.identifier.hasPrefix("platformLink.") || ["notebookWriteForSong", "lyricQuoteToNote", "platformPickerOpen"].contains(element.identifier)
        for _ in 0..<12 {
            let modal = app.buttons["youtubePrivacyClose"].exists || app.buttons["douyinPrivacyClose"].exists
            if !detail.exists || modal {
                let home = app.descendants(matching: .any)["discoverScreen"].firstMatch
                let visibleScroll = app.scrollViews.allElementsBoundByIndex.first { $0.isHittable && $0.frame.height > 80 }
                let viewport = !modal && home.exists ? home.frame : (visibleScroll?.frame ?? app.frame)
                let navigationBottom = app.navigationBars.allElementsBoundByIndex.map { $0.frame.maxY }.max() ?? viewport.minY
                let top = max(max(viewport.minY, navigationBottom), app.frame.minY + 60) + 8
                let tabBar = app.descendants(matching: .any)["radioTabBar"].firstMatch
                let bottom = min(viewport.maxY, !modal && tabBar.exists ? tabBar.frame.minY : app.frame.maxY - 24) - 8
                let frame = element.frame
                if element.isHittable && frame.minY >= top && frame.maxY <= bottom { return }
                let up = !element.exists || frame.maxY > bottom || (frame.minY >= top && frame.midY > (top + bottom) / 2)
                let lower = top + (bottom - top) * 0.8, upper = top + (bottom - top) * 0.25
                let origin = app.coordinate(withNormalizedOffset: .zero)
                // The outer margin avoids the dial and keeps the drag inside
                // the active scroll view, above the fixed tab bar.
                let x = max(app.frame.minX + 14, viewport.minX + 14)
                origin.withOffset(CGVector(dx: x, dy: up ? lower : upper))
                    .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: x, dy: up ? upper : lower)))
                continue
            }
            if footerControl {
                if element.isHittable { return }
                break
            }
            let navigationBottom = app.navigationBars.allElementsBoundByIndex.map { $0.frame.maxY }.max() ?? detail.frame.minY
            let top = max(detail.frame.minY, navigationBottom) + 8
            let footer = app.buttons["notebookWriteForSong"]
            let bottom = min(detail.frame.maxY, footer.exists ? footer.frame.minY - 16 : app.frame.maxY - 40)
            let frame = element.frame
            let tallText = element.elementType == .staticText && frame.height > bottom - top
            if element.isHittable && (tallText ? frame.maxY > top && frame.minY < bottom : frame.minY >= top && frame.maxY <= bottom) { return }
            // Keep the drag inside the reading viewport, away from the sheet
            // handle and the permanent listening controls.
            let up = !element.exists || frame.maxY > bottom
            let lower = top + (bottom - top) * 0.8, upper = top + (bottom - top) * 0.25
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: app.frame.midX, dy: up ? lower : upper))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: app.frame.midX, dy: up ? upper : lower)))
        }
        capture(app, "Reveal-Failure-" + element.identifier)
        print("REVEAL_FAILED identifier=\(element.identifier) exists=\(element.exists) hittable=\(element.isHittable) target=\(element.exists ? element.frame : .zero) app=\(app.frame)")
        print(app.debugDescription)
        XCTFail("Control should be fully reachable inside the active scroll area: " + element.identifier)
    }
    private func selectTab(_ name: String, _ app: XCUIApplication) {
        let tab = app.buttons["contentTab." + name]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        // Stop as soon as the target is visible. Repeated whole-app swipes at
        // the sheet's top dismiss it instead of scrolling the content.
        reveal(tab, app)
        XCTAssertTrue(app.buttons["platformDetailClose"].exists)
        tab.tap()
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let item = XCTAttachment(screenshot: app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
    func testSelectedLayoutClickToLoadAndTabBackgroundDismissTeardown() {
        let app = launch()
        XCTAssertFalse(app.webViews.firstMatch.exists)
        XCTAssertFalse(app.buttons["miniPlayer"].exists)
        reveal(app.buttons["douyinOpen." + clip], app)
        XCTAssertTrue(app.buttons["douyinOpen." + clip].isHittable, "External fallback should be reachable above the listening footer")
        XCTAssertLessThanOrEqual(app.buttons["douyinOpen." + clip].frame.maxY, app.buttons["platformLink.netease"].frame.minY)
        capture(app, "Douyin-Selected-Layout-zh-Hans")
        reveal(app.buttons["douyinPrivacyInfo"], app); app.buttons["douyinPrivacyInfo"].tap()
        XCTAssertTrue(app.buttons["douyinPrivacyClose"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews.firstMatch.exists)
        capture(app, "Douyin-Privacy-Notice")
        app.buttons["douyinPrivacyClose"].tap()
        let load = app.buttons["douyinLoad." + clip]
        reveal(load, app); load.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.webViews.staticTexts["未连接 Douyin · 无真实视频"].waitForExistence(timeout: 10))
        capture(app, "Douyin-Local-Player-Fixture")
        selectTab("story", app)
        XCTAssertTrue(app.webViews.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["contentStoryText"].waitForExistence(timeout: 5))
        selectTab("clips", app); reveal(load, app); load.tap()
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
        let load = app.buttons["douyinLoad." + clip]; reveal(load, app); load.tap()
        XCTAssertTrue(app.buttons["douyinRetry"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.webViews.firstMatch.exists)
        reveal(app.buttons["douyinRetry"], app); capture(app, "Douyin-Embedding-Unavailable")
        let external = app.buttons["douyinOpen." + clip]; reveal(external, app); external.tap()
        XCTAssertTrue(app.buttons["platformCopyLink"].waitForExistence(timeout: 5))
        selectTab("lyrics", app)
        XCTAssertTrue(app.descendants(matching: .any)["lyricStanza.0"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["platformLink.netease"].exists)
    }
    func testFourLocalesLargeTextCanReachSourceFallbackAndListening() {
        for locale in ["zh-Hans", "zh-Hant", "en", "ja"] {
            let app = launch(locale: locale, large: true)
            let load = app.buttons["douyinLoad." + clip]; reveal(load, app)
            capture(app, "Douyin-" + locale + "-Accessibility")
            reveal(app.buttons["douyinOpen." + clip], app)
            reveal(app.buttons["platformLink.netease"], app)
            XCTAssertTrue(app.buttons["platformLink.netease"].isHittable)
            XCTAssertFalse(app.webViews.firstMatch.exists)
            let info = app.buttons["douyinPrivacyInfo"]; reveal(info, app); info.tap()
            XCTAssertTrue(app.buttons["douyinPrivacyClose"].waitForExistence(timeout: 5))
            reveal(app.buttons["douyinPrivacy"], app)
            XCTAssertTrue(app.buttons["douyinPrivacy"].isHittable)
            capture(app, "Douyin-Privacy-" + locale + "-Accessibility")
            app.buttons["douyinPrivacyClose"].tap()
            app.terminate()
        }
    }
}
