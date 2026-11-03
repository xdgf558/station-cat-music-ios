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
        XCTAssertTrue(app.buttons["tab.shelf"].waitForExistence(timeout: 10))
        app.buttons["tab.shelf"].tap()
        XCTAssertTrue(app.buttons[large ? "catalogCategoryMenu" : "catalogCategory.albums"].waitForExistence(timeout: 5))
        return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        let identifier = element.exists ? element.identifier : "missing-control"
        for attempt in 0...12 {
            if !element.exists { _ = element.waitForExistence(timeout: 2) }
            let top = max(app.frame.minY + 60, app.navigationBars.allElementsBoundByIndex.map { $0.frame.maxY }.max() ?? 0) + 8
            var bottom = app.frame.maxY - 24
            for control in [app.descendants(matching: .any)["radioTabBar"].firstMatch,
                            app.buttons.matching(NSPredicate(format: "identifier IN %@", ["radioAlbumChooseTrack", "platformAlbumDetail"])).firstMatch,
                            app.keyboards.firstMatch] where control.exists {
                bottom = min(bottom, control.frame.minY - 8)
            }
            guard bottom - top > 80 else { XCTFail("No visible catalog scroll area"); return }
            let frame = element.exists ? element.frame : nil
            if let frame, element.isHittable && frame.minY >= top && frame.maxY <= bottom { return }
            guard attempt < 12 else { break }
            // A hittable row can still sit behind the fixed album action or tab bar.
            let down = frame.map { $0.minY < top } ?? false
            let distance = min(180, max(36, frame.map { down ? top + 12 - $0.minY : $0.maxY - bottom + 12 } ?? 180))
            let y = top + (bottom - top) * (down ? 0.3 : 0.7)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: app.frame.width / 2, dy: y - app.frame.minY))
                .press(forDuration: 0.1,
                       thenDragTo: origin.withOffset(CGVector(dx: app.frame.width / 2, dy: y + (down ? distance : -distance) - app.frame.minY)),
                       withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        capture(app, "Catalog-Reveal-Failure-" + identifier)
        print("CATALOG_REVEAL_FAILED id=\(identifier) target=\(element.exists ? element.frame : .zero)")
        print(app.debugDescription)
        XCTFail("Catalog control must be fully visible between fixed controls: " + identifier)
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
        capture(app, "Radio-Album-Top")
        reveal(secondSong, app: app)
        XCTAssertLessThan(firstSong.frame.minY, secondSong.frame.minY)
        capture(app, "Catalog-Album-Detail")
        reveal(firstSong, app: app)
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
    func testAllShelfContainsAlbumsAndSearchMatchesTheirMemberSongs() {
        let app = launch()
        XCTAssertTrue(app.buttons["album." + firstAlbum].exists)
        let search = app.textFields["catalogSearch"]
        search.tap(); search.typeText("夜窗来信\n")
        XCTAssertTrue(app.buttons["album." + firstAlbum].waitForExistence(timeout: 5))
        let firstSong = app.buttons["track." + firstTrack]
        reveal(firstSong, app: app)
        XCTAssertTrue(firstSong.exists)
        XCTAssertFalse(app.buttons["track.11111111-1111-4111-8111-111111111111"].exists)
        let favorite = app.buttons["catalogFavorite." + firstTrack]
        reveal(favorite, app: app)
        XCTAssertGreaterThanOrEqual(favorite.frame.width, 44)
        XCTAssertGreaterThanOrEqual(favorite.frame.height, 44)
        capture(app, "Radio-Shelf-Album-Search")
    }
    func testEmptyAlbumCategoryReturnsToAllWorks() {
        let app = launch(locale: "en", fixture: "normal")
        app.buttons["catalogCategory.albums"].tap()
        XCTAssertTrue(app.staticTexts["No albums yet"].waitForExistence(timeout: 5))
        capture(app, "Catalog-Empty-Albums")
        app.buttons["catalogCategory.all"].tap()
        XCTAssertTrue(app.buttons["track.11111111-1111-4111-8111-111111111111"].exists)
    }

    func testSharePreviewsUseActualAlbumAndSongIntroductions() {
        let app = launch()
        app.buttons["catalogCategory.albums"].tap()
        let first = app.buttons["album." + firstAlbum]
        XCTAssertTrue(first.waitForExistence(timeout: 5)); first.tap()
        let albumShare = app.buttons["platformAlbumShare"]
        XCTAssertTrue(albumShare.waitForExistence(timeout: 5)); albumShare.tap()
        let summary = app.staticTexts["platformShareCardSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(summary.label, "写给深夜还醒着的人。")
        XCTAssertTrue(app.buttons["platformShareCardConfirm"].exists)
        capture(app, "Share-Album-Preview")
        app.buttons["platformShareCardClose"].tap()

        let firstSong = app.buttons["track." + firstTrack]
        reveal(firstSong, app: app); firstSong.tap()
        let songShare = app.buttons["platformShare"]
        XCTAssertTrue(songShare.waitForExistence(timeout: 5)); songShare.tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(summary.label, "写给深夜还醒着的人。")
        XCTAssertTrue(app.buttons["platformShareCardConfirm"].exists)
        capture(app, "Share-Song-Preview")
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
            XCTAssertTrue(app.buttons["tab.me"].isHittable)
            capture(app, "Catalog-Albums-" + locale + "-AXXXL")
            first.tap()
            XCTAssertTrue(app.scrollViews["platformAlbumDetail"].waitForExistence(timeout: 5))
            let track = app.buttons["track." + firstTrack]
            reveal(track, app: app)
            capture(app, "Catalog-Before-Track-" + locale + "-AXXXL")
            print("CATALOG_TRACK_TAP locale=\(locale) target=\(track.frame)")
            track.tap()
            let opened = app.descendants(matching: .any)["platformDetailScreen"].firstMatch.waitForExistence(timeout: 5)
            if !opened { capture(app, "Catalog-Track-Open-Failure-" + locale); print(app.debugDescription) }
            XCTAssertTrue(opened)
            XCTAssertFalse(app.buttons["miniPlayer"].exists)
            app.terminate()
        }
    }
}
