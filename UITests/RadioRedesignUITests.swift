import XCTest

@MainActor final class RadioRedesignUITests: XCTestCase {
    private func launch(appearance: String = "paper", fixture: String = "catalog-categories", slow: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--platform-music-fixture", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
                               "-radioAppearance", appearance, "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launchEnvironment["STATION_PLATFORM_FIXTURE"] = fixture
        app.launchEnvironment["STATION_PERSONAL_TEST_NAMESPACE"] = UUID().uuidString
        if slow { app.launchEnvironment["STATION_STARTUP_PREVIEW"] = "slow" }
        app.launch()
        return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    private func reveal(_ item: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 { if item.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(item.isHittable)
    }
    func testPaperAndNightRadioDialAndFourMainDestinations() {
        for appearance in ["paper", "night"] {
            let app = launch(appearance: appearance)
            XCTAssertTrue(app.buttons["tab.radio"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.tabBars.count, 0, "The platform UI must have only its custom navigation, without a second system bar")
            XCTAssertFalse(app.textFields["catalogSearch"].exists, "Inactive pages must stay out of the accessibility tree")
            XCTAssertFalse(app.buttons["notebookNew"].exists)
            XCTAssertFalse(app.buttons["favoritesEntry"].exists)
            for name in ["radio", "shelf", "notes", "me"] { XCTAssertTrue(app.buttons["tab." + name].isHittable) }
            capture(app, "Radio-Home-" + appearance)
            let dial = app.descendants(matching: .any)["radioDial"].firstMatch
            let next = app.buttons["radioNext"]; reveal(next, in: app)
            let before = dial.value as? String
            next.tap()
            XCTAssertNotEqual(dial.value as? String, before)
            XCTAssertFalse(app.buttons["miniPlayer"].exists)
            let listen = app.buttons["platformFeaturedOpen"]; reveal(listen, in: app); listen.tap()
            XCTAssertTrue(app.buttons["platformPickerClose"].waitForExistence(timeout: 5))
            capture(app, "Radio-Listening-" + appearance)
            app.buttons["platformPickerClose"].tap(); app.buttons["platformDetailClose"].tap()
            app.buttons["tab.shelf"].tap()
            XCTAssertTrue(app.textFields["catalogSearch"].waitForExistence(timeout: 5))
            capture(app, "Radio-Shelf-" + appearance)
            app.buttons["tab.notes"].tap()
            XCTAssertTrue(app.buttons["notebookNew"].waitForExistence(timeout: 5))
            let tabBar = app.descendants(matching: .any)["radioTabBar"].firstMatch
            XCTAssertGreaterThanOrEqual(app.buttons["notebookNew"].frame.height, 44)
            XCTAssertLessThanOrEqual(app.buttons["notebookNew"].frame.maxY, tabBar.frame.minY + 1,
                                     "The complete compose button must stay above the custom tab bar")
            capture(app, "Radio-Notebook-" + appearance)
            app.buttons["notebookNew"].tap()
            XCTAssertTrue(app.textFields["notebookTitleField"].waitForExistence(timeout: 5))
            capture(app, "Radio-Editor-" + appearance)
            app.buttons["notebookEditorClose"].tap()
            app.buttons["tab.me"].tap()
            XCTAssertTrue(app.buttons["favoritesEntry"].waitForExistence(timeout: 5))
            capture(app, "Radio-Me-" + appearance)
            app.terminate()
        }
    }
    func testRadioSearchOpensShelfWithKeyboardAndCanBeCleared() {
        let app = launch()
        XCTAssertTrue(app.buttons["radioSearch"].waitForExistence(timeout: 10))
        app.buttons["radioSearch"].tap()
        let field = app.textFields["catalogSearch"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText("No matching record")
        XCTAssertTrue(app.buttons["catalogClearSearch"].waitForExistence(timeout: 5))
        app.buttons["catalogClearSearch"].tap()
        XCTAssertEqual(field.value as? String, field.placeholderValue)
    }
    func testProgramSelectionAndHomeAlbumEntryUseTheRealCatalog() {
        let app = launch()
        let scroll = app.scrollViews["discoverScreen"]
        let bar = app.descendants(matching: .any)["radioTabBar"].firstMatch
        func show(_ element: XCUIElement) {
            for _ in 0..<10 {
                if element.isHittable && element.frame.maxY <= bar.frame.minY { return }
                scroll.swipeUp()
            }
            XCTFail("The complete home entry must be reachable above navigation")
        }
        let station = app.buttons["radioStation.bbbbbbbb-0000-4000-8000-000000000010"]
        XCTAssertTrue(station.waitForExistence(timeout: 10)); show(station); station.tap()
        XCTAssertTrue(station.isSelected)
        capture(app, "Radio-Program")
        let album = app.buttons["radioAlbum.aaaaaaaa-0000-4000-8000-000000000001"]
        show(album); capture(app, "Radio-Records")
        album.tap()
        XCTAssertTrue(app.buttons["platformAlbumShare"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["miniPlayer"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["tab.shelf"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab.shelf"].isSelected)
    }
    func testDialSeparatesHorizontalTuningFromVerticalPageScroll() {
        let app = launch()
        let dial = app.descendants(matching: .any)["radioDial"].firstMatch
        XCTAssertTrue(dial.waitForExistence(timeout: 10))
        let cover = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'track.'")).firstMatch
        XCTAssertTrue(cover.isHittable)
        let coverPoint = cover.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        coverPoint.press(forDuration: 0.05, thenDragTo: coverPoint.withOffset(CGVector(dx: 0, dy: -220)))
        let tabBar = app.descendants(matching: .any)["radioTabBar"].firstMatch
        XCTAssertGreaterThanOrEqual(dial.frame.minY, 60)
        XCTAssertLessThanOrEqual(dial.frame.maxY, tabBar.frame.minY)
        capture(app, "Radio-Dial-Touch-Viewport")
        let before = dial.value as? String
        let listen = app.buttons["platformFeaturedOpen"]
        let beforeY = listen.frame.minY
        let start = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -130)))
        XCTAssertEqual(dial.value as? String, before, "A vertical page scroll must not tune a different work")
        XCTAssertLessThan(listen.frame.minY, beforeY - 30, "The dial must let a vertical drag scroll the page")
        dial.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: dial.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)))
        XCTAssertNotEqual(dial.value as? String, before, "A horizontal drag must tune a real catalog work")
        XCTAssertFalse(app.buttons["miniPlayer"].exists)
    }
    func testSwitchingTabsKeepsTuningAndCatalogNotebookQueries() {
        let app = launch()
        let next = app.buttons["radioNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 10)); reveal(next, in: app); next.tap()
        let tuned = app.descendants(matching: .any)["radioDial"].firstMatch.value as? String
        app.buttons["tab.shelf"].tap()
        let singles = app.buttons["catalogCategory.singles"]
        XCTAssertTrue(singles.waitForExistence(timeout: 5)); singles.tap()
        let catalogSearch = app.textFields["catalogSearch"]
        catalogSearch.tap(); catalogSearch.typeText("No matching record\n")
        app.buttons["tab.notes"].tap()
        let unfiled = app.buttons["notebook.filter.uncategorized"]
        XCTAssertTrue(unfiled.waitForExistence(timeout: 5)); unfiled.tap()
        let notebookSearch = app.textFields["notebookSearch"]
        notebookSearch.tap(); notebookSearch.typeText("A private search")
        app.buttons["tab.radio"].tap()
        XCTAssertTrue(app.buttons["radioNext"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["radioDial"].firstMatch.value as? String, tuned)
        XCTAssertFalse(app.textFields["catalogSearch"].exists)
        XCTAssertFalse(app.textFields["notebookSearch"].exists)
        app.buttons["tab.shelf"].tap()
        XCTAssertTrue(catalogSearch.waitForExistence(timeout: 5))
        XCTAssertEqual(catalogSearch.value as? String, "No matching record")
        XCTAssertTrue(singles.isSelected)
        app.buttons["tab.notes"].tap()
        XCTAssertTrue(notebookSearch.waitForExistence(timeout: 5))
        XCTAssertEqual(notebookSearch.value as? String, "A private search")
        XCTAssertTrue(unfiled.isSelected)
        capture(app, "Radio-Tab-Return-Notebook-State")
    }
    func testMeSettingsHaveOneRouteAndUseTheChosenAppearance() {
        for appearance in ["paper", "night"] {
            let app = launch(appearance: appearance)
            XCTAssertTrue(app.buttons["tab.me"].waitForExistence(timeout: 10)); app.buttons["tab.me"].tap()
            XCTAssertTrue(app.buttons["favoritesEntry"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["settingsHelpEntry"].exists)
            XCTAssertFalse(app.buttons["legacyDataEntry"].exists)
            for (entry, page) in [("preferencesEntry", "preferencesPage"), ("privacyEntry", "privacyPage"), ("helpEntry", "helpPage")] {
                let link = app.buttons[entry]; reveal(link, in: app); link.tap()
                XCTAssertTrue(app.descendants(matching: .any)[page].firstMatch.waitForExistence(timeout: 5))
                capture(app, "Radio-" + page + "-" + appearance)
                app.navigationBars.buttons.firstMatch.tap()
            }
            reveal(app.buttons["helpEntry"], in: app); app.buttons["helpEntry"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["helpPage"].firstMatch.waitForExistence(timeout: 5))
            app.buttons["tab.shelf"].tap(); app.buttons["tab.me"].tap()
            XCTAssertTrue(app.buttons["favoritesEntry"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.descendants(matching: .any)["helpPage"].firstMatch.exists)
            app.terminate()
        }
    }
    func testStartupCanBeSkippedWhileCatalogStillFinishes() {
        let app = launch(fixture: "song-content", slow: true)
        XCTAssertTrue(app.buttons["startupSkip"].waitForExistence(timeout: 3))
        capture(app, "Radio-Startup")
        app.buttons["startupSkip"].tap()
        XCTAssertTrue(app.buttons["tab.radio"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["platformFeaturedOpen"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["startupRetry"].exists)
        XCTAssertFalse(app.buttons["miniPlayer"].exists)
    }
}
