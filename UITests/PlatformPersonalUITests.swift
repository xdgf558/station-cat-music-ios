import XCTest

@MainActor final class PlatformPersonalUITests: XCTestCase {
    private let ids = ["bbbbbbbb-0000-4000-8000-000000000010", "bbbbbbbb-0000-4000-8000-000000000020"]
    private func launch(locale: String = "zh-Hans", large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--platform-music-fixture", "-AppleLanguages", "(\(locale))", "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launchEnvironment["STATION_PLATFORM_FIXTURE"] = "catalog-categories"
        app.launchEnvironment["STATION_PERSONAL_TEST_NAMESPACE"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["tab.radio"].waitForExistence(timeout: 10))
        return app
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication, towardTop: Bool = false) {
        for _ in 0..<12 {
            if element.isHittable { return }
            if towardTop { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        // Preserve the whole compatibility window when inspecting the app on iPad.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func seed(_ app: XCUIApplication) {
        app.buttons["tab.shelf"].tap()
        for id in ids {
            let track = app.buttons["track." + id]; reveal(track, app: app); track.tap()
            let favorite = app.buttons["platformFavorite"]
            XCTAssertTrue(favorite.waitForExistence(timeout: 5))
            // Wait for the verified listening action, not the removed section heading.
            XCTAssertTrue(app.buttons["platformLink.netease"].waitForExistence(timeout: 5))
            if favorite.value as? String != "开启" && favorite.value as? String != "On" { favorite.tap() }
            let savedFavorite = NSPredicate(format: "value == '开启' OR value == '開啟' OR value == 'On' OR value == 'オン'")
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: savedFavorite, object: favorite)], timeout: 5), .completed)
            app.buttons["platformDetailClose"].tap()
        }
        app.buttons["tab.me"].tap()
        XCTAssertTrue(app.buttons["favoritesEntry"].waitForExistence(timeout: 5))
    }
    func testPersonalHubNavigationPrivacyPreferenceAndNotes() {
        let app = launch()
        seed(app)
        capture(app, "My-Hub-zh-Hans")
        XCTAssertFalse(app.buttons["accountEntry"].exists); XCTAssertFalse(app.buttons["historyEntry"].exists)
        XCTAssertFalse(app.buttons["offlineEntry"].exists); XCTAssertFalse(app.buttons["miniPlayer"].exists)
        reveal(app.buttons["viewedEntry"], app: app); app.buttons["viewedEntry"].tap()
        XCTAssertTrue(app.buttons["viewed.track." + ids[0]].waitForExistence(timeout: 5))
        capture(app, "My-Recently-Viewed")
        let clear = app.buttons["clearViewed"]; reveal(clear, app: app); clear.tap()
        app.alerts.buttons["取消"].tap()
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
        // The redesign places platform choices directly in Me rather than a separate form.
        let preferred = app.buttons["platformPreference.spotify"]; reveal(preferred, app: app); preferred.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '开启'"), object: preferred)], timeout: 5), .completed)
        capture(app, "My-Inline-Platform-Preference")
        XCTAssertFalse(app.buttons["legacyDataEntry"].exists)
        XCTAssertFalse(app.buttons["offlineEntry"].exists); XCTAssertFalse(app.buttons["accountEntry"].exists)
        reveal(app.buttons["helpEntry"], app: app); app.buttons["helpEntry"].tap(); app.buttons["releaseNotesEntry"].tap()
        XCTAssertTrue(app.staticTexts["Station Cat Music · 1.0.9 (22)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["修复部分 iPhone 打开“我的”时闪退的问题，保留收藏、笔记与设置。"].waitForExistence(timeout: 5))
        let changes = [
            "全新暖纸质界面、衬线排版与猫耳唱片图标，提供日间及深夜外观。",
            "新增电台调频选歌与唱片架布局，笔记升级为独立一级入口。",
            "可主动选取一句已发布歌词摘入笔记，确认保存后仅留在本机。",
            "支持跟随系统、日间纸与深夜电台；保留既有收听、收藏及本机资料管理。"
        ]
        for change in changes {
            let entry = app.staticTexts[change]; reveal(entry, app: app); XCTAssertTrue(entry.exists)
        }
        capture(app, "My-1.0.9-Build22-Notes")
        let previousChange = app.staticTexts["单曲和专辑可生成分享卡片，展示作品介绍并提供 App Store 下载入口。"]
        reveal(previousChange, app: app); XCTAssertTrue(previousChange.exists, "Prior release notes must remain available")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["tab.radio"].waitForExistence(timeout: 10)); app.buttons["tab.me"].tap()
        let historyOff = app.staticTexts["浏览记录已关闭。"]
        reveal(historyOff, app: app); XCTAssertTrue(historyOff.exists)
        let restoredPreference = app.buttons["platformPreference.spotify"]; reveal(restoredPreference, app: app)
        XCTAssertEqual(restoredPreference.value as? String, "开启", "The selected platform must survive relaunch")
        reveal(app.buttons["favoritesEntry"], app: app, towardTop: true); app.buttons["favoritesEntry"].tap()
        XCTAssertTrue(app.buttons["library.track." + ids[0]].exists)
    }
    func testBrowsingRelaunchOfflineStillShowsEntriesWithoutListeningLinks() {
        let app = launch(); seed(app); app.terminate()
        app.launchEnvironment["STATION_STARTUP_PREVIEW"] = "failure"
        app.launch(); XCTAssertTrue(app.buttons["startupContinue"].waitForExistence(timeout: 10)); app.buttons["startupContinue"].tap()
        app.buttons["tab.me"].tap()
        let retained = app.buttons["viewed.track." + ids[0]]; reveal(retained, app: app)
        XCTAssertTrue(retained.exists)
        capture(app, "My-Offline")
        retained.tap()
        XCTAssertTrue(app.buttons["platformDetailRetry"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["platformLink.netease"].exists); XCTAssertFalse(app.buttons["miniPlayer"].exists)
    }
    func testHubFourLanguagesAndAccessibilityText() {
        for locale in ["zh-Hans", "zh-Hant", "en", "ja"] {
            let app = launch(locale: locale, large: true)
            app.buttons["tab.me"].tap()
            XCTAssertTrue(app.buttons["favoritesEntry"].waitForExistence(timeout: 5))
            reveal(app.buttons["favoritesEntry"], app: app)
            capture(app, "My-Empty-" + locale + "-AXXXL")
            app.buttons["favoritesEntry"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["favoritesPage"].firstMatch.waitForExistence(timeout: 5))
            app.navigationBars.buttons.firstMatch.tap()
            let preferred = app.buttons["platformPreference.spotify"]; reveal(preferred, app: app)
            XCTAssertTrue(preferred.isHittable); preferred.tap()
            let selected = ["zh-Hans": "开启", "zh-Hant": "開啟", "en": "On", "ja": "オン"][locale]!
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", selected), object: preferred)], timeout: 5), .completed)
            capture(app, "My-Inline-Preference-" + locale + "-AXXXL")
            XCTAssertTrue(app.buttons["tab.me"].isHittable)
            app.terminate()
        }
    }
}
