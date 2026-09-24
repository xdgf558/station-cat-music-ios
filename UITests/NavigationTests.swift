import XCTest

@MainActor final class NavigationTests: XCTestCase {
    func testStartupShowcaseTransitionsToHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launchEnvironment["STATION_STARTUP_PREVIEW"] = "slow"
        app.launch()
        XCTAssertTrue(app.staticTexts["startupLoading"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Startup-Chinese-Loading"; shot.lifetime = .keepAlways; add(shot)
        XCTAssertTrue(app.buttons["track.sample-night-window"].waitForExistence(timeout: 12))
        XCTAssertFalse(app.staticTexts["startupLoading"].exists)
        XCTAssertTrue(app.tabBars.firstMatch.exists)
    }
    func testStartupFailureCanRetryOrEnterLibrary() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launchEnvironment["STATION_STARTUP_PREVIEW"] = "failure"
        app.launch()
        XCTAssertTrue(app.buttons["startupRetry"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Startup-English-Failure"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["startupRetry"].tap()
        XCTAssertTrue(app.buttons["startupContinue"].waitForExistence(timeout: 5))
        app.buttons["startupContinue"].tap()
        XCTAssertTrue(app.tabBars.buttons["You"].waitForExistence(timeout: 5))
        app.tabBars.buttons["You"].tap()
        XCTAssertTrue(app.buttons["privacyEntry"].waitForExistence(timeout: 5))
    }
    func testStartupAccessibilityInFourLanguages() {
        for locale in ["en", "zh-Hans", "zh-Hant", "ja"] {
            let app = XCUIApplication()
            app.launchArguments = ["-AppleLanguages", "(\(locale))", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            app.launchEnvironment["STATION_STARTUP_PREVIEW"] = "failure"
            app.launch()
            XCTAssertTrue(app.buttons["startupRetry"].waitForExistence(timeout: 5))
            for _ in 0..<8 { if app.buttons["startupContinue"].isHittable { break }; app.swipeUp() }
            XCTAssertTrue(app.buttons["startupRetry"].isHittable)
            XCTAssertTrue(app.buttons["startupContinue"].isHittable)
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Startup-Accessibility-" + locale; shot.lifetime = .keepAlways; add(shot)
            app.buttons["startupContinue"].tap()
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
            app.terminate()
        }
    }
    func testOfflineAndVersionPages() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 10))
        app.tabBars.buttons["我的"].tap()
        app.buttons["offlineEntry"].tap()
        XCTAssertTrue(app.staticTexts["已用空间"].waitForExistence(timeout: 5))
        let offline = XCTAttachment(screenshot: app.screenshot()); offline.name = "Offline-Settings"; offline.lifetime = .keepAlways; add(offline)
        app.navigationBars.buttons.firstMatch.tap()
        for _ in 0..<4 { if app.buttons["helpEntry"].isHittable { break }; app.swipeUp() }
        app.buttons["helpEntry"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "0.1.0 (2)")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["releaseNotesEntry"].tap()
        XCTAssertTrue(app.staticTexts["Station Cat Music · 0.1.0 (2)"].waitForExistence(timeout: 5))
        let release = XCTAttachment(screenshot: app.screenshot()); release.name = "Version-Release-Notes"; release.lifetime = .keepAlways; add(release)
    }
    func testThreeTabsAndPlayerNeverAutoPlays() {
        let app = XCUIApplication(); app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]; app.launch()
        XCTAssertTrue(app.buttons["track.sample-night-window"].waitForExistence(timeout: 10))
        let home = XCTAttachment(screenshot: app.screenshot()); home.name = "M1-English-Discover"; home.lifetime = .keepAlways; add(home)
        app.buttons["track.sample-night-window"].tap()
        XCTAssertTrue(app.staticTexts["playbackUnavailable"].waitForExistence(timeout: 5))
        let player = XCTAttachment(screenshot: app.screenshot()); player.name = "Orbit-Player"; player.lifetime = .keepAlways; add(player)
        app.buttons["playerQueue"].tap()
        XCTAssertTrue(app.buttons["Clear and stop"].waitForExistence(timeout: 5))
        let queue = XCTAttachment(screenshot: app.screenshot()); queue.name = "Orbit-Queue"; queue.lifetime = .keepAlways; add(queue)
        app.buttons["queueClose"].tap()
        XCTAssertTrue(app.buttons["playerQueue"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["Fictional local preview. Live music and accounts are not connected."].exists)
        let catalog = app.scrollViews["catalogScreen"]
        XCTAssertTrue(catalog.waitForExistence(timeout: 5))
        let catalogCapture = XCTAttachment(screenshot: app.screenshot()); catalogCapture.name = "Orbit-Catalog"; catalogCapture.lifetime = .keepAlways; add(catalogCapture)
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
        XCTAssertFalse(app.switches["Save listening history"].exists, "Privacy actions belong on the second-level page")
        app.buttons["privacyEntry"].tap()
        let toggle = app.switches["Save listening history"]
        for _ in 0..<5 { if toggle.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(toggle.isHittable)
        let original = toggle.value as? String
        if original == "1" { toggle.switches.firstMatch.tap() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '0'"), object: toggle)], timeout: 5), .completed, "Wait for durable setting before terminating")
        app.terminate(); app.launch(); app.tabBars.buttons["You"].tap()
        app.buttons["privacyEntry"].tap()
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
    func testLibraryCategoryNavigationAndBack() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.buttons["track.sample-night-window"].waitForExistence(timeout: 10))
        app.buttons["track.sample-night-window"].tap()
        app.buttons["关闭"].tap()
        app.tabBars.buttons.element(boundBy: 2).tap()
        XCTAssertFalse(app.buttons["清空播放历史"].exists)
        for (entry, page) in [("accountEntry", "accountPage"), ("favoritesEntry", "favoritesPage"), ("historyEntry", "historyPage"), ("privacyEntry", "privacyPage"), ("preferencesEntry", "preferencesPage"), ("helpEntry", "helpPage")] {
            let link = app.buttons[entry]
            for _ in 0..<5 { if link.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(link.isHittable); link.tap()
            XCTAssertTrue(app.descendants(matching: .any)[page].firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["miniPlayer"].exists)
            XCTAssertLessThanOrEqual(app.buttons["miniPlayer"].frame.maxY, app.tabBars.firstMatch.frame.minY + 1)
            let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Library-" + page; image.lifetime = .keepAlways; add(image)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.scrollViews["libraryHome"].waitForExistence(timeout: 5))
        }
        app.swipeDown()
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Library-Hierarchy-Home"; image.lifetime = .keepAlways; add(image)
    }
    func testFourLocalesAndLargestDynamicType() {
        for locale in ["zh-Hans", "zh-Hant", "en", "ja"] {
            let app = XCUIApplication(); app.launchArguments = ["-AppleLanguages", "(\(locale))", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
            XCTAssertTrue(app.buttons["track.sample-night-window"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.tabBars.buttons.count, 3)
            let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "M1-\(locale)-AXXXL"; attachment.lifetime = .keepAlways; add(attachment)
            app.tabBars.buttons.element(boundBy: 2).tap()
            XCTAssertTrue(app.buttons["accountEntry"].exists)
            let mine = XCTAttachment(screenshot: app.screenshot()); mine.name = "Library-\(locale)-AXXXL"; mine.lifetime = .keepAlways; add(mine)
            let privacy = app.buttons["privacyEntry"]
            for _ in 0..<8 { if privacy.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(privacy.isHittable); privacy.tap()
            XCTAssertTrue(app.descendants(matching: .any)["privacyPage"].firstMatch.waitForExistence(timeout: 5))
            app.terminate()
        }
    }
}
