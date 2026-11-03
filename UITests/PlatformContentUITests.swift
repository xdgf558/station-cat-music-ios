import XCTest

@MainActor final class PlatformContentUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private func closeListeningChooser(_ app: XCUIApplication) {
        let close = app.buttons["platformPickerClose"]
        if close.waitForExistence(timeout: 2) { close.tap() }
    }

    private func launch(locale: String = "zh-Hans", failure: Bool = false, large: Bool = false, appearance: String = "paper") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--platform-music-fixture", "-radioAppearance", appearance, "-platformLyricsFontSize", "18", "-AppleLanguages", "(\(locale))", "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launchEnvironment["STATION_PLATFORM_FIXTURE"] = failure ? "song-content-failure" : "song-content"
        app.launchEnvironment["STATION_PERSONAL_TEST_NAMESPACE"] = UUID().uuidString
        app.launch()
        let open = app.buttons["platformFeaturedOpen"]
        XCTAssertTrue(open.waitForExistence(timeout: 10)); reveal(open, app); open.tap(); closeListeningChooser(app)
        XCTAssertTrue(app.buttons["contentTab.lyrics"].waitForExistence(timeout: 10))
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
                if !modal && home.exists {
                    let reading = CGRect(x: viewport.minX + 20, y: top, width: viewport.width - 40, height: bottom - top)
                    let title = app.buttons.matching(NSPredicate(format: "label == %@", "屏幕朝下")).allElementsBoundByIndex
                    let covers = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "track.")).allElementsBoundByIndex
                    let start = (title + covers).compactMap { candidate -> CGPoint? in
                        guard candidate.isHittable else { return nil }
                        let visible = candidate.frame.intersection(reading)
                        guard !visible.isNull, visible.width > 10, visible.height > 20 else { return nil }
                        return CGPoint(x: visible.midX, y: visible.midY)
                    }.first
                    guard let start else { print("HOME_PAN_NO_CONTENT target=\(frame) viewport=\(reading)"); break }
                    let endY = up ? max(top + 16, start.y - 300) : min(bottom - 16, start.y + 300)
                    print("HOME_PAN_BEFORE start=\(start) endY=\(endY) openMinY=\(frame.minY) viewport=\(reading)")
                    origin.withOffset(CGVector(dx: start.x, dy: start.y))
                        .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: start.x, dy: endY)))
                    print("HOME_PAN_AFTER openMinY=\(element.exists ? element.frame.minY : -1) viewport=\(reading)")
                } else {
                    let x = max(app.frame.minX + 14, viewport.minX + 14)
                    origin.withOffset(CGVector(dx: x, dy: up ? lower : upper))
                        .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: x, dy: up ? upper : lower)))
                }
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
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func assertExists(_ element: XCUIElement, _ app: XCUIApplication, _ failureName: String) {
        let found = element.waitForExistence(timeout: 5)
        if !found { capture(app, failureName); print(app.debugDescription) }
        XCTAssertTrue(found)
    }
    func testNightLyricsAndStoryKeepTheSameReadingAndListeningControls() {
        let app = launch(appearance: "night")
        XCTAssertTrue(app.buttons["lyricLine.0.0"].waitForExistence(timeout: 5))
        capture(app, "Radio-Detail-night")
        reveal(app.buttons["contentTab.story"], app); app.buttons["contentTab.story"].tap()
        XCTAssertTrue(app.staticTexts["contentStoryText"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["platformLink.netease"].isHittable)
        capture(app, "Radio-Story-night")
        XCTAssertFalse(app.buttons["miniPlayer"].exists)
    }
    func testSelectedContentLayoutReadingSizeAndEmptyClips() {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["lyricStanza.0"].firstMatch.waitForExistence(timeout: 5))
        capture(app, "Content-Lyrics-zh-Hans")
        XCTAssertTrue(app.buttons["platformLink.netease"].isHittable)
        XCTAssertTrue(app.buttons["platformShare"].exists)
        XCTAssertEqual(app.sliders.count, 0); XCTAssertFalse(app.buttons["miniPlayer"].exists)
        reveal(app.buttons["lyricTextSize"], app); app.buttons["lyricTextSize"].tap()
        app.buttons["更大"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["lyricStanza.0"].firstMatch.exists)
        capture(app, "Content-Lyrics-Large")
        reveal(app.buttons["lyricsExpand"], app); app.buttons["lyricsExpand"].tap()
        let expandedStanza = app.descendants(matching: .any)["lyricStanza.2"].firstMatch
        reveal(expandedStanza, app)
        assertExists(expandedStanza, app, "Content-Expand-Failure")
        reveal(app.buttons["contentTab.clips"], app); app.buttons["contentTab.clips"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["clipsEmpty"].firstMatch.waitForExistence(timeout: 5))
        capture(app, "Content-Clips-Empty")
        reveal(app.buttons["contentTab.story"], app); app.buttons["contentTab.story"].tap()
        XCTAssertTrue(app.staticTexts["contentStoryText"].waitForExistence(timeout: 5))
        capture(app, "Content-Story")
        app.buttons["platformDetailClose"].tap()
        XCTAssertTrue(app.buttons["platformFeaturedOpen"].waitForExistence(timeout: 5))
    }
    func testLyricsFailureCanRetryWithoutLosingListeningOrOtherTabs() {
        let app = launch(failure: true)
        XCTAssertTrue(app.buttons["lyricsRetry"].waitForExistence(timeout: 5))
        capture(app, "Content-Lyrics-Retry")
        XCTAssertTrue(app.buttons["platformLink.netease"].exists)
        reveal(app.buttons["contentTab.clips"], app); app.buttons["contentTab.clips"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["clipsEmpty"].firstMatch.waitForExistence(timeout: 5))
        reveal(app.buttons["contentTab.lyrics"], app); app.buttons["contentTab.lyrics"].tap()
        reveal(app.buttons["lyricsRetry"], app); app.buttons["lyricsRetry"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["lyricStanza.0"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["lyricsRetry"].exists)
    }
    func testFourLocalesAndAccessibilitySizesKeepTabsReachable() {
        for locale in ["zh-Hans", "zh-Hant", "en", "ja"] {
            let app = launch(locale: locale, large: true)
            reveal(app.buttons["platformLink.netease"], app)
            capture(app, "Content-" + locale + "-Large-Header")
            reveal(app.buttons["contentTab.clips"], app); app.buttons["contentTab.clips"].tap()
            assertExists(app.descendants(matching: .any)["clipsEmpty"].firstMatch, app, "Content-" + locale + "-Clips-Switch-Failure")
            reveal(app.buttons["contentTab.story"], app); app.buttons["contentTab.story"].tap()
            let storyVisible = app.staticTexts["contentStoryText"].waitForExistence(timeout: 5)
            if !storyVisible { capture(app, "Content-Story-Switch-Failure"); print(app.debugDescription) }
            XCTAssertTrue(storyVisible)
            reveal(app.staticTexts["contentStoryText"], app)
            capture(app, "Content-" + locale + "-Large-Story")
            app.buttons["platformDetailClose"].tap(); app.terminate()
        }
    }
    func testOnlyTheActivelyChosenLyricLineIsSavedToLocalNotebook() {
        let app = launch()
        let line = app.buttons["lyricLine.0.0"]
        assertExists(line, app, "Content-Lyric-Line-Failure"); reveal(line, app); line.tap()
        let quoteAction = app.buttons["lyricQuoteToNote"]
        XCTAssertTrue(quoteAction.waitForExistence(timeout: 5)); quoteAction.tap()
        let quote = app.descendants(matching: .any)["notebookQuote"].firstMatch
        XCTAssertTrue(quote.waitForExistence(timeout: 5))
        XCTAssertTrue(quote.label.contains("手机亮了一下 你把消息回完"))
        XCTAssertFalse(quote.label.contains("顺手扣向桌面"))
        let title = app.textFields["notebookTitleField"]
        XCTAssertTrue((title.value as? String ?? "").isEmpty || title.value as? String == title.placeholderValue)
        let body = app.textViews["notebookBodyField"]
        XCTAssertTrue((body.value as? String ?? "").isEmpty)
        capture(app, "Radio-User-Selected-Quote")
        app.buttons["notebookSave"].tap()
        XCTAssertTrue(app.buttons["notebookEditorClose"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["platformDetailClose"].waitForNonExistence(timeout: 5))
        let notes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "notebook.note."))
        XCTAssertTrue(notes.firstMatch.waitForExistence(timeout: 5)); XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.firstMatch.label.components(separatedBy: "手机亮了一下 你把消息回完").count - 1, 1)
        XCTAssertFalse(notes.firstMatch.label.contains("顺手扣向桌面"))
        notes.firstMatch.tap()
        XCTAssertTrue(app.buttons["notebookUnlinkWork"].waitForExistence(timeout: 5))
        XCTAssertTrue((title.value as? String ?? "").isEmpty || title.value as? String == title.placeholderValue)
        XCTAssertTrue((body.value as? String ?? "").isEmpty)
        app.buttons["notebookUnlinkWork"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["notebookQuote"].firstMatch.exists)
        body.tap(); body.typeText("继续写自己的话。")
        app.buttons["notebookSave"].tap()
    }

}
