import XCTest
@testable import StationCatMusic

private actor StartupMusicTransport: HTTPTransport {
    static let first = Track(id: "10000000-0000-4000-8000-000000000001", title: "First", artist: "Synthetic", durationSeconds: 180, audioVersion: 1, access: .free)
    static let second = Track(id: "10000000-0000-4000-8000-000000000002", title: "Second", artist: "Synthetic", durationSeconds: 180, audioVersion: 1, access: .free)
    private(set) var paths: [String] = []
    private(set) var catalogLocales: [String] = []
    private(set) var catalogEntered = false
    private(set) var detailEntered = false
    private var holdCatalog: Bool
    private var holdDetail = false
    private var catalogWaiters: [CheckedContinuation<Void, Never>] = []
    private var detailWaiters: [CheckedContinuation<Void, Never>] = []
    init(holdCatalog: Bool = true) { self.holdCatalog = holdCatalog }
    func releaseCatalog() { holdCatalog = false; let waiting = catalogWaiters; catalogWaiters = []; waiting.forEach { $0.resume() } }
    func suspendDetail() { holdDetail = true }
    func releaseDetail() { holdDetail = false; let waiting = detailWaiters; detailWaiters = []; waiting.forEach { $0.resume() } }
    func releaseAll() { releaseCatalog(); releaseDetail() }
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
            return try result(Catalog(items: [Self.first, Self.second], nextCursor: nil))
        }
        if path.hasSuffix("/music/featured") { return try result(FeaturedMusic(tracks: [Self.first], collections: [])) }
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
