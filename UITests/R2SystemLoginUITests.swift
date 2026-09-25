import XCTest

// Dedicated opt-in UI acceptance. This launches the actual signed Staging app,
// uses its ASWebAuthenticationSession, and enters only the synthetic R2 account.
// No product methods, browser replacement, token injection or HTTP shortcuts.
@MainActor final class R2SystemLoginUITests: XCTestCase {
    #if targetEnvironment(simulator)
    private let physicalDevice = false
    #else
    private let physicalDevice = true
    #endif
    private enum Failure: Error { case input, checkpoint }
    private struct Identity: Decodable { let username: String; let password: String }
    private struct Input: Decodable { let origin: String; let free: Identity }
    private let bundle = "org.stationcat.music.staging"
    private func input() throws -> Input {
        guard let path = ProcessInfo.processInfo.environment["R2_PRIVATE_INPUT"], path.hasPrefix("/") else { throw Failure.input }
        let url = URL(fileURLWithPath: path), attrs = try FileManager.default.attributesOfItem(atPath: path)
        guard attrs[.type] as? FileAttributeType == .typeRegular,
              (attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600,
              ((attrs[.size] as? NSNumber)?.intValue ?? Int.max) <= 8192,
              try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw Failure.input }
        let value = try JSONDecoder().decode(Input.self, from: Data(contentsOf: url))
        guard value.origin == "https://station-cat-music-r2.yehao1105.workers.dev",
              value.free.username == "r2tester-free", (16...256).contains(value.free.password.count) else { throw Failure.input }
        return value
    }
    private func ready(_ element: XCUIElement, timeout: TimeInterval = 20) throws {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true AND enabled == true"), object: element)
        guard XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed else { throw Failure.checkpoint }
    }
    private func reveal(_ element: XCUIElement, in web: XCUIElement) throws {
        guard element.waitForExistence(timeout: 10) else { throw Failure.checkpoint }
        for _ in 0..<3 {
            if element.isHittable && element.frame.minY >= web.frame.minY && element.frame.maxY <= web.frame.maxY { return }
            web.swipeUp()
        }
        try ready(element, timeout: 5)
    }
    private func isLoginConsent(_ alert: XCUIElement) -> Bool {
        let text = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ").lowercased()
        if text.contains("station-cat-music-r2.yehao1105.workers.dev") { return true }
        let isOurApp = text.contains("stationcatmusic") || text.contains("station cat")
        return isOurApp && ["sign in", "signin", "log in", "登录", "登入"].contains { text.contains($0) }
    }
    private func declinePasswordSave(in owners: [XCUIApplication], wait: TimeInterval = 0) throws {
        // The observed system prompt is an Alert titled 保存密码？ with 以后 and
        // 保存. Match that exact prompt shape; never dismiss an unrelated alert
        // and never save the synthetic password to the user's password manager.
        let title = NSPredicate(format: "label IN %@", ["保存密码？", "儲存密碼？", "Save Password?"])
        for (index, owner) in owners.enumerated() {
            let alert = owner.alerts.matching(title).firstMatch
            if index == 0 && wait > 0 { _ = alert.waitForExistence(timeout: wait) }
            guard alert.exists else { continue }
            let later = alert.buttons.matching(NSPredicate(format: "label IN %@", ["以后", "以後", "稍後", "Not Now"])).firstMatch
            let save = alert.buttons.matching(NSPredicate(format: "label IN %@", ["保存", "儲存", "Save", "Save Password"])).firstMatch
            guard save.exists else { throw Failure.checkpoint }
            try ready(later, timeout: 5); later.tap()
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: alert)
            guard XCTWaiter.wait(for: [dismissed], timeout: 5) == .completed else { throw Failure.checkpoint }
            print("R2_SYSTEM_UI_ACTION:password_save_declined")
        }
    }
    func testRealSystemBrowserSignsInAndReturnsToStaging() throws {
        guard ProcessInfo.processInfo.environment["R2_ENABLE_SYSTEM_UI"] == "YES" else { throw XCTSkip("Explicit isolated R2 system UI acceptance only") }
        // Record the outcome only after cleanup. An early XCTFail with this set
        // to false can abort the test before a just-created session signs out.
        continueAfterFailure = true
        var phase = "private_input", success = false, launched = false, browserStarted = false, passwordEntered = false
        var failedPhase: String?, cleanupConfirmed = false
        func mark(_ value: String) { phase = value; print("R2_SYSTEM_UI_PHASE:\(value)") }
        let app = XCUIApplication(bundleIdentifier: bundle)
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        do {
            mark("private_input")
            let value = try input()
            mark("launch_staging")
            app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            launched = true
            app.launch()
            let tab = app.tabBars.buttons["You"]
            try ready(tab); tab.tap()
            try ready(app.buttons["accountEntry"]); app.buttons["accountEntry"].tap()
            guard app.staticTexts["Isolated authentication test environment"].waitForExistence(timeout: 15) else { throw Failure.checkpoint }
            // The runner checks the exact compiled origin before launch. A restored
            // synthetic Staging session is signed out before exercising a fresh flow.
            if app.buttons["Sign out"].waitForExistence(timeout: 3) {
                try ready(app.buttons["Sign out"]); app.buttons["Sign out"].tap()
            }
            mark("open_system_browser")
            let signIn = app.buttons["Sign in with Station Cat"]
            try ready(signIn); browserStarted = true; signIn.tap()
            // Some OS versions present the system domain-consent alert first.
            // Continue is accepted only when the alert identifies our login or
            // exact R2 host. Never confirm an unrelated SpringBoard alert.
            for owner in [app, system] {
                let alert = owner.alerts.firstMatch
                if alert.waitForExistence(timeout: 2), alert.buttons["Continue"].exists {
                    guard isLoginConsent(alert) else { throw Failure.checkpoint }
                    alert.buttons["Continue"].tap()
                }
            }
            mark("system_login_form")
            let web = app.webViews.firstMatch
            guard web.waitForExistence(timeout: 25) else { throw Failure.checkpoint }
            guard web.staticTexts["Sign in to Station Cat Music"].waitForExistence(timeout: 10) else { throw Failure.checkpoint }
            let usernameQuery = web.textFields.matching(NSPredicate(format: "label == %@", "Username or email"))
            let passwordQuery = web.secureTextFields.matching(NSPredicate(format: "label == %@", "Password"))
            guard usernameQuery.count == 1, passwordQuery.count == 1 else { throw Failure.checkpoint }
            let username = usernameQuery.element(boundBy: 0), password = passwordQuery.element(boundBy: 0)
            mark("username_focus")
            try reveal(username, in: web)
            try ready(username); username.tap()
            // Do not gate input on hasFocus or app.keyboards. This system browser
            // exposes all fields as focused, while its visible remote keyboard
            // is absent from both the app and SpringBoard accessibility trees.
            mark("username_input")
            username.typeText(value.free.username)
            mark("username_value")
            // Compare privately; failure output must never include either value.
            guard username.value as? String == value.free.username else { throw Failure.checkpoint }
            mark("password_focus")
            // Public keyboard navigation moves to the next actual form field.
            // password.typeText below still fails if it lacks real input focus.
            username.typeText("\t")
            try ready(password)
            password.tap()
            mark("password_input")
            // Set before typeText: even an interrupted partial entry must prohibit
            // a screenshot of this form until the browser has been dismissed.
            passwordEntered = true
            password.typeText(value.free.password)
            mark("submit_navigation")
            guard web.textFields["Two-step code (required if enabled)"].exists else { throw Failure.checkpoint }
            // The isolated synthetic account has no TOTP. Tab through that
            // verified optional field to Continue, then click the actual button.
            password.typeText("\t\t")
            mark("submit_system_login")
            let submit = web.buttons["Continue"]
            try ready(submit); submit.tap()
            mark("password_save_prompt")
            try declinePasswordSave(in: [app, system], wait: 4)
            mark("https_callback_return")
            guard app.staticTexts["Signed in"].waitForExistence(timeout: 35) else { throw Failure.checkpoint }
            try declinePasswordSave(in: [app, system])
            try ready(app.buttons["Sign out"])
            guard !app.webViews.firstMatch.exists, !app.otherElements["TopBrowserBar"].exists,
                  app.state == .runningForeground else { throw Failure.checkpoint }
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "R2-system-login-returned-to-Staging"; attachment.lifetime = .keepAlways; add(attachment)
            success = true
        } catch {
            // XCTest's private activity/xcresult may include typed synthetic values;
            // the runner keeps it local and scrubs known credentials from text logs.
            failedPhase = phase
            if browserStarted && !passwordEntered && app.state == .runningForeground && app.webViews.firstMatch.exists {
                let attachment = XCTAttachment(screenshot: app.screenshot())
                attachment.name = "R2-login-focus-before-password-private"; attachment.lifetime = .keepAlways; add(attachment)
            }
        }
        // Try cleanup even if login succeeded but a following UI check failed.
        // Invalid input never launches or changes an existing app session.
        if launched {
            do {
                mark("signout_cleanup")
                app.activate()
                if browserStarted {
                    if passwordEntered { try declinePasswordSave(in: [app, system]) }
                    for owner in [app, system] {
                        let alert = owner.alerts.firstMatch
                        if alert.exists, isLoginConsent(alert) {
                            let cancel = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "取消"])).firstMatch
                            if cancel.isHittable { cancel.tap() }
                        }
                    }
                    let browserBar = app.otherElements["TopBrowserBar"]
                    if browserBar.exists {
                        // This is the browser requested above. The private AX
                        // evidence identifies TopBrowserBar > identifier "关闭",
                        // label "取消" on the Chinese system, despite English app
                        // launch arguments. Restrict cancellation to that toolbar.
                        let close = NSPredicate(format: "identifier IN %@ AND label IN %@", ["关闭", "Close"], ["取消", "Cancel", "Close"])
                        // JSON error responses may have no WebView in AX. The
                        // owned browser toolbar still identifies the open session.
                        let cancel = browserBar.buttons.matching(close).firstMatch
                        guard cancel.isHittable else { throw Failure.checkpoint }
                        cancel.tap()
                        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: browserBar)
                        guard XCTWaiter.wait(for: [dismissed], timeout: 10) == .completed else { throw Failure.checkpoint }
                    }
                }
                let tab = app.tabBars.buttons["You"]
                try ready(tab); tab.tap()
                if app.buttons["accountEntry"].isHittable { app.buttons["accountEntry"].tap() }
                let signOut = app.buttons["Sign out"]
                if signOut.waitForExistence(timeout: 5) { try ready(signOut); signOut.tap() }
                try ready(app.buttons["Sign in with Station Cat"])
                guard app.staticTexts["Listening as a guest"].exists, !app.webViews.firstMatch.exists,
                      !app.otherElements["TopBrowserBar"].exists else { throw Failure.checkpoint }
                cleanupConfirmed = true
            } catch { failedPhase = failedPhase ?? "signout_cleanup" }
        }
        if success && cleanupConfirmed && failedPhase == nil {
            print("R2_SYSTEM_LOGIN_PASSED: actual_ASWebAuthenticationSession=true HTTPS_callback=true authenticated_UI=true signed_out=true physical_device=\(physicalDevice)")
        } else {
            if launched, app.state == .runningForeground, !app.webViews.firstMatch.exists,
               !app.otherElements["TopBrowserBar"].exists {
                let attachment = XCTAttachment(screenshot: app.screenshot())
                attachment.name = "R2-system-login-after-cleanup-failure"; attachment.lifetime = .keepAlways; add(attachment)
                let authMessagePresent = app.staticTexts["authMessage"].exists
                print("R2_SYSTEM_UI_DIAGNOSTIC auth_message_present=\(authMessagePresent) cleanup_confirmed=\(cleanupConfirmed)")
            }
            // Both the original failure and unsuccessful cleanup remain explicit.
            if launched && !cleanupConfirmed { print("R2_SYSTEM_UI_FAILED phase=signout_cleanup category=checkpoint") }
            XCTFail("R2_SYSTEM_UI_FAILED phase=\(failedPhase ?? "https_callback_return") category=checkpoint")
        }
    }
}
