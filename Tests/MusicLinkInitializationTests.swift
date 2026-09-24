import XCTest
@testable import StationCatMusic

private actor StartupMusicTransport: HTTPTransport {
    static let first = Track(id: "10000000-0000-4000-8000-000000000001", title: "First", artist: "Synthetic", durationSeconds: 180, audioVersion: 1, access: .free)
    static let second = Track(id: "10000000-0000-4000-8000-000000000002", title: "Second", artist: "Synthetic", durationSeconds: 180, audioVersion: 1, access: .free)
    private(set) var paths: [String] = []
    private(set) var catalogLocales: [String] = []
    private(set) var catalogEntered = false
    private(set) var detailEntered = false
    private(set) var featuredEntered = false
    private var holdFeatured: Bool
    private var featuredWaiters: [CheckedContinuation<Void, Never>] = []
    private var catalogStatus: Int
    private var featuredStatus: Int
    private var holdCatalog: Bool
    private var holdDetail = false
    private var catalogWaiters: [CheckedContinuation<Void, Never>] = []
    private var detailWaiters: [CheckedContinuation<Void, Never>] = []
    init(holdCatalog: Bool = true, holdFeatured: Bool = false, catalogStatus: Int = 200, featuredStatus: Int = 200) {
        self.holdCatalog = holdCatalog; self.holdFeatured = holdFeatured
        self.catalogStatus = catalogStatus; self.featuredStatus = featuredStatus
    }
    func succeed() { catalogStatus = 200; featuredStatus = 200 }
    func bothEntered() -> Bool { featuredEntered && catalogEntered }
    func releaseFeatured() { holdFeatured = false; let waiting = featuredWaiters; featuredWaiters = []; waiting.forEach { $0.resume() } }
    func releaseCatalog() { holdCatalog = false; let waiting = catalogWaiters; catalogWaiters = []; waiting.forEach { $0.resume() } }
    func suspendDetail() { holdDetail = true }
    func releaseDetail() { holdDetail = false; let waiting = detailWaiters; detailWaiters = []; waiting.forEach { $0.resume() } }
    func releaseAll() { releaseCatalog(); releaseDetail(); releaseFeatured() }
    private func result<T: Codable & Sendable>(_ data: T) throws -> HTTPResult {
        HTTPResult(status: 200, data: try JSONEncoder().encode(APIEnvelope(data: data, requestId: UUID().uuidString, serverNow: ISO8601DateFormatter().string(from: Date()))))
    }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        guard let path = request.url?.path else { throw APIError.invalidRequest }
        paths.append(path)
        guard request.httpMethod == "GET" else { throw APIError.invalidRequest }
        if path.hasSuffix("/music/catalog") {
            catalogEntered = true
            catalogLocales.append(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "locale" })?.value ?? "")
            if holdCatalog { await withCheckedContinuation { catalogWaiters.append($0) } }
            if catalogStatus != 200 { return HTTPResult(status: catalogStatus, data: Data()) }
            return try result(Catalog(items: [Self.first, Self.second], nextCursor: nil))
        }
        if path.hasSuffix("/music/featured") {
            featuredEntered = true
            if holdFeatured { await withCheckedContinuation { featuredWaiters.append($0) } }
            if featuredStatus != 200 { return HTTPResult(status: featuredStatus, data: Data()) }
            return try result(FeaturedMusic(tracks: [Self.first], collections: []))
        }
        if path.contains("/music/collections/") {
            return try result(MusicCollection(id: "20000000-0000-4000-8000-000000000001", slug: "synthetic-album", title: "Synthetic album", description: "Test only", version: 1, tracks: [Self.second, Self.first], nextCursor: nil))
        }
        guard let track = [Self.first, Self.second].first(where: { path.hasSuffix("/music/tracks/" + $0.id) }) else { throw APIError.invalidRequest }
        detailEntered = true
        if holdDetail { await withCheckedContinuation { detailWaiters.append($0) } }
        return try result(TrackDetail(track: track, summary: "Test only", coverUrl: nil, lyrics: MusicLyrics(kind: "plain", text: track.title, lines: [], audioVersion: 1), genres: [], moods: [], previewAvailable: false, previewSourceStartSeconds: nil, previewDurationSeconds: nil))
    }
}

@MainActor final class MusicLinkInitializationTests: XCTestCase {
    private let origin = URL(string: "https://startup.native.example.test")!
    private enum Failure: Error { case checkpoint }
    private func configuration() throws -> NativeAuthConfiguration {
        try NativeAuthConfiguration(environment: .development, origin: origin, explicitlyEnabled: true)
    }
    private func model(_ transport: StartupMusicTransport, account: NativeAccountModel = NativeAccountModel()) throws -> AppModel {
        let native = try NativeMusicAPI(configuration: configuration(), explicitlyEnabled: true, transport: transport)
        return AppModel(client: native, account: account, musicWebOrigin: origin, environment: .development)
    }
    private func link(_ track: Track) -> URL { URL(string: origin.absoluteString + "/music/?track=" + track.id)! }
    private func until(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { throw Failure.checkpoint }
            await Task.yield()
        }
    }
    private func assertNotPlaying(_ model: AppModel, paths: [String], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(model.playback.isPlaying, file: file, line: line)
        XCTAssertFalse(model.playback.hasAudioSource, file: file, line: line)
        XCTAssertTrue([PlaybackService.State.idle, .selected].contains(model.playback.state), file: file, line: line)
        XCTAssertEqual(model.playback.position, 0, file: file, line: line)
        XCTAssertFalse(paths.contains { $0.contains("/playback-grants") || $0.contains("/music/media/") }, file: file, line: line)
    }
    func testStartupShowcaseWaitsForInitializationAndNeverReturnsOnReload() async throws {
        let transport = StartupMusicTransport(holdCatalog: true, holdFeatured: true), model = try model(transport)
        defer { model.playback.shutdown(); Task { await transport.releaseAll() } }
        XCTAssertEqual(model.startupPhase, .loading)
        let startup = Task { await model.initialize() }
        try await until { await transport.bothEntered() }
        XCTAssertEqual(model.startupPhase, .loading)
        await transport.releaseAll(); await startup.value
        XCTAssertEqual(model.startupPhase, .ready)
        await model.load()
        XCTAssertEqual(model.startupPhase, .ready)
        assertNotPlaying(model, paths: await transport.paths)
    }
    func testStartupFailureRetryAndContinueAreExplicit() async throws {
        let transport = StartupMusicTransport(holdCatalog: false, catalogStatus: 503, featuredStatus: 503), model = try model(transport)
        defer { model.playback.shutdown() }
        model.continueAfterStartupFailure()
        XCTAssertEqual(model.startupPhase, .loading, "Cannot bypass an in-flight account restoration")
        await model.initialize()
        XCTAssertEqual(model.startupPhase, .unavailable)
        XCTAssertEqual(model.startupFailureKey, "startupFailure.service")
        await transport.succeed()
        await model.retryStartup()
        XCTAssertEqual(model.startupPhase, .ready)
        XCTAssertNil(model.catalogFailure)
        XCTAssertNil(model.featuredFailure)
        let paths = await transport.paths
        XCTAssertEqual(paths.filter { $0.hasSuffix("/music/catalog") }.count, 2)
        XCTAssertEqual(paths.filter { $0.hasSuffix("/music/featured") }.count, 2)
        assertNotPlaying(model, paths: paths)
        let failed = try self.model(StartupMusicTransport(holdCatalog: false, catalogStatus: 503, featuredStatus: 503))
        defer { failed.playback.shutdown() }
        await failed.initialize(); failed.continueAfterStartupFailure()
        XCTAssertEqual(failed.startupPhase, .ready)
        XCTAssertEqual(failed.phase, .unavailable)
    }
    func testResolvedColdLinkCanEnterDespiteFailedCatalog() async throws {
        let transport = StartupMusicTransport(holdCatalog: false, catalogStatus: 503, featuredStatus: 503), model = try model(transport)
        defer { model.playback.shutdown() }
        await model.receiveMusicLink(link(StartupMusicTransport.first)); await model.initialize()
        XCTAssertEqual(model.startupPhase, .ready)
        XCTAssertEqual(model.playback.selectedTrack?.id, StartupMusicTransport.first.id)
        assertNotPlaying(model, paths: await transport.paths)
    }
    func testDiscoveryPublishesWhileCatalogIsStillWaiting() async throws {
        let transport = StartupMusicTransport(), model = try model(transport)
        defer { model.playback.shutdown(); Task { await transport.releaseAll() } }
        let startup = Task { await model.initialize() }
        try await until { model.discoveryPhase == .loaded }
        XCTAssertEqual(model.discoveryTracks.map(\.id), [StartupMusicTransport.first.id])
        XCTAssertEqual(model.phase, .loading)
        let paths = await transport.paths
        XCTAssertTrue(paths.contains { $0.hasSuffix("/music/catalog") })
        assertNotPlaying(model, paths: paths)
        await transport.releaseAll(); await startup.value
        XCTAssertEqual(model.phase, .loaded)
    }
    func testCatalogPublishesWhileDiscoveryIsStillWaiting() async throws {
        let transport = StartupMusicTransport(holdCatalog: false, holdFeatured: true), model = try model(transport)
        defer { model.playback.shutdown(); Task { await transport.releaseAll() } }
        let startup = Task { await model.initialize() }
        try await until { model.phase == .loaded }
        XCTAssertEqual(model.discoveryPhase, .loading)
        XCTAssertEqual(model.tracks.count, 2)
        await transport.releaseAll(); await startup.value
        XCTAssertEqual(model.discoveryPhase, .loaded)
    }
    func testFailedSectionDoesNotDiscardOtherSection() async throws {
        for catalogFails in [true, false] {
            let transport = StartupMusicTransport(holdCatalog: false, catalogStatus: catalogFails ? 503 : 200, featuredStatus: catalogFails ? 200 : 503)
            let model = try model(transport)
            defer { model.playback.shutdown() }
            await model.initialize()
            XCTAssertEqual(model.startupPhase, .ready, "One successful section must allow entry")
            XCTAssertEqual(model.phase, catalogFails ? .unavailable : .loaded)
            XCTAssertEqual(model.discoveryPhase, catalogFails ? .loaded : .unavailable)
            XCTAssertEqual(model.featuredTracks.count, catalogFails ? 1 : 0)
            assertNotPlaying(model, paths: await transport.paths)
        }
    }
    func testCancelledLoadCannotPublishEitherLateSection() async throws {
        let transport = StartupMusicTransport(holdCatalog: true, holdFeatured: true), model = try model(transport)
        defer { model.playback.shutdown(); Task { await transport.releaseAll() } }
        let loading = Task { await model.load() }
        try await until { await transport.bothEntered() }
        loading.cancel(); await transport.releaseAll(); await loading.value
        XCTAssertTrue(model.tracks.isEmpty); XCTAssertTrue(model.featuredTracks.isEmpty)
        XCTAssertEqual(model.phase, .loading); XCTAssertEqual(model.discoveryPhase, .loading)
    }
    func testScopeChangeRejectsBothLateSections() async throws {
        let transport = StartupMusicTransport(holdCatalog: true, holdFeatured: true), model = try model(transport)
        defer { model.playback.shutdown(); Task { await transport.releaseAll() } }
        let loading = Task { await model.load() }
        try await until { await transport.bothEntered() }
        await model.changeScope(AccountScope(environment: .development, accountID: "new-account"))
        await transport.releaseAll(); await loading.value
        XCTAssertTrue(model.tracks.isEmpty); XCTAssertTrue(model.featuredTracks.isEmpty)
        XCTAssertTrue(model.collections.isEmpty)
        assertNotPlaying(model, paths: await transport.paths)
    }
    func testOneColdLaunchLinkWaitsForInitializationWithoutRedelivery() async throws {
        let transport = StartupMusicTransport(), model = try model(transport)
        defer { model.playback.shutdown(); Task { await transport.releaseAll() } }
        // One OS delivery before RootView.task starts. No second URL is sent.
        await model.receiveMusicLink(link(StartupMusicTransport.first))
        let before = await transport.paths; XCTAssertTrue(before.isEmpty)
        let startup = Task { await model.initialize() }
        try await until { await transport.catalogEntered }
        XCTAssertNil(model.playback.selectedTrack)
        await transport.releaseCatalog(); await startup.value
        XCTAssertEqual(model.playback.selectedTrack?.id, StartupMusicTransport.first.id)
        XCTAssertEqual(model.detail?.track.id, StartupMusicTransport.first.id)
        let paths = await transport.paths
        XCTAssertEqual(paths.filter { $0.hasSuffix("/music/tracks/" + StartupMusicTransport.first.id) }.count, 1)
        assertNotPlaying(model, paths: paths)
    }
    func testOnlyLatestValidLinkSurvivesLoadingAndInvalidHostCannotReplaceIt() async throws {
        let transport = StartupMusicTransport(), model = try model(transport)
        defer { model.playback.shutdown(); Task { await transport.releaseAll() } }
        let startup = Task { await model.initialize() }
        try await until { await transport.catalogEntered }
        await model.receiveMusicLink(link(StartupMusicTransport.first))
        await model.receiveMusicLink(link(StartupMusicTransport.second))
        await model.receiveMusicLink(URL(string: "https://wrong.example.test/music/?track=" + StartupMusicTransport.first.id)!)
        await transport.releaseCatalog(); await startup.value
        XCTAssertEqual(model.playback.selectedTrack?.id, StartupMusicTransport.second.id)
        let paths = await transport.paths
        XCTAssertFalse(paths.contains { $0.hasSuffix("/music/tracks/" + StartupMusicTransport.first.id) })
        XCTAssertEqual(paths.filter { $0.hasSuffix("/music/tracks/" + StartupMusicTransport.second.id) }.count, 1)
        assertNotPlaying(model, paths: paths)
    }
    func testRestoredAccountAndDelayedScopeNotificationDoNotClearColdLink() async throws {
        let authTransport = AuthFixtureTransport(), journal = AuthJournal(store: MemorySecureStore(), environment: .development)
        try await journal.install(CredentialEnvelope(schemaVersion: 1, scope: AccountScope(environment: .development, accountID: "fixture-A"), sessionID: "fixture-session-fixture-A", familyID: "fixture-family-fixture-A", generation: 0, refreshToken: String(repeating: "R", count: 43), pending: nil, refreshExpiresAt: Date().addingTimeInterval(86400), absoluteExpiresAt: ISO8601DateFormatter().date(from: "2030-01-01T00:00:00Z")!))
        await authTransport.setHold(true)
        let config = try configuration()
        let auth = NativeAuthenticationService(configuration: config, api: NativeAuthAPI(configuration: config, transport: authTransport), journal: journal, browser: FixtureBrowser())
        let account = NativeAccountModel(auth: auth), transport = StartupMusicTransport(holdCatalog: false), model = try model(transport, account: account)
        defer { model.playback.shutdown(); Task { await transport.releaseAll(); await authTransport.release() } }
        await model.receiveMusicLink(link(StartupMusicTransport.first))
        let startup = Task { await model.initialize() }
        try await until { await authTransport.refreshEntered }
        XCTAssertNil(model.playback.selectedTrack)
        await authTransport.release(); await startup.value
        XCTAssertEqual(model.scope.accountID, "fixture-A")
        XCTAssertEqual(model.playback.selectedTrack?.id, StartupMusicTransport.first.id)
        // A SwiftUI onChange task enqueued by restore can run after initialization.
        await model.accountScopeChanged(account.scope)
        XCTAssertEqual(model.playback.selectedTrack?.id, StartupMusicTransport.first.id)
        let paths = await transport.paths
        XCTAssertEqual(paths.filter { $0.hasSuffix("/music/tracks/" + StartupMusicTransport.first.id) }.count, 1)
        assertNotPlaying(model, paths: paths)
    }
    func testFailedRestoreStillReleasesGuestLink() async throws {
        let authTransport = AuthFixtureTransport(), journal = AuthJournal(store: MemorySecureStore(), environment: .development)
        try await journal.install(CredentialEnvelope(schemaVersion: 1, scope: AccountScope(environment: .development, accountID: "fixture-A"), sessionID: "fixture-session-fixture-A", familyID: "fixture-family-fixture-A", generation: 0, refreshToken: String(repeating: "R", count: 43), pending: nil, refreshExpiresAt: Date().addingTimeInterval(86400), absoluteExpiresAt: Date().addingTimeInterval(172800)))
        await authTransport.setFailRefresh(true)
        let config = try configuration()
        let auth = NativeAuthenticationService(configuration: config, api: NativeAuthAPI(configuration: config, transport: authTransport), journal: journal, browser: FixtureBrowser())
        let transport = StartupMusicTransport(holdCatalog: false), model = try model(transport, account: NativeAccountModel(auth: auth))
        defer { model.playback.shutdown(); Task { await transport.releaseAll() } }
        await model.receiveMusicLink(link(StartupMusicTransport.first)); await model.initialize()
        XCTAssertNil(model.scope.accountID)
        XCTAssertEqual(model.playback.selectedTrack?.id, StartupMusicTransport.first.id)
        assertNotPlaying(model, paths: await transport.paths)
    }
    func testColdAlbumAndWarmTrackResolveWithoutAutoplayOrRepeatedStartup() async throws {
        let transport = StartupMusicTransport(holdCatalog: false), model = try model(transport)
        defer { model.playback.shutdown(); Task { await transport.releaseAll() } }
        await model.receiveMusicLink(URL(string: origin.absoluteString + "/music/?collection=synthetic-album")!)
        await model.initialize()
        XCTAssertEqual(model.activeCollection?.slug, "synthetic-album")
        XCTAssertEqual(model.selectedTab, 1)
        await model.initialize()
        await model.receiveMusicLink(link(StartupMusicTransport.second))
        XCTAssertEqual(model.playback.selectedTrack?.id, StartupMusicTransport.second.id)
        let paths = await transport.paths
        XCTAssertEqual(paths.filter { $0.hasSuffix("/music/catalog") }.count, 1)
        assertNotPlaying(model, paths: paths)
    }
    func testLateLinkResolutionCannotCrossSubsequentAccountChange() async throws {
        let transport = StartupMusicTransport(holdCatalog: false), account = NativeAccountModel(), model = try model(transport, account: account)
        defer { model.playback.shutdown(); Task { await transport.releaseAll() } }
        await model.initialize(); await transport.suspendDetail()
        let opening = Task { await model.receiveMusicLink(link(StartupMusicTransport.first)) }
        try await until { await transport.detailEntered }
        account.scope = AccountScope(environment: .development, accountID: "later-account")
        await model.accountScopeChanged(account.scope)
        await transport.releaseDetail(); await opening.value
        XCTAssertEqual(model.scope.accountID, "later-account")
        XCTAssertNil(model.playback.selectedTrack); XCTAssertNil(model.detail)
        assertNotPlaying(model, paths: await transport.paths)
    }
    func testLocaleAndReloadDuringStartupFinishBeforeSingleQueuedLink() async throws {
        let transport = StartupMusicTransport(), model = try model(transport)
        defer { model.playback.shutdown(); Task { await transport.releaseAll() } }
        model.locale = "en"
        await model.receiveMusicLink(link(StartupMusicTransport.first))
        let startup = Task { await model.initialize() }
        try await until { await transport.catalogEntered }
        model.locale = "ja"
        await model.load()
        await model.load() // Multiple callers coalesce into one replacement load.
        XCTAssertNil(model.playback.selectedTrack)
        let heldLocales = await transport.catalogLocales; XCTAssertEqual(heldLocales, ["en"])
        await transport.releaseCatalog(); await startup.value
        let locales = await transport.catalogLocales; XCTAssertEqual(locales, ["en", "ja"])
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertEqual(model.playback.selectedTrack?.id, StartupMusicTransport.first.id)
        let paths = await transport.paths
        let detailIndex = try XCTUnwrap(paths.firstIndex { $0.hasSuffix("/music/tracks/" + StartupMusicTransport.first.id) })
        let lastCatalogIndex = try XCTUnwrap(paths.lastIndex { $0.hasSuffix("/music/catalog") })
        XCTAssertGreaterThan(detailIndex, lastCatalogIndex)
        XCTAssertEqual(paths.filter { $0.hasSuffix("/music/tracks/" + StartupMusicTransport.first.id) }.count, 1)
        assertNotPlaying(model, paths: paths)
    }
    func testCancelledViewTaskDoesNotConsumeTheOnlyPendingLink() async throws {
        let transport = StartupMusicTransport(), model = try model(transport)
        defer { model.playback.shutdown(); Task { await transport.releaseAll() } }
        await model.receiveMusicLink(link(StartupMusicTransport.first))
        let viewTask = Task { await model.initialize() }
        try await until { await transport.catalogEntered }
        viewTask.cancel()
        await transport.releaseCatalog(); await viewTask.value
        // A replacement RootView task joins the model-owned startup, without
        // restarting it or needing another OS URL delivery.
        await model.initialize()
        XCTAssertEqual(model.playback.selectedTrack?.id, StartupMusicTransport.first.id)
        let paths = await transport.paths
        XCTAssertEqual(paths.filter { $0.hasSuffix("/music/catalog") }.count, 1)
        XCTAssertEqual(paths.filter { $0.hasSuffix("/music/tracks/" + StartupMusicTransport.first.id) }.count, 1)
        assertNotPlaying(model, paths: paths)
    }
}
