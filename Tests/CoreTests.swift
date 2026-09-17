import XCTest
@testable import StationCatMusic

@MainActor final class CoreTests: XCTestCase {
    func envelope() -> CredentialEnvelope {
        CredentialEnvelope(schemaVersion: 1, scope: AccountScope(environment: .mock, accountID: "fixture-A"), sessionID: "fixture-session",
                           familyID: "fixture-family", generation: 4, refreshToken: "FIXTURE_ONLY", pending: nil, refreshExpiresAt: Date(timeIntervalSince1970: 200), absoluteExpiresAt: Date(timeIntervalSince1970: 300))
    }
    func track(_ access: AccessPolicy = .free) -> Track {
        Track(id: "fixture-song", title: "Sample", artist: "Fixture", durationSeconds: 180, audioVersion: 3, access: access)
    }
    func data() throws -> Data { try Data(contentsOf: XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "json"))) }
    func rejected(_ expected: APIError, _ action: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await action(); XCTFail("Expected rejection", file: file, line: line) }
        catch { XCTAssertEqual(error as? APIError, expected, file: file, line: line) }
    }
    func testCapabilitiesAndEntitlementKindsFailClosed() throws {
        let flags = try JSONDecoder().decode(NativeCapabilities.self, from: Data("{\"musicPlayback\":\"yes\",\"futureVIP\":true}".utf8))
        XCTAssertFalse(flags.musicPlayback); XCTAssertFalse(flags.nativeAuthentication); XCTAssertFalse(flags.accountDeletion)
        XCTAssertThrowsError(try JSONDecoder().decode(MusicEntitlementKind.self, from: Data("\"unrecognized\"".utf8)))
    }
    func testProtectedStorageFailurePreservesExistingRecord() async throws {
        let store = UnavailableReadStore()
        let journal = AuthJournal(store: store, environment: .mock)
        do { _ = try await journal.read(); XCTFail("Unavailable storage accepted") }
        catch { XCTAssertEqual(error as? SecureStoreError, .protectedDataUnavailable) }
        let removals = await store.removals; XCTAssertEqual(removals, 0)
    }
    func testPlaybackWireFixtureDecodesAndValidates() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "schema-examples", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let bytes = try JSONSerialization.data(withJSONObject: XCTUnwrap(fixture["PlaybackGrantResponse"]))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(APIEnvelope<PlaybackGrant>.self, from: bytes)
        let track = Track(id: "fixture-only", title: "Sample", artist: "Fixture", durationSeconds: 1, audioVersion: 1, access: .free)
        try response.data.validate(serverNow: XCTUnwrap(ISO8601DateFormatter().date(from: response.serverNow)), scope: .guest, session: nil, track: track, allowedHosts: ["mock.invalid"])
    }
    func testBuiltAppIsExplicitlyMockWithoutHTTPExceptions() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "StationEnvironment") as? String, "mock")
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity"))
    }
    func testUnknownPolicyFailsClosed() throws {
        XCTAssertEqual(try JSONDecoder().decode(AccessPolicy.self, from: Data("\"future_policy\"".utf8)), .unavailable)
        XCTAssertThrowsError(try JSONDecoder().decode(GrantAuthMode.self, from: Data("\"future_auth\"".utf8)))
    }
    func testDefaultRemoteEnvironmentsClosed() async throws {
        let transport = MockTransport(data: try data())
        for environment in [AppEnvironment.development, .staging, .production] {
            let api = APIClient(environment: environment, transport: transport)
            await rejected(.networkDisabled) { _ = try await api.catalog() }
            await rejected(.networkDisabled) { try await api.mutate() }
        }
        let count = await transport.requestCount; XCTAssertEqual(count, 0)
    }
    func testCatalogDecodesAndMutationClosed() async throws {
        let client = APIClient(environment: .mock, transport: MockTransport(data: try data()))
        let catalog = try await client.catalog(); XCTAssertEqual(catalog.items.count, 3)
        await rejected(.networkDisabled) { try await client.mutate() }
    }
    func test503IsUnavailableNotExpiredMembership() async throws {
        let client = APIClient(environment: .mock, transport: MockTransport(data: Data(), status: 503))
        await rejected(.unavailable) { _ = try await client.catalog() }
    }
    func testMalformedCatalogRejected() async {
        let client = APIClient(environment: .mock, transport: MockTransport(data: Data("{}".utf8)))
        await rejected(.invalidPayload) { _ = try await client.catalog() }
    }
    func testRequestCancellation() async throws {
        let client = APIClient(environment: .mock, transport: MockTransport(data: try data(), delay: .seconds(2)))
        let work = Task { try await client.catalog() }; work.cancel()
        do { _ = try await work.value; XCTFail("Cancelled request returned data") } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testScopeCachesNeverImplicitlyMerge() async {
        let library = ScopedLibrary(); let a = envelope().scope
        let b = AccountScope(environment: .mock, accountID: "fixture-B")
        await library.setFavorite("song", value: true, scope: .guest)
        let emptyA = await library.favorites(in: a); XCTAssertTrue(emptyA.isEmpty)
        await library.setFavorite("private", value: true, scope: a)
        await library.clear(scope: a)
        let emptyB = await library.favorites(in: b); XCTAssertTrue(emptyB.isEmpty)
        let guest = await library.favorites(in: .guest); XCTAssertEqual(guest, ["song"])
    }
    func testLateCatalogCannotOverwriteNewAccount() async throws {
        let model = AppModel(client: APIClient(environment: .mock, transport: MockTransport(data: try data(), delay: .milliseconds(100))))
        let work = Task { await model.load() }
        await Task.yield()
        await model.changeScope(envelope().scope)
        await work.value
        XCTAssertTrue(model.tracks.isEmpty); XCTAssertEqual(model.scope, envelope().scope)
    }
    func testPlayerOwnershipAcrossNavigation() throws {
        let model = AppModel(client: APIClient(environment: .mock, transport: MockTransport(data: try data())))
        let identity = model.playback.identity
        for tab in 0...2 { model.selectedTab = tab; model.select(track()); model.showPlayer = false }
        XCTAssertEqual(identity, model.playback.identity); XCTAssertFalse(model.playback.isPlaying); XCTAssertFalse(model.playback.hasAudioSource)
    }
    func testLocaleCoverageAndFallback() {
        XCTAssertEqual(Set(L10n.all.keys), Set(["en", "ja", "zh-Hans", "zh-Hant"]))
        for values in L10n.all.values { XCTAssertEqual(Set(values.keys), Set(L10n.all["en"]!.keys)); XCTAssertFalse(values.values.contains("")) }
        XCTAssertEqual(L10n.resolve("zh-TW"), "zh-Hant"); XCTAssertEqual(L10n.resolve("ja-JP"), "ja"); XCTAssertEqual(L10n.resolve("fr"), "en")
    }
    func testPendingRefreshSurvivesNewJournalWithSameID() async throws {
        let store = MemorySecureStore(); let journal = AuthJournal(store: store, environment: .mock)
        try await journal.install(envelope()); let first = try await journal.prepare(digest: "fixture-digest")
        let relaunched = AuthJournal(store: store, environment: .mock)
        let retry = try await relaunched.prepare(digest: "fixture-digest")
        XCTAssertEqual(first, retry); XCTAssertEqual(retry.refreshToken, "FIXTURE_ONLY")
        await rejected(.staleResponse) { _ = try await relaunched.prepare(digest: "changed-body") }
    }
    func testFailedPendingWriteCannotAuthorizeSend() async throws {
        let store = MemorySecureStore(); let journal = AuthJournal(store: store, environment: .mock)
        try await journal.install(envelope()); await store.setFailure(true)
        await rejected(.storageUnavailable) { _ = try await journal.prepare(digest: "digest") }
        let saved = try await journal.read(); XCTAssertNil(saved?.pending)
    }
    func testRotationAtomicWriteFailureRetainsOldEnvelope() async throws {
        let store = MemorySecureStore(); let journal = AuthJournal(store: store, environment: .mock)
        try await journal.install(envelope()); let pending = try await journal.prepare(digest: "digest")
        var replacement = pending; replacement.generation += 1; replacement.refreshToken = "FIXTURE_NEW"; replacement.pending = nil
        await store.setFailure(true)
        await rejected(.storageUnavailable) { try await journal.complete(expected: pending, replacement: replacement) }
        let saved = try await journal.read(); XCTAssertEqual(saved, pending)
    }
    func testSuccessfulRotationAndStaleReplayRejected() async throws {
        let store = MemorySecureStore(); let journal = AuthJournal(store: store, environment: .mock)
        try await journal.install(envelope()); let pending = try await journal.prepare(digest: "digest")
        var replacement = pending; replacement.generation += 1; replacement.refreshToken = "FIXTURE_NEW"; replacement.pending = nil
        try await journal.complete(expected: pending, replacement: replacement)
        let saved = try await journal.read(); XCTAssertEqual(saved, replacement)
        await rejected(.staleResponse) { try await journal.complete(expected: pending, replacement: replacement) }
    }
    func testCrossAccountRotationRejected() async throws {
        let journal = AuthJournal(store: MemorySecureStore(), environment: .mock)
        try await journal.install(envelope()); let pending = try await journal.prepare(digest: "digest")
        let other = CredentialEnvelope(schemaVersion: 1, scope: AccountScope(environment: .mock, accountID: "B"), sessionID: pending.sessionID, familyID: pending.familyID, generation: 5, refreshToken: "FIXTURE_NEW", pending: nil, refreshExpiresAt: Date(timeIntervalSince1970: 200), absoluteExpiresAt: Date(timeIntervalSince1970: 300))
        await rejected(.staleResponse) { try await journal.complete(expected: pending, replacement: other) }
    }
    func testLogoutWinsAgainstSuspendedRotation() async throws {
        let store = SuspendedStore(); let journal = AuthJournal(store: store, environment: .mock)
        try await journal.install(envelope()); let pending = try await journal.prepare(digest: "digest")
        var replacement = pending; replacement.generation += 1; replacement.pending = nil
        await store.suspendNextWrite()
        let rotate = Task { try await journal.complete(expected: pending, replacement: replacement) }
        await store.waitUntilSuspended()
        let logout = Task { try await journal.logout() }
        while await journal.epoch == 0 { await Task.yield() }
        await store.resumeWrite()
        do { try await rotate.value; XCTFail("Stale rotation published success") } catch { XCTAssertEqual(error as? APIError, .staleResponse) }
        try await logout.value
        let saved = try await journal.read(); XCTAssertNil(saved)
    }
    func testReceiptEncodingHashesDecodedBytes() throws {
        let data = Data((0..<32).map(UInt8.init))
        XCTAssertEqual(try DeletionReceipt.encode(data), "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8")
        XCTAssertEqual(try DeletionReceipt.hash(data), "630dcd2966c4336691125448bbb25b4ff412a49c732db2c8abc1b8581bd710dd")
        XCTAssertThrowsError(try DeletionReceipt.encode(Data(repeating: 0, count: 31)))
        XCTAssertNotEqual(try DeletionReceipt.generate(), try DeletionReceipt.generate())
    }
    func testDeletionPersistFailureStopsPrepare() async throws {
        let store = MemorySecureStore(); await store.setFailure(true)
        let journal = DeletionJournal(store: store, environment: .mock)
        await rejected(.storageUnavailable) { _ = try await journal.prepare() }
        let action = try await journal.recoveryAction(); XCTAssertEqual(action, .none)
    }
    func testDeletionCannotConfirmBeforeKnownDeadlines() async throws {
        let journal = DeletionJournal(store: MemorySecureStore(), environment: .mock)
        _ = try await journal.prepare()
        await rejected(.invalidRequest) { _ = try await journal.explicitlyConfirm(scopeVersion: "station-account-v1", now: Date()) }
    }
    func testDeletionConfirmationPersistsAndRestartOnlyQueries() async throws {
        let store = MemorySecureStore(); let journal = DeletionJournal(store: store, environment: .mock)
        let record = try await journal.prepare(); let now = Date()
        try await journal.recordPrepared(id: record.deletionRequestID, scopeVersion: record.scopeVersion, prepareUntil: now.addingTimeInterval(600), receiptUntil: now.addingTimeInterval(1209600))
        let confirmed = try await journal.explicitlyConfirm(scopeVersion: record.scopeVersion, now: now)
        XCTAssertTrue(confirmed.confirmAttempted); XCTAssertNotNil(confirmed.confirmRequestID)
        let relaunched = DeletionJournal(store: store, environment: .mock)
        let action = try await relaunched.recoveryAction(); XCTAssertEqual(action, .queryStatus(record.deletionRequestID))
        await rejected(.invalidRequest) { _ = try await relaunched.explicitlyConfirm(scopeVersion: record.scopeVersion, now: now) }
        let auth = AuthJournal(store: store, environment: .mock); try await auth.install(envelope()); try await auth.logout()
        let recovered = try await relaunched.read(); XCTAssertEqual(recovered, confirmed)
    }
    func testExpiredDeletionPrepareRejected() async throws {
        let journal = DeletionJournal(store: MemorySecureStore(), environment: .mock); let r = try await journal.prepare(); let now = Date()
        try await journal.recordPrepared(id: r.deletionRequestID, scopeVersion: r.scopeVersion, prepareUntil: now, receiptUntil: now.addingTimeInterval(100))
        await rejected(.invalidRequest) { _ = try await journal.explicitlyConfirm(scopeVersion: r.scopeVersion, now: now) }
    }
    func testRealKeychainSingleItemAcrossInstancesAndReplacement() async throws {
        let service = "org.stationcat.music.dev.tests.\(UUID().uuidString)"
        let first = KeychainStore(service: service)
        try await first.write(Data("fixture-old".utf8), key: "auth.mock")
        let reopened = KeychainStore(service: service)
        let old = try await reopened.read("auth.mock"); XCTAssertEqual(old, Data("fixture-old".utf8))
        try await reopened.write(Data("fixture-new".utf8), key: "auth.mock")
        let updated = try await first.read("auth.mock"); XCTAssertEqual(updated, Data("fixture-new".utf8))
        try await first.remove("auth.mock"); let missing = try await reopened.read("auth.mock"); XCTAssertNil(missing)
    }
    func testContinuousDeadlineConservativelySubtractsRTT() throws {
        var boundary = PlaybackBoundary()
        try boundary.install(serverNow: 1000, validUntil: 1060, sent: 10, received: 15, sequence: 0)
        XCTAssertEqual(boundary.deadline, 68); XCTAssertFalse(boundary.expire(at: 67)); XCTAssertTrue(boundary.expire(at: 68))
        XCTAssertTrue(boundary.requiresExplicitResume)
        XCTAssertThrowsError(try boundary.install(serverNow: 1000, validUntil: 2000, sent: 10, received: 15, sequence: 0))
    }
    func testInvalidAndExhaustedDeadlineRejected() {
        var boundary = PlaybackBoundary()
        XCTAssertThrowsError(try boundary.install(serverNow: .nan, validUntil: 200, sent: 0, received: 1, sequence: 0))
        XCTAssertThrowsError(try boundary.install(serverNow: 100, validUntil: 103, sent: 0, received: 2, sequence: 0))
        XCTAssertThrowsError(try boundary.install(serverNow: 100, validUntil: 200, sent: 2, received: 1, sequence: 0))
    }
    func testDeadlineHardStopAndTrackChangeInvalidateOldGrant() throws {
        let clock = FakeClock(); let loader = SpyLoader(); let service = PlaybackService(clock: clock, loader: loader)
        service.select(track()); let sequence = service.boundary.sequence
        try service.installBoundary(serverNow: 1000, validUntil: 1060, sent: 0, received: 0, sequence: sequence)
        clock.now = 60; service.checkDeadline()
        XCTAssertEqual(service.state, .verificationRequired); XCTAssertNil(service.boundary.deadline)
        XCTAssertFalse(service.hasAudioSource); XCTAssertFalse(service.autoAdvance); XCTAssertGreaterThan(loader.cancellations, 0)
        service.select(track()); XCTAssertThrowsError(try service.installBoundary(serverNow: 1000, validUntil: 2000, sent: 60, received: 60, sequence: sequence))
    }
    func testGrantIdentityAndURLBinding() throws {
        func grant(_ mode: GrantAuthMode = .sessionBearer, account: String? = "fixture-A", url: String = "https://music.example/api/mobile/v1/music/media/fffffffffffffffffffffffffffffffffffffffffff/audio", version: Int = 3) -> PlaybackGrant {
            PlaybackGrant(playbackUrl: URL(string: url)!, expiresAt: Date(timeIntervalSince1970: 200), playbackValidUntil: Date(timeIntervalSince1970: 200), revalidateAt: Date(timeIntervalSince1970: 150), durationSeconds: 180, previewSourceStartSeconds: nil, authMode: mode, accountID: account, sessionID: mode == .sessionBearer ? "fixture-session" : nil, trackID: "fixture-song", audioVersion: version, variant: "full")
        }
        try grant().validate(serverNow: Date(timeIntervalSince1970: 100), scope: envelope().scope, session: "fixture-session", track: track(.vip), allowedHosts: ["music.example"])
        for bad in [grant(account: "B"), grant(url: "http://music.example/api/mobile/v1/music/media/fffffffffffffffffffffffffffffffffffffffffff/audio"), grant(url: "https://music.example/api/mobile/v1/music/media/fffffffffffffffffffffffffffffffffffffffffff/audio?token=fixture"), grant(version: 2), grant(.publicAccess, account: nil)] {
            XCTAssertThrowsError(try bad.validate(serverNow: Date(timeIntervalSince1970: 100), scope: envelope().scope, session: "fixture-session", track: track(.vip), allowedHosts: ["music.example"]))
        }
    }
}
@MainActor private final class FakeClock: PlaybackClock { var now: Double = 0 }
@MainActor private final class SpyLoader: MediaLoading { var cancellations = 0; func cancelAll() { cancellations += 1 } }
private actor SuspendedStore: SecureStore {
    private var data: [String: Data] = [:]
    private var shouldSuspend = false
    private var suspended: CheckedContinuation<Void, Never>?
    private var notification: CheckedContinuation<Void, Never>?
    func suspendNextWrite() { shouldSuspend = true }
    func waitUntilSuspended() async { if suspended == nil { await withCheckedContinuation { notification = $0 } } }
    func resumeWrite() { suspended?.resume(); suspended = nil }
    func read(_ key: String) -> Data? { data[key] }
    func remove(_ key: String) { data.removeValue(forKey: key) }
    func write(_ value: Data, key: String) async {
        if shouldSuspend {
            shouldSuspend = false
            await withCheckedContinuation { c in suspended = c; notification?.resume(); notification = nil }
        }
        data[key] = value
    }
}

private actor UnavailableReadStore: SecureStore {
    private(set) var removals = 0
    func read(_ key: String) throws -> Data? { throw SecureStoreError.protectedDataUnavailable }
    func write(_ data: Data, key: String) throws { throw SecureStoreError.protectedDataUnavailable }
    func remove(_ key: String) { removals += 1 }
}
