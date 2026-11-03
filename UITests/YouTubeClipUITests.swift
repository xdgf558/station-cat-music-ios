import XCTest

@MainActor final class YouTubeClipUITests: XCTestCase {
    private let clip = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
    override func setUp() { continueAfterFailure = false }
    private func closeListeningChooser(_ app: XCUIApplication) {
        let close = app.buttons["platformPickerClose"]
        if close.waitForExistence(timeout: 2) { close.tap() }
    }

    private func launch(locale: String = "zh-Hans", failure: Bool = false, large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--platform-music-fixture", "-AppleLanguages", "(\(locale))", "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launchEnvironment["STATION_PLATFORM_FIXTURE"] = failure ? "youtube-error" : "youtube-clips"
        app.launchEnvironment["STATION_PERSONAL_TEST_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["STATION_PLATFORM_OPEN_FAIL"] = "1" // Never leaves the local fixture.
        app.launch()
        let open = app.buttons["platformFeaturedOpen"]
        XCTAssertTrue(open.waitForExistence(timeout: 10)); reveal(open, app); open.tap(); closeListeningChooser(app)
        let tab = app.buttons["contentTab.clips"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10)); reveal(tab, app); tab.tap()
        capture(app, "YouTube-Initial-" + locale)
        let found = app.buttons["youtubeLoad." + clip].waitForExistence(timeout: 5)
        if !found { print(app.debugDescription) }
        XCTAssertTrue(found)
        return app
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        guard element.waitForExistence(timeout: 5) else { XCTFail("Expected scroll target is missing"); return }
        let identifier = element.identifier
        let detail = app.descendants(matching: .any)["platformDetailScreen"].firstMatch
        let footerControl = identifier.hasPrefix("platformLink.") || ["notebookWriteForSong", "lyricQuoteToNote", "platformPickerOpen"].contains(identifier)
        func align(_ target: CGRect?, top: CGFloat, bottom: CGFloat, x: CGFloat) {
            let height = bottom - top
            let adjustment: CGFloat
            if let target, target.minY < top { adjustment = top + 12 - target.minY }
            else if let target, target.maxY > bottom { adjustment = bottom - 12 - target.maxY }
            else { adjustment = -min(140, height * 0.3) }
            let distance = min(max(abs(adjustment), 80), min(160, height * 0.3))
            let delta = adjustment > 0 ? distance : -distance
            let startY = top + height * (delta > 0 ? 0.3 : 0.7)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            print("YOUTUBE_REVEAL_ADJUST id=\(identifier) target=\(target ?? .zero) top=\(top) bottom=\(bottom) delta=\(delta)")
            // Keep a real scroll-length drag, using the original event type.
            // Short slow presses can activate the preview instead of panning.
            origin.withOffset(CGVector(dx: x - app.frame.minX, dy: startY - app.frame.minY))
                .press(forDuration: 0.05,
                       thenDragTo: origin.withOffset(CGVector(dx: x - app.frame.minX, dy: startY + delta - app.frame.minY)))
        }
        for attempt in 0...12 {
            if !element.exists { _ = element.waitForExistence(timeout: 2) }
            let modal = app.buttons["youtubePrivacyClose"].exists || app.buttons["douyinPrivacyClose"].exists
            if !detail.exists || modal {
                let home = app.descendants(matching: .any)["discoverScreen"].firstMatch
                let visibleScroll = app.scrollViews.allElementsBoundByIndex.first { $0.isHittable && $0.frame.height > 80 }
                let targetScroll = app.scrollViews.containing(.any, identifier: identifier).firstMatch
                let viewport = !modal && home.exists ? home.frame :
                    (modal && targetScroll.exists ? targetScroll.frame : (visibleScroll?.frame ?? app.frame))
                let navigationBottom = app.navigationBars.allElementsBoundByIndex.map { $0.frame.maxY }.max() ?? viewport.minY
                let top = max(max(viewport.minY, navigationBottom), app.frame.minY + 60) + 8
                let tabBar = app.descendants(matching: .any)["radioTabBar"].firstMatch
                let bottom = min(viewport.maxY, !modal && tabBar.exists ? tabBar.frame.minY : app.frame.maxY - 24) - 8
                guard bottom - top > 80 else { XCTFail("No visible scroll area above fixed controls"); return }
                let frame = element.exists ? element.frame : nil
                if let frame, element.isHittable && frame.minY >= top && frame.maxY <= bottom { return }
                guard attempt < 12 else { break }
                if modal && targetScroll.exists {
                    // Nested sheets need a gesture scoped to their own scroll view.
                    if let frame, frame.minY < top { targetScroll.swipeDown(velocity: .slow) }
                    else { targetScroll.swipeUp(velocity: .slow) }
                    continue
                }
                align(frame, top: top, bottom: bottom, x: max(app.frame.minX + 14, viewport.minX + 14))
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
            guard bottom - top > 80 else { XCTFail("No visible reading area above the listening footer"); return }
            let frame = element.exists ? element.frame : nil
            if let frame {
                let tallText = element.elementType == .staticText && frame.height > bottom - top
                if element.isHittable && (tallText ? frame.maxY > top && frame.minY < bottom : frame.minY >= top && frame.maxY <= bottom) { return }
            }
            guard attempt < 12 else { break }
            align(frame, top: top, bottom: bottom, x: detail.frame.midX)
        }
        capture(app, "Reveal-Failure-" + identifier)
        print("REVEAL_FAILED identifier=\(identifier) exists=\(element.exists) hittable=\(element.isHittable) target=\(element.exists ? element.frame : .zero) app=\(app.frame)")
        print(app.debugDescription)
        XCTFail("Control should be fully reachable inside the active scroll area: " + identifier)
    }
    private func revealDetailTab(_ element: XCUIElement, _ app: XCUIApplication) {
        let detail = app.descendants(matching: .any)["platformDetailScreen"].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 5), "Song detail must remain open")
        reveal(element, app)
        XCTAssertTrue(detail.exists, "Song detail must remain open while locating its tabs")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let item = XCTAttachment(screenshot: app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
    func testSelectedLayoutClickToLoadAndTabBackgroundDismissTeardown() {
        let app = launch()
        XCTAssertFalse(app.webViews.firstMatch.exists)
        XCTAssertFalse(app.buttons["miniPlayer"].exists)
        reveal(app.buttons["youtubeOpen." + clip], app)
        XCTAssertTrue(app.buttons["youtubeOpen." + clip].isHittable, "External fallback should be reachable above the listening footer")
        XCTAssertLessThanOrEqual(app.buttons["youtubeOpen." + clip].frame.maxY, app.buttons["platformLink.netease"].frame.minY)
        capture(app, "YouTube-Selected-Layout-zh-Hans")
        reveal(app.buttons["youtubePrivacyInfo"], app); app.buttons["youtubePrivacyInfo"].tap()
        XCTAssertTrue(app.buttons["youtubePrivacyClose"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews.firstMatch.exists)
        capture(app, "YouTube-Privacy-Notice")
        app.buttons["youtubePrivacyClose"].tap()
        let load = app.buttons["youtubeLoad." + clip]
        reveal(load, app); load.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.webViews.staticTexts["未连接 YouTube · 无真实视频"].waitForExistence(timeout: 10))
        capture(app, "YouTube-Local-Player-Fixture")
        let story = app.buttons["contentTab.story"]
        revealDetailTab(story, app); story.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["contentStoryText"].waitForExistence(timeout: 5))
        revealDetailTab(app.buttons["contentTab.clips"], app); app.buttons["contentTab.clips"].tap(); reveal(load, app); load.tap()
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
        let lyrics = app.buttons["contentTab.lyrics"]
        revealDetailTab(lyrics, app); lyrics.tap()
        XCTAssertTrue(app.descendants(matching: .any)["lyricStanza.0"].firstMatch.waitForExistence(timeout: 5))
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
