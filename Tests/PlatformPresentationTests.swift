import XCTest
import CryptoKit
@testable import StationCatMusic

private actor PresentationCatalog: PlatformMusicProviding {
    nonisolated let webOrigin = PlatformMusicAPI.productionOrigin
    static let firstID = "11111111-1111-4111-8111-111111111111"
    static let secondID = "22222222-2222-4222-8222-222222222222"
    private var locale = "en"
    private var fail = false
    private var held = false
    private var featuredHeld = false
    private var featuredWaiters: [CheckedContinuation<Void, Never>] = []
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var detailCalls: [String] = []
    func setLocale(_ value: String) { locale = value }
    func setFailure(_ value: Bool) { fail = value }
    func holdDetails() { held = true }
    func releaseDetails() { held = false; let old = waiting; waiting = []; old.forEach { $0.resume() } }
    func holdFeatured() { featuredHeld = true }
    func releaseFeatured() { featuredHeld = false; let old = featuredWaiters; featuredWaiters = []; old.forEach { $0.resume() } }
    func track(_ id: String) -> Track {
        let slug = id == Self.firstID ? "night-window" : "slow-morning"
        let prefix = locale == "zh-Hant" ? "" : "/" + locale.lowercased()
        var track = Track(id: id, title: slug, artist: "Station Cat", durationSeconds: 180, audioVersion: 1, access: .unavailable)
        track.offlineEligible = false
        var components = URLComponents(url: webOrigin, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath = prefix + "/music/tracks/" + slug + "/"
        track.release = PlatformTrackRelease(slug: slug, summary: "A public work.", webURL: components.url!, platforms: [], availability: "unreleased", previewAvailable: false)
        return track
    }
    func catalog() throws -> Catalog {
        if fail { throw URLError(.notConnectedToInternet) }
        return Catalog(items: [track(Self.firstID), track(Self.secondID)], nextCursor: nil)
    }
    func featuredTracks() async throws -> [Track] {
        if featuredHeld { await withCheckedContinuation { featuredWaiters.append($0) } }
        if fail { throw URLError(.notConnectedToInternet) }
        return [track(Self.firstID)]
    }
    func resolvePlatformTrack(slug: String, locale: String) async throws -> PlatformTrackDetail {
        guard let value = [track(Self.firstID), track(Self.secondID)].first(where: { $0.release?.slug == slug }) else { throw APIError.rejected(404) }
        return try await platformDetail(value, locale: locale)
    }
    func platformDetail(_ track: Track, locale: String) async throws -> PlatformTrackDetail {
        detailCalls.append(track.id)
        if held { await withCheckedContinuation { waiting.append($0) } }
        return PlatformTrackDetail(track: track, story: "Public story", lyricsURL: nil)
    }
}

@MainActor final class PlatformPresentationTests: XCTestCase {
    private func directory() -> URL { FileManager.default.temporaryDirectory.appending(path: "platform-presentation-" + UUID().uuidString) }
    private func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<200 { if predicate() { return }; try await Task.sleep(for: .milliseconds(10)) }
        XCTFail("Platform presentation did not settle")
    }
    func testNewDetailLinkIsQueuedAtColdLaunchWithoutAudioOrGrant() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let source = PresentationCatalog()
        let model = AppModel(client: source, library: ScopedLibrary(directory: folder), platformMode: true)
        model.locale = "en"
        await model.receiveMusicLink(PlatformMusicAPI.productionOrigin.appending(path: "music/tracks/night-window/"))
        await model.initialize()
        try await wait { model.platformDetail != nil }
        XCTAssertEqual(model.playback.selectedTrack?.id, PresentationCatalog.firstID)
        XCTAssertTrue(model.showPlayer)
        XCTAssertFalse(model.playback.hasAudioSource)
        XCTAssertEqual(model.playback.state, .selected)
        XCTAssertNil(model.nativeMusic)
        XCTAssertNil(model.libraryRemote)
        XCTAssertEqual(model.trackShareURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedPath }, "/en/music/tracks/night-window/")
    }
    func testInvalidLinksCannotReplaceAValidColdLaunchIntent() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let model = AppModel(client: PresentationCatalog(), library: ScopedLibrary(directory: folder), platformMode: true)
        await model.receiveMusicLink(PlatformMusicAPI.productionOrigin.appending(path: "music/tracks/night-window/"))
        for value in ["/music/tracks/slow-morning/?next=bad", "/music/tracks/%73low-morning/", "/auth/mobile/callback", "/music/tracks/slow-morning/#fragment"] {
            await model.receiveMusicLink(URL(string: value, relativeTo: PlatformMusicAPI.productionOrigin)!.absoluteURL)
        }
        await model.initialize()
        try await wait { model.platformDetail != nil }
        XCTAssertEqual(model.playback.selectedTrack?.id, PresentationCatalog.firstID)
        XCTAssertFalse(model.playback.hasAudioSource)
    }
    func testDetailResponseFromPreviousSelectionCannotPublish() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let source = PresentationCatalog(), model = AppModel(client: source, library: ScopedLibrary(directory: folder), platformMode: true)
        await model.initialize(); await source.holdDetails()
        model.selectPlatformTrack(model.tracks[0])
        for _ in 0..<100 { if await source.detailCalls.count == 1 { break }; try await Task.sleep(for: .milliseconds(10)) }
        model.selectPlatformTrack(model.tracks[1])
        await source.releaseDetails()
        try await wait { model.platformDetail?.track.id == PresentationCatalog.secondID }
        XCTAssertEqual(model.playback.selectedTrack?.id, PresentationCatalog.secondID)
        XCTAssertFalse(model.playback.hasAudioSource)
    }
    func testRefreshFailureRetainsThePublicListAndHasRetryMessage() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let source = PresentationCatalog(), model = AppModel(client: source, library: ScopedLibrary(directory: folder), platformMode: true)
        await model.initialize(); let before = model.tracks
        let previousArtworkRetry = model.artworkRetryGeneration
        await source.setFailure(true); await model.load()
        XCTAssertEqual(model.tracks, before)
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertNotNil(model.catalogFailure)
        XCTAssertGreaterThan(model.artworkRetryGeneration, previousArtworkRetry,
            "A user retry must also give failed artwork views another attempt")
        await source.setFailure(false); await model.load()
        XCTAssertNil(model.catalogFailure)
    }
    func testSmallPlatformRowsUseCardDerivativeWithoutChangingOtherArtworkURLs() {
        let asset = "/api/station/content/assets/cccccccc-cccc-4ccc-8ccc-cccccccccccc"
        let display = URL(string: "https://wwwstationcat.org" + asset + "?size=display")!
        XCTAssertEqual(PlatformArtwork.url(display, thumbnail: true).absoluteString,
            "https://wwwstationcat.org" + asset + "?size=card")
        XCTAssertEqual(PlatformArtwork.url(display, thumbnail: false), display)
        for raw in ["https://artwork.test" + asset + "?size=display",
                    "https://wwwstationcat.org/api/music/tracks/cccccccc-cccc-4ccc-8ccc-cccccccccccc/cover?size=display",
                    "https://wwwstationcat.org" + asset + "?size=display&extra=1",
                    "https://wwwstationcat.org/api/station/content/assets/not-an-id?size=display"] {
            let existing = URL(string: raw)!
            XCTAssertEqual(PlatformArtwork.url(existing, thumbnail: true), existing)
        }
    }
    func testPlatformRefreshPreservesLegacyAudioReceiptAndDoesNotReconcileIt() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let origin = URL(string: "https://old-isolated.example.test")!
        let cache = OfflineMusicCache(origin: origin, baseDirectory: folder)
        let cacheFolder = await cache.directory
        let bytes = Data(repeating: 1, count: 32), now = Date()
        let digest: (Data) -> String = { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
        var legacy = Track(id: PresentationCatalog.firstID, title: "Original", artist: "Station Cat", durationSeconds: 180, audioVersion: 1, access: .free)
        legacy.offlineEligible = true
        let permit = OfflinePermit(trackId: legacy.id, audioVersion: 1, policyVersion: 1, accessMode: "free", variant: "full", byteSize: bytes.count, sha256: digest(bytes), durationSeconds: 180, validUntil: now.addingTimeInterval(7 * 86400))
        let song = OfflineSong(track: legacy, permit: permit, savedAt: now, expiresAt: now.addingTimeInterval(600))
        let songFolder = cacheFolder.appending(path: digest(Data(legacy.id.utf8)))
        try FileManager.default.createDirectory(at: songFolder, withIntermediateDirectories: true)
        let receipt = try JSONEncoder().encode(song)
        try receipt.write(to: songFolder.appending(path: "receipt.json")); try bytes.write(to: songFolder.appending(path: "audio.mp3"))
        let model = AppModel(client: PresentationCatalog(), library: ScopedLibrary(directory: folder.appending(path: "library")), offlineStorage: cache, platformMode: true)
        await model.initialize(); await model.load()
        XCTAssertEqual(try Data(contentsOf: songFolder.appending(path: "receipt.json")), receipt)
        XCTAssertEqual(try Data(contentsOf: songFolder.appending(path: "audio.mp3")), bytes)
        XCTAssertEqual(model.offlineSongs.map(\.id), [legacy.id])
        XCTAssertFalse(model.playback.hasAudioSource)
        model.setAutoCache(true); model.saveOffline(model.tracks[0])
        XCTAssertFalse(model.autoCacheFreeSongs)
        XCTAssertNil(model.offlineDownloading)
    }
    func testLocalFavoriteSurvivesPlatformReloadAndLibraryReopen() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let model = AppModel(client: PresentationCatalog(), library: ScopedLibrary(directory: folder), platformMode: true)
        await model.initialize(); try await model.library.setFavorite(model.tracks[0].id, value: true, scope: .guest)
        await model.load(); await model.refreshLibrary()
        XCTAssertEqual(model.favoriteTracks.map(\.id), [PresentationCatalog.firstID])
        let reopened = AppModel(client: PresentationCatalog(), library: ScopedLibrary(directory: folder), platformMode: true)
        await reopened.initialize()
        XCTAssertEqual(reopened.favoriteTracks.map(\.id), [PresentationCatalog.firstID])
    }
    func testPublicOptInIsIndependentAndClosedByDefault() {
        let base: [String: Any] = ["StationEnvironment": "production", "StationNativeAuthEnabled": "YES"]
        XCTAssertNil(PlatformConfiguration(info: base).origin)
        let open = base.merging(["StationPublicReleasesEnabled": "YES", "StationPublicReleaseOrigin": ProductionActivationProfile.origin]) { _, right in right }
        XCTAssertEqual(PlatformConfiguration(info: open).origin, PlatformMusicAPI.productionOrigin)
        for raw in ["https://wrong.example.test", ProductionActivationProfile.origin + "/", ProductionActivationProfile.origin + "?extra=1"] {
            var fields = open; fields["StationPublicReleaseOrigin"] = raw
            XCTAssertNil(PlatformConfiguration(info: fields).origin)
        }
        var mock = open; mock["StationEnvironment"] = "mock"
        XCTAssertNil(PlatformConfiguration(info: mock).origin)
    }
    func testCatalogCanDismissStartupBeforeSlowFeaturedDetailsFinish() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let source = PresentationCatalog(); await source.holdFeatured()
        let model = AppModel(client: source, library: ScopedLibrary(directory: folder), platformMode: true)
        let initialization = Task { await model.initialize() }
        try await wait { model.startupPhase == .ready }
        XCTAssertEqual(model.tracks.count, 2)
        XCTAssertTrue(model.featuredTracks.isEmpty)
        XCTAssertEqual(model.discoveryTracks.count, 2)
        await source.releaseFeatured(); await initialization.value
        XCTAssertEqual(model.featuredTracks.count, 1)
    }
    func testLegacyCacheNamespaceDoesNotDependOnAuthenticationOrPublicOptIn() async {
        let fields: [String: Any] = ["StationEnvironment": "staging", "StationNativeAuthEnabled": "NO",
            "StationPublicReleasesEnabled": "NO", "StationLegacyOfflineOrigin": PlatformConfiguration.previousStagingOrigin.absoluteString]
        let configuration = PlatformConfiguration(info: fields)
        XCTAssertNil(configuration.origin)
        XCTAssertEqual(configuration.legacyOfflineOrigin, PlatformConfiguration.previousStagingOrigin)
        XCTAssertNil(NativeRuntimeConfiguration(info: fields).authentication)
        var bad = fields; bad["StationLegacyOfflineOrigin"] = "https://other-cache.example.test"
        XCTAssertNil(PlatformConfiguration(info: bad).legacyOfflineOrigin)
        do { _ = try await LegacyOfflineManagementTransport().send(URLRequest(url: PlatformConfiguration.previousStagingOrigin)); XCTFail("Management must never fetch audio") }
        catch { XCTAssertEqual(error as? APIError, .networkDisabled) }
    }
}
