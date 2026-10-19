import XCTest
@testable import StationCatMusic

private final class VisitClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_790_000_000)
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return date }
    func advance(_ seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; date.addTimeInterval(seconds) }
}

private actor PersonalCatalog: PlatformMusicProviding {
    nonisolated let webOrigin = PlatformMusicAPI.productionOrigin
    static let first = "11111111-1111-4111-8111-111111111111"
    static let second = "22222222-2222-4222-8222-222222222222"
    var offline = false
    var hold = false
    private var waiter: CheckedContinuation<Void, Never>?
    private(set) var started = false
    func setLocale(_ locale: String) {}
    func configure(offline: Bool = false, hold: Bool = false) { self.offline = offline; self.hold = hold; started = false }
    func release() { hold = false; waiter?.resume(); waiter = nil }
    func track(_ id: String = first) -> Track {
        let slug = id == Self.first ? "first-song" : "second-song"
        return Track(id: id, title: slug, artist: "Station Cat", durationSeconds: 0, audioVersion: 1, access: .unavailable,
            release: PlatformTrackRelease(slug: slug, summary: "", webURL: webOrigin.appending(path: "music/tracks/" + slug + "/"), platforms: [], availability: "unconfirmed", previewAvailable: false))
    }
    func catalog() throws -> Catalog {
        if offline { throw URLError(.notConnectedToInternet) }
        return Catalog(items: [track(), track(Self.second)], nextCursor: nil)
    }
    func featuredTracks() throws -> [Track] { [] }
    func platformDetail(_ track: Track, locale: String) async throws -> PlatformTrackDetail {
        try await resolvePlatformTrack(slug: track.release!.slug, locale: locale)
    }
    func resolvePlatformTrack(slug: String, locale: String) async throws -> PlatformTrackDetail {
        started = true
        if hold { await withCheckedContinuation { waiter = $0 } }
        if offline { throw URLError(.notConnectedToInternet) }
        return PlatformTrackDetail(track: track(slug == "first-song" ? Self.first : Self.second), story: "", lyricsURL: nil)
    }
    func bookmark(_ track: Track, locale: String) throws -> PlatformBookmark {
        if offline { throw URLError(.notConnectedToInternet) }
        return PlatformBookmark(id: track.id, slug: track.release!.slug, title: track.title, artist: track.artist,
            revision: 1, locale: locale, savedAt: Date(), expires: Date().addingTimeInterval(3600))
    }
}

@MainActor final class PlatformPersonalizationTests: XCTestCase {
    private func folder() -> URL { FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appending(path: "personal-" + UUID().uuidString) }
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 { if condition() { return }; try await Task.sleep(for: .milliseconds(10)) }
        XCTFail("Personal state did not settle")
    }
    func testLocalHistorySurvivesReopenAndIsNotPlaybackHistory() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let personalURL = root.appending(path: "personal"), bookmarkURL = root.appending(path: "bookmarks")
        let source = PersonalCatalog(), library = ScopedLibrary()
        let model = AppModel(client: source, library: library, platformMode: true, bookmarks: PlatformBookmarkStore(directory: bookmarkURL), personal: PlatformPersonalStore(directory: personalURL))
        await model.initialize()
        let track = try XCTUnwrap(model.tracks.first)
        await model.toggleFavorite(track)
        model.selectPlatformTrack(track)
        try await wait { model.platformVisits.count == 1 && model.favoriteBookmarks[track.id] != nil }
        XCTAssertTrue(model.recent.isEmpty); XCTAssertFalse(model.playback.hasAudioSource)
        await source.configure(offline: true)
        let reopened = AppModel(client: source, library: library, platformMode: true, bookmarks: PlatformBookmarkStore(directory: bookmarkURL), personal: PlatformPersonalStore(directory: personalURL))
        await reopened.initialize()
        XCTAssertEqual(reopened.favoriteCount, 1); XCTAssertEqual(reopened.platformVisits.count, 1)
        let row = try XCTUnwrap(reopened.platformVisits.first)
        XCTAssertNil(row.track); XCTAssertEqual(row.bookmark?.title, "first-song")
        reopened.openPlatformVisit(row); try await wait { reopened.platformDetailFailure }
        XCTAssertNil(reopened.platformDetail); XCTAssertFalse(reopened.playback.hasAudioSource)
        XCTAssertTrue(reopened.recent.isEmpty)
        let url = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: personalURL, includingPropertiesForKeys: nil).first)
        let json = try String(contentsOf: url, encoding: .utf8)
        for forbidden in ["https:", "utm_", "title", "artist", "platforms", "playback", "coverUrl"] { XCTAssertFalse(json.contains(forbidden)) }
    }
    func testClearAndOffOnRejectLateDetailEvenAfterDiskReopen() async throws {
        for disable in [false, true] {
            let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
            let source = PersonalCatalog(), personal = PlatformPersonalStore(directory: root)
            let model = AppModel(client: source, platformMode: true, personal: personal)
            await model.initialize(); await source.configure(hold: true)
            model.selectPlatformTrack(try XCTUnwrap(model.tracks.first))
            for _ in 0..<100 { if await source.started { break }; try await Task.sleep(for: .milliseconds(10)) }
            let oldEpoch = try XCTUnwrap(model.personalState?.historyEpoch)
            if disable { await model.setBrowsingHistory(false); await model.setBrowsingHistory(true) }
            else { await model.clearBrowsingHistory() }
            await source.release(); try await wait { model.platformDetail != nil }
            try await Task.sleep(for: .milliseconds(30))
            XCTAssertTrue(model.platformVisits.isEmpty)
            let reopened = PlatformPersonalStore(directory: root)
            let rejected = try await reopened.record(id: PersonalCatalog.first, slug: "first-song", epoch: oldEpoch, scope: .guest)
            XCTAssertTrue(rejected.visits.isEmpty)
            model.selectPlatformTrack(try XCTUnwrap(model.tracks.first))
            try await wait { model.platformVisits.count == 1 }
        }
    }
    func testCloseOrScopeSwitchWhileDetailLoadsDoesNotRecordOldWork() async throws {
        for changeScope in [false, true] {
            let source = PersonalCatalog(), personal = PlatformPersonalStore()
            let model = AppModel(client: source, platformMode: true, personal: personal)
            await model.initialize(); await source.configure(hold: true)
            model.selectPlatformTrack(try XCTUnwrap(model.tracks.first))
            for _ in 0..<100 { if await source.started { break }; try await Task.sleep(for: .milliseconds(10)) }
            if changeScope { await model.changeScope(AccountScope(environment: .mock, accountID: UUID().uuidString)) }
            else { model.showPlayer = false }
            await source.release(); try await Task.sleep(for: .milliseconds(40))
            let guest = try await personal.snapshot(scope: .guest)
            XCTAssertTrue(guest.visits.isEmpty); XCTAssertTrue(model.platformVisits.isEmpty)
        }
    }
    func testRefreshDoesNotCountAnotherViewAndPreferenceDoesNotClearHistory() async throws {
        let source = PersonalCatalog(), model = AppModel(client: PersonalCatalog(), platformMode: true)
        await model.initialize(); model.selectPlatformTrack(await source.track())
        try await wait { model.platformVisits.count == 1 }
        let date = model.platformVisits.first?.visit.viewedAt
        await model.setPreferredPlatform(.spotify)
        await model.load(); try await wait { model.platformDetail != nil }
        XCTAssertEqual(model.platformVisits.first?.visit.viewedAt, date)
        XCTAssertEqual(model.preferredPlatform, .spotify)
    }
    func testRetentionDeduplicationAndBoundedOrdering() async throws {
        let clock = VisitClock(), store = PlatformPersonalStore(now: { clock.now() })
        let initial = try await store.snapshot(scope: .guest)
        for index in 0..<105 {
            let id = String(format: "11111111-1111-4111-8111-%012d", index)
            _ = try await store.record(id: id, slug: "song-\(index)", epoch: initial.historyEpoch, scope: .guest)
            clock.advance(1)
        }
        var state = try await store.snapshot(scope: .guest)
        XCTAssertEqual(state.visits.count, 100); XCTAssertEqual(state.visits.first?.slug, "song-104")
        let last = try XCTUnwrap(state.visits.last)
        state = try await store.record(id: last.id, slug: last.slug, epoch: state.historyEpoch, scope: .guest)
        XCTAssertEqual(state.visits.count, 100); XCTAssertEqual(state.visits.first?.id, last.id)
        clock.advance(PlatformPersonalStore.retention + 1)
        state = try await store.snapshot(scope: .guest); XCTAssertTrue(state.visits.isEmpty)
    }
    func testPreferencesKeepServerOrderAndNeverInventPlatformLinks() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let scope = AccountScope(environment: .production, accountID: nil)
        let store = PlatformPersonalStore(directory: root)
        let links = [PlatformProvider.netease, .spotify, .netease, .youtube].enumerated().map {
            PlatformLink(id: "\($0.offset)", provider: $0.element, url: URL(string: "https://example.invalid/\($0.offset)")!)
        }
        let empty = try await store.snapshot(scope: scope)
        XCTAssertEqual(empty.orderedLinks(links), links)
        _ = try await store.setPreferred(.netease, scope: scope)
        let reopened = try await PlatformPersonalStore(directory: root).snapshot(scope: scope)
        XCTAssertEqual(reopened.orderedLinks(links), [links[0], links[2], links[1], links[3]])
        let missing = try await store.setPreferred(.qishui, scope: scope)
        XCTAssertEqual(missing.orderedLinks(links), links)
        let otherEnvironment = try await store.snapshot(scope: .guest)
        XCTAssertNil(otherEnvironment.preferred)
        let otherAccount = try await store.snapshot(scope: AccountScope(environment: .production, accountID: UUID().uuidString))
        XCTAssertNil(otherAccount.preferred)
    }
    func testDisabledStateCorruptionAndSymlinkFailClosed() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let store = PlatformPersonalStore(directory: root)
        let off = try await store.setHistory(false, scope: .guest)
        let reopened = try await PlatformPersonalStore(directory: root).snapshot(scope: .guest)
        XCTAssertFalse(reopened.historyEnabled); XCTAssertEqual(reopened.historyEpoch, off.historyEpoch)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first)
        try Data("broken".utf8).write(to: file)
        do { _ = try await store.snapshot(scope: .guest); XCTFail("Reset corrupt privacy state") } catch {}
        do { _ = try await store.setPreferred(.netease, scope: .guest); XCTFail("Overwrote corrupt privacy state") } catch {}
        XCTAssertEqual(try Data(contentsOf: file), Data("broken".utf8))
        try FileManager.default.removeItem(at: file)
        let target = root.deletingLastPathComponent().appending(path: "sentinel-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: target) }
        try Data("keep".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        do { _ = try await store.setHistory(false, scope: .guest); XCTFail("Followed symlink") } catch {}
        XCTAssertEqual(try Data(contentsOf: target), Data("keep".utf8))
    }
    func testAccountDeletionRemovesOnlyScopedNewData() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let store = PlatformPersonalStore(directory: root), account = AccountScope(environment: .mock, accountID: UUID().uuidString)
        _ = try await store.setPreferred(.netease, scope: .guest)
        _ = try await store.setPreferred(.spotify, scope: account)
        try await store.removeDeletedAccount(scope: account)
        do { _ = try await store.setPreferred(.spotify, scope: account); XCTFail("Resurrected deleted scope") } catch {}
        let guest = try await store.snapshot(scope: .guest); XCTAssertEqual(guest.preferred, .netease)
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil); XCTAssertEqual(files.count, 1)
    }
    func testClockRollbackHidesButDoesNotEraseAndExpiryPrunesDisk() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let clock = VisitClock(), store = PlatformPersonalStore(directory: root, now: { clock.now() })
        let initial = try await store.snapshot(scope: .guest)
        _ = try await store.record(id: PersonalCatalog.first, slug: "first-song", epoch: initial.historyEpoch, scope: .guest)
        clock.advance(-60)
        let hidden = try await store.snapshot(scope: .guest); XCTAssertTrue(hidden.visits.isEmpty)
        clock.advance(61)
        let restored = try await PlatformPersonalStore(directory: root, now: { clock.now() }).snapshot(scope: .guest)
        XCTAssertEqual(restored.visits.count, 1)
        clock.advance(PlatformPersonalStore.retention + 1)
        let expired = try await store.snapshot(scope: .guest); XCTAssertTrue(expired.visits.isEmpty)
        let url = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first)
        XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("first-song"))
    }
    func testClearBrowsingPreservesFavoritesAndEarlierListeningHistory() async throws {
        let source = PersonalCatalog(), library = ScopedLibrary()
        let model = AppModel(client: source, library: library, platformMode: true)
        await model.initialize(); let track = try XCTUnwrap(model.tracks.first)
        try await library.record(track, variant: "full", audible: 10, position: 10, eventID: UUID().uuidString, scope: .guest)
        await model.refreshLibrary(); await model.toggleFavorite(track)
        let earlier = model.recent
        XCTAssertEqual(earlier.count, 1)
        model.selectPlatformTrack(track); try await wait { model.platformVisits.count == 1 }
        await model.clearBrowsingHistory()
        XCTAssertTrue(model.platformVisits.isEmpty); XCTAssertEqual(model.favorites, [track.id])
        XCTAssertEqual(model.recent, earlier)
        await model.refreshLibrary(); XCTAssertEqual(model.recent, earlier)
    }
}
