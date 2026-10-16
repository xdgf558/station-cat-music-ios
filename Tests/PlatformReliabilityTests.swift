import XCTest
@testable import StationCatMusic

private actor ReliabilityCatalog: PlatformMusicProviding {
    nonisolated let webOrigin = PlatformMusicAPI.productionOrigin
    static let id = "33333333-3333-4333-8333-333333333333"
    static let other = "44444444-4444-4444-8444-444444444444"
    private var offline = false, empty = true, wrongIdentity = false
    private var held: [String: CheckedContinuation<Void, Never>] = [:]
    private var gates = Set<String>()
    private var catalogHeld = false
    private var catalogWaiter: CheckedContinuation<Void, Never>?
    func holdCatalog() { catalogHeld = true }
    func releaseCatalog() { catalogHeld = false; catalogWaiter?.resume(); catalogWaiter = nil }
    private(set) var resolutions: [String] = []
    func setLocale(_ locale: String) {}
    func configure(offline: Bool = false, empty: Bool = true, wrongIdentity: Bool = false) { self.offline = offline; self.empty = empty; self.wrongIdentity = wrongIdentity }
    func hold(_ slug: String) { gates.insert(slug) }
    func release(_ slug: String) { gates.remove(slug); held.removeValue(forKey: slug)?.resume() }
    func track(slug: String = "new-song", locale: String = "en") -> Track {
        let id = slug == "new-song" ? Self.id : Self.other
        var value = Track(id: id, title: slug, artist: "Station Cat", durationSeconds: 0, audioVersion: 1, access: .unavailable)
        value.release = PlatformTrackRelease(slug: slug, summary: "", webURL: webOrigin.appending(path: "music/tracks/" + slug + "/"), platforms: [], availability: "unconfirmed", previewAvailable: false)
        return value
    }
    func catalog() async throws -> Catalog {
        if catalogHeld { await withCheckedContinuation { catalogWaiter = $0 } }
        if offline { throw URLError(.notConnectedToInternet) }
        return Catalog(items: empty ? [] : [track()], nextCursor: nil)
    }
    func featuredTracks() throws -> [Track] { if offline { throw URLError(.notConnectedToInternet) }; return [] }
    func platformDetail(_ track: Track, locale: String) async throws -> PlatformTrackDetail { try await resolvePlatformTrack(slug: track.release!.slug, locale: locale) }
    func resolvePlatformTrack(slug: String, locale: String) async throws -> PlatformTrackDetail {
        resolutions.append(slug)
        if gates.contains(slug) { await withCheckedContinuation { held[slug] = $0 } }
        if offline { throw URLError(.notConnectedToInternet) }
        if slug == "missing" { throw APIError.rejected(404) }
        if slug == "withdrawn" { throw APIError.rejected(410) }
        // Intentionally ignores Task cancellation so model guards must reject a late result.
        return PlatformTrackDetail(track: track(slug: wrongIdentity ? "wrong-song" : slug, locale: locale), story: locale, lyricsURL: nil)
    }
    func bookmark(_ track: Track, locale: String) throws -> PlatformBookmark {
        if offline { throw URLError(.notConnectedToInternet) }
        return PlatformBookmark(id: track.id, slug: track.release!.slug, title: track.title, artist: track.artist,
            revision: track.audioVersion, locale: locale, savedAt: Date(), expires: Date().addingTimeInterval(3600))
    }
}

@MainActor final class PlatformReliabilityTests: XCTestCase {
    private let origin = PlatformMusicAPI.productionOrigin
    private func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<200 { if predicate() { return }; try await Task.sleep(for: .milliseconds(10)) }
        XCTFail("State did not settle")
    }
    private func folder() -> URL { FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appending(path: "bookmark-test-" + UUID().uuidString) }
    func testSharedPromotionLinkMatrix() throws {
        struct Matrix: Decodable { let cases: [Item]; struct Item: Decodable { let url: URL; let accepted: Bool; let slug: String? } }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "platform-link-cases", withExtension: "json"))
        let matrix = try JSONDecoder().decode(Matrix.self, from: Data(contentsOf: url))
        for item in matrix.cases {
            let parsed = PlatformMusicLink(item.url, origin: origin)
            XCTAssertEqual(parsed != nil, item.accepted, item.url.absoluteString)
            if item.accepted { XCTAssertEqual(parsed?.slug, item.slug); XCTAssertNil(URLComponents(url: parsed!.canonicalURL, resolvingAgainstBaseURL: false)?.query) }
        }
        let old = try XCTUnwrap(PlatformMusicLink(URL(string: origin.absoluteString + "/music/?track=" + ReliabilityCatalog.id + "&utm_source=douyin")!, origin: origin))
        XCTAssertEqual(old.id, ReliabilityCatalog.id); XCTAssertEqual(old.attribution, ["utm_source": "douyin"])
    }
    func testNewSongResolvesAtColdLaunchWithFailedCatalogAndNeverPlays() async throws {
        let source = ReliabilityCatalog(); await source.configure(offline: true)
        let model = AppModel(client: source, platformMode: true); model.locale = "en"
        // Catalog is unavailable on first launch. Direct request succeeds after retry.
        await model.receiveMusicLink(URL(string: origin.absoluteString + "/music/tracks/new-song/?utm_source=douyin&utm_content=clip01")!)
        await model.initialize(); try await wait { model.platformDetailFailure }
        XCTAssertEqual(model.phase, .unavailable); XCTAssertEqual(model.platformDetailFailureKey, "startupFailure.offline")
        await source.configure()
        model.retryPlatformDetail(); try await wait { model.platformDetail != nil }
        XCTAssertEqual(model.platformDetail?.track.id, ReliabilityCatalog.id)
        XCTAssertEqual(model.platformAttribution["utm_source"], "douyin")
        XCTAssertTrue(model.tracks.isEmpty); XCTAssertFalse(model.playback.hasAudioSource)
        XCTAssertNil(model.nativeMusic)
        // A later successful empty catalog must not discard the directly resolved work.
        await model.load(); try await wait { model.platformDetail != nil }
        XCTAssertEqual(model.platformDetail?.track.id, ReliabilityCatalog.id)
    }
    func testColdSingleLinkDoesNotWaitForHeldCatalog() async throws {
        let source = ReliabilityCatalog(); await source.holdCatalog()
        let model = AppModel(client: source, platformMode: true); model.locale = "en"
        await model.receiveMusicLink(URL(string: origin.absoluteString + "/ja/music/tracks/new-song/?utm_source=douyin")!)
        let initialization = Task { await model.initialize() }
        try await wait { model.platformDetail != nil }
        XCTAssertEqual(model.phase, .loading)
        XCTAssertEqual(model.startupPhase, .ready)
        XCTAssertEqual(model.platformDetail?.track.id, ReliabilityCatalog.id)
        XCTAssertFalse(model.playback.hasAudioSource)
        await source.releaseCatalog(); await initialization.value
        XCTAssertEqual(model.platformDetail?.track.id, ReliabilityCatalog.id)
    }
    func testLatestLinkAndLocaleWinOverDelayedResolution() async throws {
        let source = ReliabilityCatalog(); let model = AppModel(client: source, platformMode: true); model.locale = "en"
        await model.initialize(); await source.hold("new-song")
        await model.receiveMusicLink(origin.appending(path: "music/tracks/new-song/"))
        for _ in 0..<100 { if await source.resolutions.contains("new-song") { break }; try await Task.sleep(for: .milliseconds(10)) }
        await model.receiveMusicLink(URL(string: origin.absoluteString + "/music/tracks/other-song/?utm_campaign=second")!)
        try await wait { model.platformDetail?.track.id == ReliabilityCatalog.other }
        await source.release("new-song"); try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(model.platformDetail?.track.id, ReliabilityCatalog.other)
        XCTAssertEqual(model.platformAttribution, ["utm_campaign":"second"])
        model.locale = "ja"; await model.load(); try await wait { model.platformDetail?.story == "ja" }
        XCTAssertEqual(model.platformDetail?.track.id, ReliabilityCatalog.other)
    }
    func testMissingWithdrawnAndWrongIdentityNeverPublishOrPlay() async throws {
        let source = ReliabilityCatalog(); let model = AppModel(client: source, platformMode: true); model.locale = "en"
        await model.initialize()
        for (slug, key) in [("missing","platformWorkMissing"),("withdrawn","platformWorkRemoved")] {
            await model.openMusicLink(origin.appending(path: "music/tracks/" + slug + "/"))
            try await wait { model.platformDetailFailure }; XCTAssertEqual(model.platformDetailFailureKey, key); XCTAssertNil(model.platformDetail)
        }
        await source.configure(wrongIdentity: true)
        await model.openMusicLink(origin.appending(path: "music/tracks/new-song/"))
        try await wait { model.platformDetailFailure }
        XCTAssertEqual(model.platformDetailFailureKey, "startupFailure.payload")
        XCTAssertFalse(model.playback.hasAudioSource); XCTAssertNil(model.nativeMusic)
    }
    func testFavoriteRelaunchOfflineRetainsCountAndExplicitlyPermittedText() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let libraryURL = root.appending(path: "library"), cacheURL = root.appending(path: "cache")
        let source = ReliabilityCatalog(); await source.configure(empty: false)
        let model = AppModel(client: source, library: ScopedLibrary(directory: libraryURL), platformMode: true, bookmarks: PlatformBookmarkStore(directory: cacheURL)); model.locale = "en"
        await model.initialize(); await model.toggleFavorite(try XCTUnwrap(model.tracks.first))
        try await wait { model.favoriteBookmarks.count == 1 }
        let files = try FileManager.default.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: nil)
        let persisted = try String(contentsOf: XCTUnwrap(files.first), encoding: .utf8)
        for forbidden in ["https:", "platforms", "playback", "coverUrl"] { XCTAssertFalse(persisted.contains(forbidden)) }
        await source.configure(offline: true)
        let reopened = AppModel(client: source, library: ScopedLibrary(directory: libraryURL), platformMode: true, bookmarks: PlatformBookmarkStore(directory: cacheURL)); reopened.locale = "en"
        await reopened.initialize()
        XCTAssertEqual(reopened.favoriteCount, 1)
        let row = try XCTUnwrap(reopened.platformFavorites.first)
        XCTAssertNil(row.track); XCTAssertEqual(row.bookmark?.title, "new-song")
        reopened.openPlatformFavorite(row); try await wait { reopened.platformDetailFailure }
        XCTAssertNil(reopened.platformDetail); XCTAssertFalse(reopened.playback.hasAudioSource)
        await reopened.toggleFavoriteID(row.id); XCTAssertEqual(reopened.favoriteCount, 0)
    }
    func testLegacyFavoriteWithoutSnapshotStillHasPlaceholderAndCanBeRemoved() async throws {
        let library = ScopedLibrary(); try await library.setFavorite(ReliabilityCatalog.id, value: true, scope: .guest)
        let source = ReliabilityCatalog(); await source.configure(offline: true)
        let model = AppModel(client: source, library: library, platformMode: true)
        await model.initialize(); XCTAssertEqual(model.favoriteCount, 1)
        let row = try XCTUnwrap(model.platformFavorites.first)
        XCTAssertNil(row.track); XCTAssertNil(row.bookmark)
        await model.toggleFavoriteID(row.id); XCTAssertTrue(model.favorites.isEmpty)
    }
    func testCorruptBookmarkIsRepairableAndSymlinkTargetIsNeverTouched() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let item = PlatformBookmark(id: ReliabilityCatalog.id, slug: "new-song", title: "Saved title", artist: "Station Cat", revision: 1, locale: "en", savedAt: now, expires: now.addingTimeInterval(3600))
        let store = PlatformBookmarkStore(directory: root); try await store.save(item, scope: .guest)
        let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let url = try XCTUnwrap(urls.first)
        try Data("broken JSON".utf8).write(to: url)
        let reopened = PlatformBookmarkStore(directory: root)
        let missed = try await reopened.snapshots(scope: .guest); XCTAssertTrue(missed.isEmpty)
        try await reopened.save(item, scope: .guest)
        let repaired = try await reopened.snapshots(scope: .guest); XCTAssertEqual(repaired[item.id], item)
        try FileManager.default.removeItem(at: url)
        let target = root.appending(path: "unrelated-file")
        let sentinel = Data("leave this alone".utf8); try sentinel.write(to: target)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        do { try await PlatformBookmarkStore(directory: root).save(item, scope: .guest); XCTFail("Symlink accepted") } catch {}
        XCTAssertEqual(try Data(contentsOf: target), sentinel)
    }
    func testExpiredOrClockRollbackMetadataCannotHideFavoriteOrAuthorizeLink() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(), scope = AccountScope.guest
        let item = PlatformBookmark(id: ReliabilityCatalog.id, slug: "new-song", title: "Saved title", artist: "Station Cat", revision: 1, locale: "en", savedAt: now, expires: now.addingTimeInterval(60))
        let store = PlatformBookmarkStore(directory: root, now: { now }); try await store.save(item, scope: scope)
        let expired = PlatformBookmarkStore(directory: root, now: { now.addingTimeInterval(61) })
        let expiredItems = try await expired.snapshots(scope: scope); XCTAssertTrue(expiredItems.isEmpty)
        let rollback = PlatformBookmarkStore(directory: root, now: { now.addingTimeInterval(-10) })
        let hidden = try await rollback.snapshots(scope: scope); XCTAssertTrue(hidden.isEmpty)
        let restored = try await PlatformBookmarkStore(directory: root, now: { now }).snapshots(scope: scope)
        XCTAssertEqual(restored[item.id], item)
        let other = try await store.snapshots(scope: AccountScope(environment: .production, accountID: "another-account"))
        XCTAssertTrue(other.isEmpty)
    }
}
