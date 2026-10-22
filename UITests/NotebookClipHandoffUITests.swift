import XCTest

/// Local HTML fixtures exercise player teardown and native note handoff only.
/// They do not establish real provider playback, sound, or HTTPS availability.
@MainActor final class NotebookClipHandoffUITests: XCTestCase {
    private let clipID = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
    private let fixtureSong = "屏幕朝下"

    override func setUp() { continueAfterFailure = false }

    private func launch(_ provider: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--platform-music-fixture", "-AppleLanguages", "(en)",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launchEnvironment["STATION_PLATFORM_FIXTURE"] = provider + "-clips"
        app.launchEnvironment["STATION_PERSONAL_TEST_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["STATION_PLATFORM_OPEN_FAIL"] = "1"
        app.launch()
        let featured = app.buttons["platformFeaturedOpen"]
        XCTAssertTrue(featured.waitForExistence(timeout: 15)); reveal(featured, app); featured.tap()
        let clips = app.buttons["contentTab.clips"]
        XCTAssertTrue(clips.waitForExistence(timeout: 10)); reveal(clips, app); clips.tap()
        let load = app.buttons[provider + "Load." + clipID]
        XCTAssertTrue(load.waitForExistence(timeout: 10)); reveal(load, app); load.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        let fixtureProvider = provider == "youtube" ? "YouTube" : "Douyin"
        XCTAssertTrue(app.webViews.staticTexts["未连接 " + fixtureProvider + " · 无真实视频"].waitForExistence(timeout: 10))
        return app
    }

    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<12 {
            let frame = element.frame
            // Keep taps above the sticky listening footer. Stop before reaching
            // the sheet's top so a repeated downward swipe cannot dismiss it.
            if element.isHittable && frame.midY > 140 && frame.midY < app.frame.height - 150 { return }
            if frame.midY < 140 { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func openEditor(_ app: XCUIApplication) {
        let write = app.buttons["notebookWriteForSong"]
        XCTAssertTrue(write.waitForExistence(timeout: 5)); reveal(write, app); write.tap()
        XCTAssertTrue(app.buttons["notebookEditorClose"].waitForExistence(timeout: 5))
        let linkedWork = app.buttons["notebookChooseWork"]
        XCTAssertTrue(linkedWork.waitForExistence(timeout: 5))
        XCTAssertTrue(linkedWork.label.contains(fixtureSong), "The notebook must retain the exact work opened in the clip detail")
    }

    private func assertStoppedAfterReturning(_ app: XCUIApplication, provider: String) {
        XCTAssertTrue(app.buttons["notebookEditorClose"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["platformDetailClose"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.webViews.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["miniPlayer"].exists)
        let load = app.buttons[provider + "Load." + clipID]
        XCTAssertTrue(load.waitForExistence(timeout: 5))
        reveal(load, app)
        XCTAssertTrue(load.isHittable, "Returning to the clip requires another explicit load action")
        XCTAssertFalse(app.webViews.firstMatch.exists, "Revealing the clip again must not recreate its player")
    }

    private func exerciseHandoff(_ provider: String) {
        let app = launch(provider)
        openEditor(app)
        XCTAssertTrue(app.webViews.firstMatch.waitForNonExistence(timeout: 5))
        capture(app, "Notebook-" + provider + "-Linked-Editor")
        app.buttons["notebookEditorClose"].tap()
        assertStoppedAfterReturning(app, provider: provider)

        // Exercise saving as a separate user action after the no-autoplay check.
        openEditor(app)
        let title = "My " + provider + " reflection"
        let body = "I wrote these words myself after reading this song."
        let heading = app.descendants(matching: .any).matching(identifier: "notebookTitleField").firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 5)); heading.tap(); heading.typeText(title)
        let text = app.textViews["notebookBodyField"]
        XCTAssertTrue(text.exists); text.tap(); text.typeText(body)
        app.buttons["notebookSave"].tap()
        assertStoppedAfterReturning(app, provider: provider)
        app.buttons["platformDetailClose"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons.element(boundBy: 2).tap()
        let entry = app.buttons["notebookEntry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); reveal(entry, app); entry.tap()

        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "notebook.note."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5)); XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows.firstMatch.label.contains(title))
        capture(app, "Notebook-" + provider + "-Saved-Own-Writing")
        rows.firstMatch.tap()
        XCTAssertTrue(app.textViews["notebookBodyField"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["notebookBodyField"].value as? String, body)
        XCTAssertTrue(app.buttons["notebookChooseWork"].label.contains(fixtureSong))
        XCTAssertFalse(app.webViews.firstMatch.exists)
    }

    func testYouTubeStopsBeforeWritingAndOwnNoteAppearsInNotebook() { exerciseHandoff("youtube") }
    func testDouyinStopsBeforeWritingAndOwnNoteAppearsInNotebook() { exerciseHandoff("douyin") }
}
