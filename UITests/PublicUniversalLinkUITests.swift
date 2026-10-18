import XCTest

// Opt-in device acceptance. URLs go through the OS default handler, never
// through AppModel or a target-app openURL injection. No platform button is tapped.
@MainActor final class PublicUniversalLinkUITests: XCTestCase {
    private let bundleID = "org.stationcat.music"
    private let origin = "https://wwwstationcat.org"

    private func requireOptIn() throws {
        guard ProcessInfo.processInfo.environment["STATION_PUBLIC_LINK_ACCEPTANCE"] == "YES" else {
            throw XCTSkip("Explicit public Universal Links device acceptance only")
        }
        continueAfterFailure = false
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    func testColdAndWarmPublicSongDispatch() throws {
        try requireOptIn()
        let environment = ProcessInfo.processInfo.environment
        let songs = try (1...2).map { index -> (slug: String, title: String) in
            let slug = try XCTUnwrap(environment["STATION_LINK_SONG_\(index)_SLUG"])
            let title = try XCTUnwrap(environment["STATION_LINK_SONG_\(index)_TITLE"])
            XCTAssertNotNil(slug.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression))
            XCTAssertLessThanOrEqual(slug.count, 128)
            XCTAssertFalse(title.isEmpty); XCTAssertLessThanOrEqual(title.count, 300)
            return (slug, title)
        }
        XCTAssertNotEqual(songs[0].slug, songs[1].slug)
        let app = XCUIApplication(bundleIdentifier: bundleID)
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 45))
        // Alternate songs so a stale sheet cannot pass the next navigation check.
        for (index, prefix) in ["", "/zh-hant", "/zh-hans", "/en", "/ja"].enumerated() {
            for cold in [true, false] {
                let song = songs[cold ? 0 : 1]
                let phase = "public-link-\(index)-" + (cold ? "cold" : "warm")
                if cold {
                    app.terminate()
                    XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
                } else {
                    XCUIDevice.shared.press(.home)
                    let background = XCTNSPredicateExpectation(predicate: NSPredicate(
                        format: "state == %d OR state == %d",
                        Int(XCUIApplication.State.runningBackground.rawValue),
                        Int(XCUIApplication.State.runningBackgroundSuspended.rawValue)), object: app)
                    XCTAssertEqual(XCTWaiter.wait(for: [background], timeout: 10), .completed)
                }
                let url = try XCTUnwrap(URL(string: origin + prefix + "/music/tracks/" + song.slug +
                    "/?utm_source=acceptance&utm_medium=link&utm_campaign=public-links&utm_content=" + phase))
                XCUIDevice.shared.system.open(url)
                XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), phase)
                XCTAssertTrue(app.scrollViews["platformDetailScreen"].waitForExistence(timeout: 30), phase)
                XCTAssertTrue(app.staticTexts[song.title].waitForExistence(timeout: 20), phase)
                XCTAssertTrue(app.buttons["platformFavorite"].label.contains(song.title), phase)
                XCTAssertFalse(app.buttons["miniPlayer"].exists, phase)
                XCTAssertFalse(app.buttons["playerQueue"].exists, phase)
                capture(app, name: phase)
                print("PUBLIC_SYSTEM_LINK_PASSED prefix_index=\(index) cold=\(cold)")
                app.buttons["platformDetailClose"].tap()
            }
        }
    }

    func testCurrentVersionAndReleaseNotes() throws {
        try requireOptIn()
        let app = XCUIApplication(bundleIdentifier: bundleID)
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 45))
        app.tabBars.buttons["我的"].tap()
        for _ in 0..<5 {
            if app.buttons["helpEntry"].isHittable { break }
            app.swipeUp()
        }
        app.buttons["helpEntry"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "0.1.0 (10)")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["releaseNotesEntry"].tap()
        XCTAssertTrue(app.staticTexts["Station Cat Music · 0.1.0 (10)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["支持从其他 App 的 Station Cat 歌曲链接进入对应作品页面；具体打开方式由 iOS 和来源 App 决定。"].exists)
        capture(app, name: "public-links-build9-release-notes")
    }
}
