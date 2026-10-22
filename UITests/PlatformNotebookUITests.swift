import XCTest
import UIKit

@MainActor final class PlatformNotebookUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private func launch(locale: String = "en", large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--platform-music-fixture", "-AppleLanguages", "(\(locale))", "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launchEnvironment["STATION_PLATFORM_FIXTURE"] = "song-content"
        app.launchEnvironment["STATION_PERSONAL_TEST_NAMESPACE"] = UUID().uuidString
        app.launch(); XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        return app
    }
    private func enter(_ app: XCUIApplication) {
        app.tabBars.buttons.element(boundBy: 2).tap()
        let entry = app.buttons["notebookEntry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        XCTAssertTrue(app.buttons["notebookNew"].waitForExistence(timeout: 5))
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<10 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    private func field(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        // App-coordinate screenshots crop iPhone compatibility windows on iPad.
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    private func addNote(_ app: XCUIApplication, title: String, body: String) {
        reveal(app.buttons["notebookNew"], app: app); app.buttons["notebookNew"].tap()
        let heading = field(app, "notebookTitleField")
        XCTAssertTrue(heading.waitForExistence(timeout: 5)); heading.tap(); heading.typeText(title)
        let text = app.textViews["notebookBodyField"]; text.tap(); text.typeText(body)
        app.buttons["notebookSave"].tap()
        XCTAssertTrue(app.buttons["notebookNew"].waitForExistence(timeout: 5))
    }
    private func rows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "notebook.note."))
    }
    private func paste(_ value: String, into element: XCUIElement, app: XCUIApplication) {
        // The simulator test runner and tested app share this pasteboard. Use
        // the real system Paste action, not typeText (which sends Return keys).
        UIPasteboard.general.string = value
        element.tap(); element.press(forDuration: 1.2)
        let menuItem = app.menuItems["Paste"]
        if menuItem.waitForExistence(timeout: 2) { menuItem.tap() }
        else {
            let button = app.buttons["Paste"].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 3)); button.tap()
        }
    }
    func testTitleNextMovesTypingToBodyAndSavesSingleLineTitle() {
        let app = launch(); enter(app); app.buttons["notebookNew"].tap()
        let heading = app.textFields["notebookTitleField"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5)); heading.tap(); heading.typeText("A title")
        // Send the actual Return key. The keyboard exposes a localized/lowercase
        // label (for example "next"), which is not a stable app identifier.
        heading.typeText("\n")
        // Do not tap the body: subsequent typing must follow the focus change.
        app.typeText("My own words belong in the body.")
        XCTAssertEqual(heading.value as? String, "A title")
        XCTAssertEqual(app.textViews["notebookBodyField"].value as? String, "My own words belong in the body.")
        XCTAssertTrue(app.staticTexts["notebookTextLimits"].exists)
        app.buttons["notebookSave"].tap()
        XCTAssertTrue(app.buttons["notebookNew"].waitForExistence(timeout: 5)); XCTAssertEqual(rows(app).count, 1)
        rows(app).firstMatch.tap()
        XCTAssertTrue(app.textFields["notebookTitleField"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["notebookTitleField"].value as? String, "A title")
        XCTAssertEqual(app.textViews["notebookBodyField"].value as? String, "My own words belong in the body.")
    }
    func testPastedMultilineTitlePreservesWordsAsSingleLine() {
        let app = launch(); enter(app)
        let examples = [("First line\nSecond line", "First line Second line"),
                        ("First thought\r\nSecond thought", "First thought Second thought")]
        for (index, example) in examples.enumerated() {
            app.buttons["notebookNew"].tap()
            let heading = app.textFields["notebookTitleField"]
            XCTAssertTrue(heading.waitForExistence(timeout: 5)); paste(example.0, into: heading, app: app)
            XCTAssertEqual(heading.value as? String, example.1)
            // UIKit may already replace line breaks before the Binding setter.
            // The permanent rule is visible either way; the persisted text is
            // the contract, rather than requiring a transient conversion hint.
            XCTAssertTrue(app.staticTexts["notebookTextLimits"].exists)
            app.buttons["notebookSave"].tap()
            XCTAssertTrue(app.buttons["notebookNew"].waitForExistence(timeout: 5)); XCTAssertEqual(rows(app).count, index + 1)
            let saved = rows(app).matching(NSPredicate(format: "label CONTAINS %@", example.1)).firstMatch
            XCTAssertTrue(saved.waitForExistence(timeout: 5)); saved.tap()
            XCTAssertTrue(app.textFields["notebookTitleField"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.textFields["notebookTitleField"].value as? String, example.1)
            app.buttons["notebookEditorClose"].tap()
            XCTAssertTrue(app.buttons["notebookNew"].waitForExistence(timeout: 5))
        }
        UIPasteboard.general.items = []
    }
    func testRejectedTitleKeepsCompleteDraftForCorrectionAndRetry() {
        let app = launch(); enter(app); app.buttons["notebookNew"].tap()
        let overlong = String(repeating: "a", count: 121)
        let body = "First thought.\nSecond thought stays here."
        let heading = app.textFields["notebookTitleField"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5)); heading.tap(); heading.typeText(overlong)
        let text = app.textViews["notebookBodyField"]; text.tap(); text.typeText(body)
        app.buttons["notebookSave"].tap()
        let error = field(app, "notebookError")
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["notebookEditorClose"].exists)
        XCTAssertEqual(heading.value as? String, overlong, "An invalid title must not be silently truncated")
        XCTAssertEqual(text.value as? String, body, "A rejected save must retain the complete body")
        heading.tap(); heading.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(heading.value as? String, String(repeating: "a", count: 120))
        XCTAssertEqual(text.value as? String, body)
        app.buttons["notebookSave"].tap()
        XCTAssertTrue(app.buttons["notebookNew"].waitForExistence(timeout: 5)); XCTAssertEqual(rows(app).count, 1)
        rows(app).firstMatch.tap()
        XCTAssertTrue(app.textFields["notebookTitleField"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["notebookTitleField"].value as? String, String(repeating: "a", count: 120))
        XCTAssertEqual(app.textViews["notebookBodyField"].value as? String, body)
        capture(app, "Notebook-Corrected-Title-Draft-Retained")
    }
    func testWritingSearchOfflineReopenAndClear() {
        let app = launch(); enter(app)
        capture(app, "Notebook-Empty")
        addNote(app, title: "A quiet evening", body: "I want to slow down and listen more closely.")
        addNote(app, title: "The long way home", body: "Some songs make an ordinary walk feel different.")
        addNote(app, title: "Notes for tomorrow", body: "Leave a little room for what comes next.")
        XCTAssertEqual(rows(app).count, 3)
        capture(app, "Notebook-Topic-Index")
        let search = app.textFields["notebookSearch"]; search.tap(); search.typeText("quiet")
        XCTAssertEqual(rows(app).count, 1)
        app.terminate(); app.launchEnvironment["STATION_STARTUP_PREVIEW"] = "failure"
        app.launch(); XCTAssertTrue(app.buttons["startupContinue"].waitForExistence(timeout: 15)); app.buttons["startupContinue"].tap()
        enter(app); XCTAssertEqual(rows(app).count, 3)
        rows(app).firstMatch.tap()
        XCTAssertTrue(app.textViews["notebookBodyField"].waitForExistence(timeout: 5))
        capture(app, "Notebook-Offline-Editor")
        app.buttons["notebookEditorClose"].tap()
        reveal(app.buttons["notebookManageTopics"], app: app); app.buttons["notebookManageTopics"].tap()
        app.buttons["notebookClear"].tap()
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["notebookClear"].exists)
        app.buttons["notebookClear"].tap(); app.alerts.buttons["Clear all notes"].tap()
        XCTAssertTrue(app.buttons["notebookNew"].waitForExistence(timeout: 5)); XCTAssertEqual(rows(app).count, 0)
        app.terminate(); app.launch(); XCTAssertTrue(app.buttons["startupContinue"].waitForExistence(timeout: 15)); app.buttons["startupContinue"].tap()
        enter(app); XCTAssertEqual(rows(app).count, 0)
    }
    func testTopicsAndDiscardUnsavedWriting() {
        let app = launch(); enter(app)
        app.buttons["notebookManageTopics"].tap(); app.buttons["notebookNewTopic"].tap()
        let name = app.textFields["notebookTopicName"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Everyday")
        app.buttons["notebookSaveTopic"].tap()
        XCTAssertTrue(app.staticTexts["Everyday"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Everyday"].waitForExistence(timeout: 5))
        app.buttons["notebookNew"].tap()
        let heading = field(app, "notebookTitleField"); XCTAssertTrue(heading.waitForExistence(timeout: 5)); heading.tap(); heading.typeText("Unsaved words")
        app.buttons["notebookEditorClose"].tap()
        app.buttons["Keep editing"].tap()
        XCTAssertEqual(heading.value as? String, "Unsaved words")
        app.buttons["notebookEditorClose"].tap(); app.buttons["Discard changes"].tap()
        XCTAssertTrue(app.buttons["notebookNew"].waitForExistence(timeout: 5)); XCTAssertEqual(rows(app).count, 0)
    }
    func testChineseTopicFilteringAndLinkedWork() {
        let app = launch(locale: "zh-Hans"); enter(app)
        app.buttons["notebookManageTopics"].tap()
        for topic in ["日常", "关系"] {
            app.buttons["notebookNewTopic"].tap()
            let name = app.textFields["notebookTopicName"]; XCTAssertTrue(name.waitForExistence(timeout: 5))
            name.tap(); name.typeText(topic); app.buttons["notebookSaveTopic"].tap()
            XCTAssertTrue(app.staticTexts[topic].waitForExistence(timeout: 5))
        }
        app.navigationBars.buttons["关闭"].tap()
        addNote(app, title: "给明天留一点空间", body: "今天不必把所有事情做完。")
        addNote(app, title: "把脚步放慢", body: "一段旋律，让普通的回家路变得不同。")
        app.buttons["notebookNew"].tap()
        let title = field(app, "notebookTitleField"); XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText("屏幕朝下的一刻")
        let body = app.textViews["notebookBodyField"]; body.tap(); body.typeText("我的想法：把手机放下，多听一听身边的人。")
        reveal(app.buttons["notebookChooseWork"], app: app); app.buttons["notebookChooseWork"].tap()
        let work = app.buttons["notebook.song.883d3be1-2f28-4d81-b590-c3be6d80e8cd"]
        XCTAssertTrue(work.waitForExistence(timeout: 5)); work.tap()
        let picker = app.buttons["notebookTopicPicker"]; reveal(picker, app: app); picker.tap()
        let option = app.buttons.matching(identifier: "关系").allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(option); option?.tap()
        app.buttons["notebookSave"].tap()
        XCTAssertTrue(app.buttons["notebookNew"].waitForExistence(timeout: 5))
        XCTAssertEqual(rows(app).count, 3)
        capture(app, "Notebook-Selected-3-zh-Hans")
        app.buttons["关系"].tap(); XCTAssertEqual(rows(app).count, 1)
        XCTAssertTrue(rows(app).firstMatch.label.contains("屏幕朝下的一刻"))
        rows(app).firstMatch.tap()
        XCTAssertTrue(app.buttons["notebookChooseWork"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["notebookChooseWork"].label.contains("屏幕朝下"))
        capture(app, "Notebook-Linked-Editor-zh-Hans")
        app.buttons["notebookEditorClose"].tap()
        app.buttons["notebookManageTopics"].tap()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "notebook.topic.actions.", "关系")).firstMatch.tap()
        app.buttons["删除主题"].tap(); app.alerts.buttons["删除主题"].tap()
        app.navigationBars.buttons["关闭"].tap()
        app.buttons["notebook.filter.uncategorized"].tap()
        XCTAssertEqual(rows(app).count, 3, "Removing the topic must retain its note as Uncategorized")
    }
    func testNotebookFourLanguagesAndLargeText() {
        for locale in ["zh-Hans", "zh-Hant", "en", "ja"] {
            let app = launch(locale: locale, large: true); enter(app)
            reveal(app.buttons["notebookNew"], app: app)
            capture(app, "Notebook-" + locale + "-AXXXL")
            app.buttons["notebookNew"].tap()
            XCTAssertTrue(field(app, "notebookTitleField").waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["notebookEditorClose"].isHittable)
            capture(app, "Notebook-Editor-" + locale + "-AXXXL")
            app.buttons["notebookEditorClose"].tap(); app.terminate()
        }
    }
}
