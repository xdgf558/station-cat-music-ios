import XCTest

@MainActor final class PlatformCatalogUITests: XCTestCase {
    private let firstAlbum = "aaaaaaaa-0000-4000-8000-000000000001"
    private let secondAlbum = "aaaaaaaa-0000-4000-8000-000000000002"
    private let firstTrack = "bbbbbbbb-0000-4000-8000-000000000010"
    private let secondTrack = "bbbbbbbb-0000-4000-8000-000000000011"
    private func launch(locale: String = "zh-Hans", large: Bool = false, fixture: String = "catalog-categories") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--platform-music-fixture", "-AppleLanguages", "(\(locale))", "-UIPreferredContentSizeCategoryName",
            large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launchEnvironment["STATION_PLATFORM_FIXTURE"] = fixture
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        app.tabBars.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons[large ? "catalogCategoryMenu" : "catalogCategory.albums"].waitForExistence(timeout: 5))
        return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<10 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    func testAlbumsSinglesSearchAndOrderedDetail() {
        let app = launch()
        app.buttons["catalogCategory.albums"].tap()
        let first = app.buttons["album." + firstAlbum]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["album." + secondAlbum].exists)
        capture(app, "Catalog-Albums-zh-Hans")
        first.tap()
        let firstSong = app.buttons["track." + firstTrack], secondSong = app.buttons["track." + secondTrack]
        XCTAssertTrue(firstSong.waitForExistence(timeout: 5))
        reveal(secondSong, app: app)
        XCTAssertLessThan(firstSong.frame.minY, secondSong.frame.minY)
        capture(app, "Catalog-Album-Detail")
        firstSong.tap()
        XCTAssertTrue(app.buttons["platformLink.netease"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["miniPlayer"].exists)
        XCTAssertEqual(app.sliders.count, 0)
        app.buttons["platformDetailClose"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["catalogCategory.singles"].tap()
        XCTAssertTrue(app.buttons["track.11111111-1111-4111-8111-111111111111"].exists)
        XCTAssertFalse(firstSong.exists)
        capture(app, "Catalog-Singles-zh-Hans")
        app.buttons["catalogCategory.albums"].tap()
        let search = app.textFields["catalogSearch"]
        search.tap(); search.typeText("改天\n")
        XCTAssertTrue(app.buttons["album." + secondAlbum].waitForExistence(timeout: 5))
        XCTAssertFalse(first.exists)
        app.buttons["catalogClearSearch"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
    }
    func testEmptyAlbumCategoryReturnsToAllWorks() {
        let app = launch(locale: "en", fixture: "normal")
        app.buttons["catalogCategory.albums"].tap()
        XCTAssertTrue(app.staticTexts["No albums yet"].waitForExistence(timeout: 5))
        capture(app, "Catalog-Empty-Albums")
        app.buttons["catalogCategory.all"].tap()
        XCTAssertTrue(app.buttons["track.11111111-1111-4111-8111-111111111111"].exists)
    }
    func testAlbumGalleryFourLanguagesAndAccessibilityText() {
        for locale in ["zh-Hans", "zh-Hant", "en", "ja"] {
            let app = launch(locale: locale, large: true)
            app.buttons["catalogCategoryMenu"].tap()
            let category = app.buttons["catalogCategory.albums"]
            XCTAssertTrue(category.waitForExistence(timeout: 5))
            category.tap()
            let first = app.buttons["album." + firstAlbum]
            reveal(first, app: app)
            XCTAssertTrue(first.isHittable)
            XCTAssertTrue(app.tabBars.buttons.element(boundBy: 2).isHittable)
            capture(app, "Catalog-Albums-" + locale + "-AXXXL")
            first.tap()
            let track = app.buttons["track." + firstTrack]
            reveal(track, app: app); track.tap()
            XCTAssertTrue(app.scrollViews["platformDetailScreen"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["miniPlayer"].exists)
            app.terminate()
        }
    }
}
