import XCTest

@MainActor final class R3BackgroundPlaybackUITests: XCTestCase {
    func testPhysicalHomeAndReturnKeepsProgress() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical device acceptance only")
        #else
        guard ProcessInfo.processInfo.environment["R3_ENABLE_PHYSICAL_PLAYBACK"] == "YES" else { throw XCTSkip("Explicit isolated physical playback only") }
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "org.stationcat.music.staging")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer {
            app.activate()
            if app.buttons["Pause"].firstMatch.exists { app.buttons["Pause"].firstMatch.tap() }
            app.terminate()
        }
        let track = app.buttons["track.a3d01b06-8c4c-4a8a-9d66-25429d2ad843"].firstMatch
        XCTAssertTrue(track.waitForExistence(timeout: 20))
        track.tap()
        let play = app.buttons["Play"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        play.tap()
        let elapsed = app.staticTexts["playbackElapsed"].firstMatch
        let progressing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            elapsed.exists && self.seconds(elapsed.label) >= 2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [progressing], timeout: 20), .completed)
        let before = seconds(elapsed.label)
        XCUIDevice.shared.press(.home)
        let background = XCTNSPredicateExpectation(predicate: NSPredicate(format: "state == %d OR state == %d", XCUIApplication.State.runningBackground.rawValue, XCUIApplication.State.runningBackgroundSuspended.rawValue), object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [background], timeout: 5), .completed)
        // App is not touched during this interval. This tests actual suspension
        // behavior, not a synthetic interruption notification.
        let hold = XCTestExpectation(description: "Background interval")
        DispatchQueue.main.asyncAfter(deadline: .now() + 70) { hold.fulfill() }
        XCTAssertEqual(XCTWaiter.wait(for: [hold], timeout: 75), .completed)
        app.activate()
        XCTAssertTrue(elapsed.waitForExistence(timeout: 10))
        let after = seconds(elapsed.label)
        XCTAssertGreaterThanOrEqual(after - before, 60)
        XCTAssertTrue(app.buttons["Pause"].firstMatch.exists)
        print("R3_BACKGROUND_PASSED: elapsed_before=\(before); elapsed_after=\(after); home_interval=70")
        #endif
    }
    private func seconds(_ value: String) -> Int {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        return parts.count == 2 ? parts[0] * 60 + parts[1] : -1
    }
}
