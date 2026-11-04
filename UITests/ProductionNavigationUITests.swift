import XCTest

/// Exercises shipping optimization and metadata construction with every remote
/// service closed. The Production UI-only scheme excludes the native test host.
@MainActor final class ProductionNavigationUITests: XCTestCase {
    func testMeSettingsSurviveNavigationAndColdRelaunch() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("This smoke test owns only an isolated CI simulator")
        #endif
        guard ProcessInfo.processInfo.environment["STATION_PRODUCTION_ME_SMOKE"] == "YES" else {
            throw XCTSkip("Run through the closed-service Production UI scheme")
        }
        continueAfterFailure = false
        for appearance in ["paper", "night"] {
            // A new application handle prevents a terminated launch's cached
            // accessibility snapshot from driving the next process.
            let app = XCUIApplication()
            app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
                                   "-radioAppearance", appearance]
            app.launch()
            enterClosedServiceApp(app)
            openMe(app)
            XCTAssertFalse(app.buttons["miniPlayer"].exists)
            for (entry, page) in [("preferencesEntry", "preferencesPage"),
                                  ("privacyEntry", "privacyPage"), ("helpEntry", "helpPage")] {
                let link = app.buttons[entry]
                reveal(link, in: app)
                link.tap()
                XCTAssertTrue(app.descendants(matching: .any)[page].firstMatch.waitForExistence(timeout: 5))
                XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
                let back = app.navigationBars.buttons.firstMatch
                XCTAssertTrue(back.waitForExistence(timeout: 5))
                back.tap()
                XCTAssertTrue(app.buttons["favoritesEntry"].waitForExistence(timeout: 5))
            }
            app.buttons["tab.shelf"].tap()
            XCTAssertTrue(app.textFields["catalogSearch"].waitForExistence(timeout: 5))
            openMe(app)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Production-Me-" + appearance
            shot.lifetime = .keepAlways
            add(shot)
            app.terminate()
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        }
        // Reopen the same on-disk settings after both appearance passes, without
        // DEBUG namespaces, bundled catalog injection or a network transport.
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
                               "-radioAppearance", "night"]
        app.launch()
        enterClosedServiceApp(app)
        openMe(app)
        XCTAssertFalse(app.buttons["miniPlayer"].exists)
        app.terminate()
    }

    private func enterClosedServiceApp(_ app: XCUIApplication) {
        // A disabled Production catalog deliberately reports unavailable. This
        // tests its explicit continue route rather than enabling a live server.
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        let proceed = app.buttons["startupContinue"]
        XCTAssertTrue(proceed.waitForExistence(timeout: 10))
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"), object: proceed)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 5), .completed)
        proceed.tap()
        XCTAssertTrue(app.buttons["tab.me"].waitForExistence(timeout: 5))
    }

    private func openMe(_ app: XCUIApplication) {
        app.buttons["tab.me"].tap()
        XCTAssertTrue(app.buttons["favoritesEntry"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["libraryHome"].firstMatch.exists)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
}
