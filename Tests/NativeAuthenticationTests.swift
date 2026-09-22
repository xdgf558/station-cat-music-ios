import XCTest
import CryptoKit
@testable import StationCatMusic

@MainActor final class FixtureBrowser: AuthenticationBrowser {
    var callbackOverride: URL?
    func authorize(url: URL, callback: URL) async throws -> URL {
        if let callbackOverride { return callbackOverride }
        let state = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "state" }!.value!
        return URL(string: callback.absoluteString + "?code=" + String(repeating: "C", count: 43) + "&state=" + state)!
    }
}
actor AuthFixtureTransport {
    var requests: [URLRequest] = []
    var failRefresh = false
    var mismatch = false
    var holdRefresh = false
    var refreshEntered = false
    var waiter: CheckedContinuation<Void, Never>?
    var account = "fixture-A"
    var deletionID = ""
    var receiptExpires = Date().addingTimeInterval(86400)
    var prepareExpires = Date().addingTimeInterval(600)
    var failConfirm = false
    var failLogout = false
    func setFailRefresh(_ value: Bool) { failRefresh = value }
    func setMismatch(_ value: Bool) { mismatch = value }
    func setHold(_ value: Bool) { holdRefresh = value }
    func setAccount(_ value: String) { account = value }
    func setFailConfirm(_ value: Bool) { failConfirm = value }
    func setFailLogout(_ value: Bool) { failLogout = value }
    func release() { waiter?.resume(); waiter = nil }
    func clearRequests() { requests = [] }
    private func date(_ value: Date) -> String { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.string(from: value) }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request)
        let path = request.url!.path
        if path.hasSuffix("/auth/logout"), failLogout { throw URLError(.notConnectedToInternet) }
        let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let now = Date()
        var data: [String: Any]
        if path.hasSuffix("/auth/refresh") || path.hasSuffix("/auth/token") {
            let refreshing = path.hasSuffix("/auth/refresh")
            if refreshing {
                refreshEntered = true
                if holdRefresh { await withCheckedContinuation { waiter = $0 } }
                if failRefresh { return HTTPResult(status: 503, data: Data("{\"error\":{\"code\":\"SERVICE_UNAVAILABLE\"}}".utf8)) }
            }
            let generation = (body["generation"] as? Int ?? -1) + 1
            data = ["accountId": mismatch ? "fixture-B" : account, "sessionId": "fixture-session-" + account, "tokenFamilyId": "fixture-family-" + account,
                    "generation": generation, "accessToken": String(repeating: "A", count: 43), "accessExpiresAt": date(now.addingTimeInterval(300)),
                    "refreshToken": String(repeating: "R", count: 43), "refreshExpiresAt": date(now.addingTimeInterval(86400)),
                    "absoluteExpiresAt": "2030-01-01T00:00:00Z"]
            if refreshing { data["refreshRequestId"] = body["refreshRequestId"]; data["previousGeneration"] = generation - 1; data["replayUntil"] = date(now.addingTimeInterval(120)) }
        } else if path.hasSuffix("/auth/reauth") { data = ["validUntil": date(now.addingTimeInterval(300))]
        } else if path.hasSuffix("/prepare") {
            deletionID = body["deletionRequestId"] as! String
            data = ["deletionRequestId": deletionID, "status": "prepared", "confirmAccepted": false, "scopeVersion": "station-account-v1", "prepareExpiresAt": date(prepareExpires), "receiptExpiresAt": date(receiptExpires)]
        } else if path.hasSuffix("/confirm") || path.hasSuffix("/status") {
            if path.hasSuffix("/confirm"), failConfirm { throw URLError(.networkConnectionLost) }
            data = ["deletionRequestId": deletionID, "status": "accepted", "confirmAccepted": true, "receiptExpiresAt": date(receiptExpires), "stage": "queued"]
        } else { data = ["accepted": true] }
        return HTTPResult(status: 200, data: try JSONSerialization.data(withJSONObject: ["data": data, "serverNow": date(now), "requestId": UUID().uuidString]))
    }
}
// Keep protocol conformance separate from actor declaration isolation inference.
// The mutable fixture state and send implementation remain actor-isolated.
extension AuthFixtureTransport: HTTPTransport {}
@MainActor final class NativeAuthenticationTests: XCTestCase {
    let origin = URL(string: "https://native.example.test")!
    func setup(store: any SecureStore = MemorySecureStore(), transport: AuthFixtureTransport = AuthFixtureTransport()) throws -> (NativeAuthenticationService, AuthJournal, NativeAuthAPI, AuthFixtureTransport) {
        let config = try NativeAuthConfiguration(environment: .development, origin: origin, explicitlyEnabled: true)
        let api = NativeAuthAPI(configuration: config, transport: transport), journal = AuthJournal(store: store, environment: .development)
        return (NativeAuthenticationService(configuration: config, api: api, journal: journal, browser: FixtureBrowser()), journal, api, transport)
    }
    func testConfigurationNeverEnablesMockOrProduction() throws {
        for env in [AppEnvironment.mock, .production] { XCTAssertThrowsError(try NativeAuthConfiguration(environment: env, origin: origin, explicitlyEnabled: true)) }
        XCTAssertThrowsError(try NativeAuthConfiguration(environment: .development, origin: origin, explicitlyEnabled: false))
        for value in ["https://user@example.test", "https://example.test/path", "https://example.test?q=a", "https://example.test#fragment"] { XCTAssertThrowsError(try NativeAuthConfiguration(environment: .staging, origin: URL(string: value)!, explicitlyEnabled: true)) }
    }
    func testPKCEEntropyS256AndExactCallback() throws {
        let config = try NativeAuthConfiguration(environment: .development, origin: origin, explicitlyEnabled: true)
        let flow = try PKCEFlow(), other = try PKCEFlow()
        XCTAssertEqual(flow.verifier.count, 43); XCTAssertNotEqual(flow.verifier, other.verifier); XCTAssertNotEqual(flow.state, other.state)
        let url = try flow.authorizationURL(config, locale: "en"); XCTAssertTrue(url.absoluteString.contains("code_challenge_method=S256"))
        let callback = config.callback.absoluteString + "?code=" + String(repeating: "C", count: 43) + "&state=" + flow.state
        XCTAssertEqual(try flow.code(from: URL(string: callback)!, configuration: config).count, 43)
        for invalid in [callback + "&state=" + flow.state, callback.replacingOccurrences(of: "native.example.test", with: "evil.example.test"), callback + "#fragment", callback.replacingOccurrences(of: flow.state, with: other.state)] {
            XCTAssertThrowsError(try flow.code(from: URL(string: invalid)!, configuration: config))
        }
    }
    func testLoginPersistsBeforePublishingAndLogoutRemovesOnlyAuth() async throws {
        let store = MemorySecureStore(); let (auth, journal, _, transport) = try setup(store: store)
        let deletion = DeletionJournal(store: store, environment: .development); _ = try await deletion.prepare(accountID: "fixture-A")
        try await auth.signIn(); let saved = try await journal.read(); XCTAssertEqual(saved?.scope.accountID, "fixture-A")
        let state = await auth.state(); XCTAssertEqual(state, .authenticated(AccountScope(environment: .development, accountID: "fixture-A")))
        try await auth.signOut(); let empty = try await journal.read(); XCTAssertNil(empty); let receipt = try await deletion.read(); XCTAssertNotNil(receipt)
        let requests = await transport.requests; XCTAssertTrue(requests.contains { $0.url?.path.hasSuffix("/auth/logout") == true })
    }
    func testStorageFailureDoesNotPublishCredentials() async throws {
        let store = MemorySecureStore(); let (auth, _, _, _) = try setup(store: store); await store.setFailure(true)
        do { try await auth.signIn(); XCTFail("Accepted unavailable Keychain") } catch {}
        let state = await auth.state(); XCTAssertNotEqual(state, .authenticated(AccountScope(environment: .development, accountID: "fixture-A")))
    }
    func testRefreshPendingSavedBeforeSendAndFixedAcrossServiceRelaunch() async throws {
        let store = MemorySecureStore(), transport = AuthFixtureTransport();let (auth, journal, _, _) = try setup(store: store, transport: transport)
        try await auth.signIn(); await transport.setFailRefresh(true)
        do { _ = try await auth.accessToken(forceRefresh: true); XCTFail("Expected 503") } catch {}
        let pending = try await journal.read();XCTAssertNotNil(pending?.pending)
        await transport.setFailRefresh(false)
        let (relaunch, _, _, _) = try setup(store: store, transport: transport);try await relaunch.restore()
        let requests = await transport.requests.filter { $0.url?.path.hasSuffix("/auth/refresh") == true }
        XCTAssertEqual(requests.count, 2);XCTAssertEqual(requests[0].httpBody, requests[1].httpBody)
        let completed = try await journal.read();XCTAssertNil(completed?.pending);XCTAssertEqual(completed?.generation, 1)
    }
    func testConcurrentRefreshIsSingleFlight() async throws {
        let (auth, _, _, transport) = try setup();try await auth.signIn();await transport.setHold(true)
        let first = Task { try await auth.accessToken(forceRefresh: true) }
        while !(await transport.refreshEntered) { await Task.yield() }
        let second = Task { try await auth.accessToken(forceRefresh: true) }
        while await auth.coalescedRefreshes == 0 { await Task.yield() }
        await transport.release();_ = try await first.value;_ = try await second.value
        let requests = await transport.requests.filter { $0.url?.path.hasSuffix("/auth/refresh") == true };XCTAssertEqual(requests.count, 1)
    }
    func testLogoutDuringRefreshRejectsLateSuccess() async throws {
        let (auth, journal, _, transport) = try setup();try await auth.signIn();await transport.setHold(true)
        let task = Task { try await auth.accessToken(forceRefresh: true) }
        while !(await transport.refreshEntered) { await Task.yield() }
        try await auth.signOut();await transport.release()
        do { _ = try await task.value;XCTFail("Late success accepted") } catch {}
        let saved = try await journal.read();XCTAssertNil(saved);let state = await auth.state();XCTAssertEqual(state, .guest)
    }
    func testMismatchedRefreshCannotOverwriteAccount() async throws {
        let (auth, journal, _, transport) = try setup();try await auth.signIn();await transport.setMismatch(true)
        do { _ = try await auth.accessToken(forceRefresh: true);XCTFail("Cross-account response accepted") } catch {}
        let saved = try await journal.read();XCTAssertEqual(saved?.scope.accountID, "fixture-A");XCTAssertEqual(saved?.generation, 0)
    }
    func testOldContextCannotSignOutNewAccount() async throws {
        let (auth, _, _, transport) = try setup();try await auth.signIn();let old = try await auth.requestContext()
        await transport.setAccount("fixture-B");try await auth.signIn();try await auth.signOut(ifCurrent: old)
        let state = await auth.state();XCTAssertEqual(state, .authenticated(AccountScope(environment: .development, accountID: "fixture-B")))
    }
    func testDeletionResponseLossKeepsReceiptAndRelaunchOnlyQueries() async throws {
        let store = MemorySecureStore();let (auth, _, api, transport) = try setup(store: store);try await auth.signIn()
        let journal = DeletionJournal(store: store, environment: .development), deletion = NativeDeletionService(journal: DeletionJournal(store: store, environment: .development), auth: auth, api: api)
        _ = try await deletion.prepare();await transport.setFailConfirm(true)
        do { _ = try await deletion.explicitlyConfirm();XCTFail("Expected loss") } catch {}
        let record = try await journal.read();XCTAssertTrue(record?.confirmAttempted == true)
        await transport.clearRequests()
        let recovered = NativeDeletionService(journal: journal, auth: auth, api: api);let status = try await recovered.queryRecovery();XCTAssertTrue(status?.confirmAccepted == true)
        let requests = await transport.requests;XCTAssertEqual(requests.count, 1);XCTAssertEqual(requests[0].httpMethod, "GET");XCTAssertTrue(requests[0].value(forHTTPHeaderField: "Authorization")!.hasPrefix("DeletionReceipt "))
    }
    func testDeletionStorageFailureCannotSendConfirmation() async throws {
        let store = MemorySecureStore();let (auth, _, api, transport) = try setup(store: store);try await auth.signIn()
        let deletion = NativeDeletionService(journal: DeletionJournal(store: store, environment: .development), auth: auth, api: api)
        _ = try await deletion.prepare();await store.setFailure(true)
        do { _ = try await deletion.explicitlyConfirm();XCTFail("Confirmed without durable receipt") } catch {}
        let requests = await transport.requests;XCTAssertFalse(requests.contains { $0.url?.path.hasSuffix("/confirm") == true })
    }
    func testOldAccountDeletionJournalCannotBeReusedByAnotherAccount() async throws {
        let journal = DeletionJournal(store: MemorySecureStore(), environment: .development);_ = try await journal.prepare(accountID: "A")
        do { _ = try await journal.prepare(accountID: "B");XCTFail("Receipt reused across accounts") } catch {}
    }
    func testPendingStorageFailureSendsNoRefresh() async throws {
        let store = MemorySecureStore(); let (auth, _, _, transport) = try setup(store: store)
        try await auth.signIn(); await transport.clearRequests(); await store.setFailure(true)
        do { _ = try await auth.accessToken(forceRefresh: true); XCTFail("Refresh started without pending persistence") } catch {}
        let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testResultStorageFailureKeepsOldPendingAndNeverPublishes() async throws {
        let store = MemorySecureStore(); let (auth, journal, _, transport) = try setup(store: store)
        try await auth.signIn(); await transport.setHold(true)
        let task = Task { try await auth.accessToken(forceRefresh: true) }
        while !(await transport.refreshEntered) { await Task.yield() }
        await store.setFailure(true); await transport.release()
        do { _ = try await task.value; XCTFail("New token published before persistence") } catch {}
        let record = try await journal.read(); XCTAssertEqual(record?.generation, 0); XCTAssertNotNil(record?.pending)
        let state = await auth.state(); XCTAssertEqual(state, .unavailable)
    }
    func testOfflineLogoutReportsUnconfirmedButLocalCredentialIsRemoved() async throws {
        let (auth, journal, _, transport) = try setup(); try await auth.signIn(); await transport.setFailLogout(true)
        do { try await auth.signOut(); XCTFail("Server logout falsely confirmed") }
        catch { XCTAssertEqual((error as? NativeFailure)?.code, "LOGOUT_UNCONFIRMED") }
        let record = try await journal.read(); XCTAssertNil(record)
        let state = await auth.state(); XCTAssertEqual(state, .guest)
    }
}
