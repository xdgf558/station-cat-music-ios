import XCTest

@MainActor final class PlatformMusicUITests: XCTestCase {
    private let firstID = "11111111-1111-4111-8111-111111111111"
    private let secondID = "22222222-2222-4222-8222-222222222222"
    private func closeListeningChooser(_ app: XCUIApplication) {
        let close = app.buttons["platformPickerClose"]
        if close.waitForExistence(timeout: 2) { close.tap() }
    }

    private func launch(locale: String = "en", fixture: String = "normal", largeText: Bool = false, failOpen: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--platform-music-fixture", "-AppleLanguages", "(\(locale))", "-UIPreferredContentSizeCategoryName",
            largeText ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launchEnvironment["STATION_PLATFORM_FIXTURE"] = fixture
        app.launchEnvironment["STATION_PERSONAL_TEST_NAMESPACE"] = UUID().uuidString
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
    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
    func testPlatformDiscoveryAndDetailsDoNotOfferNativePlayback() {
        let app = launch()
        assertNoPlaybackControls(app)
        capture(app, "Platform-Discover")
        scrollUntilVisible(app.buttons["platformFeaturedOpen"], in: app); app.buttons["platformFeaturedOpen"].tap(); closeListeningChooser(app)
        XCTAssertTrue(app.descendants(matching: .any)["platformDetailScreen"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["platformLink.netease"].waitForExistence(timeout: 5))
        app.buttons["platformPickerOpen"].tap()
        XCTAssertTrue(app.buttons["platformPicker.spotify"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["platformPreviewWebsite"].exists)
        app.buttons["platformPickerClose"].tap()
        XCTAssertTrue(app.buttons["platformShare"].exists)
        assertNoPlaybackControls(app)
        capture(app, "Platform-Work-Detail")
        app.buttons["platformDetailClose"].tap()
        app.buttons["tab.shelf"].tap()
        XCTAssertTrue(app.buttons["track.\(secondID)"].waitForExistence(timeout: 5))
        app.buttons["track.\(secondID)"].tap()
        XCTAssertTrue(app.staticTexts["platformLinksPending"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["platformLink.netease"].exists)
        assertNoPlaybackControls(app)
    }
    func testFavoriteEntryOpensTheSamePlatformDetailAndKeepsLibraryHierarchy() {
        let app = launch()
        scrollUntilVisible(app.buttons["platformFeaturedOpen"], in: app); app.buttons["platformFeaturedOpen"].tap(); closeListeningChooser(app)
        let favorite = app.buttons["platformFavorite"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 5))
        if favorite.value as? String == "On" {
            favorite.tap()
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'Off'"), object: favorite)], timeout: 5), .completed)
        }
        favorite.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'On'"), object: favorite)], timeout: 5), .completed)
        app.buttons["platformDetailClose"].tap()
        app.buttons["tab.me"].tap()
        XCTAssertFalse(app.buttons["accountEntry"].exists)
        XCTAssertTrue(app.buttons["favoritesEntry"].exists)
        app.buttons["favoritesEntry"].tap()
        XCTAssertTrue(app.buttons["library.track.\(firstID)"].waitForExistence(timeout: 5))
        app.buttons["library.track.\(firstID)"].tap()
        XCTAssertTrue(app.buttons["platformLink.netease"].waitForExistence(timeout: 5))
        assertNoPlaybackControls(app)
        app.buttons["platformDetailClose"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertFalse(app.buttons["settingsHelpEntry"].exists)
        XCTAssertFalse(app.buttons["legacyDataEntry"].exists)
        scrollUntilVisible(app.buttons["privacyEntry"], in: app)
        app.buttons["privacyEntry"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["privacyPage"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["offlineEntry"].exists)
        XCTAssertFalse(app.switches["Automatically save free songs"].exists)
        assertNoPlaybackControls(app)
    }
    func testFavoritesSurviveTerminatedOfflineLaunch() {
        let app = launch()
        scrollUntilVisible(app.buttons["platformFeaturedOpen"], in: app); app.buttons["platformFeaturedOpen"].tap(); closeListeningChooser(app)
        let favorite = app.buttons["platformFavorite"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 5))
        if favorite.value as? String != "On" { favorite.tap() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'On'"), object: favorite)], timeout: 5), .completed)
        app.buttons["platformDetailClose"].tap()
        app.buttons["tab.me"].tap(); app.buttons["favoritesEntry"].tap()
        XCTAssertTrue(app.buttons["library.track.\(firstID)"].waitForExistence(timeout: 5))
        app.terminate()
        // Bundled Mock 503; this test changes no device/network setting or live service.
        app.launchEnvironment["STATION_STARTUP_PREVIEW"] = "failure"
        app.launch()
        XCTAssertTrue(app.buttons["startupContinue"].waitForExistence(timeout: 5)); app.buttons["startupContinue"].tap()
        app.buttons["tab.me"].tap(); app.buttons["favoritesEntry"].tap()
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
        scrollUntilVisible(app.buttons["platformFeaturedOpen"], in: app); app.buttons["platformFeaturedOpen"].tap(); closeListeningChooser(app)
        XCTAssertTrue(app.buttons["platformDetailRetry"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["platformLink.netease"].exists)
        app.buttons["platformDetailRetry"].tap()
        XCTAssertTrue(app.buttons["platformLink.netease"].waitForExistence(timeout: 5))
        assertNoPlaybackControls(app)
        app.terminate()

        let refused = launch(failOpen: true)
        scrollUntilVisible(refused.buttons["platformFeaturedOpen"], in: refused); refused.buttons["platformFeaturedOpen"].tap(); closeListeningChooser(refused)
        let provider = refused.buttons["platformLink.netease"]
        XCTAssertTrue(provider.waitForExistence(timeout: 5))
        scrollUntilVisible(provider, in: refused); provider.tap()
        let copy = refused.buttons["platformCopyLink"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        scrollUntilVisible(copy, in: refused); copy.tap()
        XCTAssertEqual(copy.value as? String, "copied")
        XCTAssertTrue(refused.descendants(matching: .any)["platformDetailScreen"].firstMatch.exists)
        assertNoPlaybackControls(refused)
        capture(refused, "Platform-Open-Fallback")
    }
    func testPlatformFourLocalesAndLargestDynamicType() {
        for locale in ["zh-Hans", "zh-Hant", "en", "ja"] {
            let app = launch(locale: locale, largeText: true)
            for tab in ["radio", "shelf", "notes", "me"] { XCTAssertTrue(app.buttons["tab." + tab].exists) }
            let open = app.buttons["platformFeaturedOpen"]
            scrollUntilVisible(open, in: app); open.tap(); closeListeningChooser(app)
            let provider = app.buttons["platformLink.netease"]
            XCTAssertTrue(provider.waitForExistence(timeout: 5))
            scrollUntilVisible(provider, in: app)
            XCTAssertTrue(provider.isHittable)
            assertNoPlaybackControls(app)
            capture(app, "Platform-" + locale + "-AXXXL")
            app.buttons["platformDetailClose"].tap()
            app.buttons["tab.me"].tap()
            XCTAssertFalse(app.buttons["accountEntry"].exists)
            XCTAssertTrue(app.buttons["favoritesEntry"].exists)
            assertNoPlaybackControls(app)
            app.terminate()
        }
    }
    func testVerifiedPlatformChooserRemembersOnlyTheChosenPublishedService() {
        let app = launch(failOpen: true)
        let open = app.buttons["platformFeaturedOpen"]
        scrollUntilVisible(open, in: app); open.tap()
        let spotify = app.buttons["platformPicker.spotify"]
        XCTAssertTrue(spotify.waitForExistence(timeout: 5)); XCTAssertTrue(spotify.isEnabled)
        XCTAssertFalse(app.buttons["platformPicker.apple_music"].isEnabled)
        spotify.tap()
        capture(app, "Radio-Listening-Service-Chooser")
        app.buttons["platformPickerConfirm"].tap()
        XCTAssertTrue(app.buttons["platformPickerClose"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["platformLink.spotify"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["platformOpenFailure"].waitForExistence(timeout: 5))
        assertNoPlaybackControls(app)
    }

}
