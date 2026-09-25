import XCTest
import CryptoKit
@testable import StationCatMusic

private actor OfflineFixture: OfflineMusicProviding, MediaHTTPTransport {
    let track: Track
    let data: Data
    var grants = 0
    var ranges = 0
    var permissions = 0
    var network = true
    var corrupt = false
    var withdrawn = false
    var delay = Duration.zero
    init(_ data: Data, id: String = UUID().uuidString) {
        self.data = data
        track = Track(id: id, title: "Synthetic test audio", artist: "Fixture", durationSeconds: 4.049, audioVersion: 1, access: .free, offlineEligible: true)
    }
    func setNetwork(_ value: Bool) { network = value }
    func setCorrupt() { corrupt = true }
    func setDelay() { delay = .milliseconds(500) }
    func withdraw() { withdrawn = true }
    func offlinePermission(for track: Track) throws -> OfflinePermission {
        guard network, !withdrawn else { throw APIError.rejected(403) }; permissions += 1
        let now = Date()
        return OfflinePermission(permit: OfflinePermit(trackId: track.id, audioVersion: track.audioVersion, policyVersion: 1, accessMode: "free", variant: "full", byteSize: data.count,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), durationSeconds: track.durationSeconds, validUntil: now.addingTimeInterval(7 * 86400)), serverNow: now, requestSeconds: 0)
    }
    func authorize(track: Track, variant: String) throws -> AuthorizedPlayback {
        guard network else { throw URLError(.notConnectedToInternet) }; grants += 1
        let now = Date(), end = now.addingTimeInterval(90)
        return AuthorizedPlayback(grant: PlaybackGrant(playbackUrl: URL(string: "https://offline.test/api/mobile/v1/music/media/" + String(repeating: "a", count: 43) + "/audio")!, expiresAt: end, playbackValidUntil: end, revalidateAt: end,
            durationSeconds: track.durationSeconds, previewSourceStartSeconds: nil, authMode: .publicAccess, accountID: nil, sessionID: nil, trackID: track.id, audioVersion: track.audioVersion, variant: variant), serverNow: now, context: nil, scope: .guest)
    }
    func isCurrent(_ authorization: AuthorizedPlayback) -> Bool { true }
    func bearer(for authorization: AuthorizedPlayback, refresh: Bool) -> String? { nil }
    func send(_ request: URLRequest) async throws -> MediaHTTPResult {
        guard network else { throw URLError(.notConnectedToInternet) }
        ranges += 1
        try await Task.sleep(for: delay)
        let range = request.value(forHTTPHeaderField: "Range")!.dropFirst(6).split(separator: "-").compactMap { Int($0) }
        let first = range[0], last = min(range[1], data.count - 1)
        var bytes = data.subdata(in: first..<(last + 1))
        if corrupt { bytes[0] ^= 1 }
        return MediaHTTPResult(status: 206, data: bytes, headers: ["content-type":"audio/mpeg", "etag":"synthetic", "content-length":String(bytes.count), "content-range":"bytes \(first)-\(last)/\(data.count)"])
    }
}
private actor SealBarrier {
    var reached = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async { reached = true; await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}
private struct OfflineCatalog: CatalogProviding {
    let items: [Track]
    func catalog() async throws -> Catalog { Catalog(items: items, nextCursor: nil) }
}
private final class RemovalObserver: @unchecked Sendable {
    let player: PlaybackService
    init(_ player: PlaybackService) { self.player = player }
    func remove(_ url: URL) throws {
        let stopped = DispatchQueue.main.sync { !self.player.hasAudioSource }
        guard stopped else { throw APIError.invalidPayload }
        try FileManager.default.removeItem(at: url)
    }
}
@MainActor final class OfflineMusicTests: XCTestCase {
    private func fixture() throws -> OfflineFixture {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "SyntheticAudio", withExtension: "mp3"))
        return OfflineFixture(try Data(contentsOf: url))
    }
    private func root() -> URL { FileManager.default.temporaryDirectory.appending(path: "offline-test-" + UUID().uuidString) }
    private let origin = URL(string: "https://offline.test")!
    private func wait(_ check: () -> Bool) async throws {
        for _ in 0..<100 { if check() { return }; try await Task.sleep(for: .milliseconds(50)) }
        XCTFail("Player did not reach expected state")
    }
    func testExpiredRollbackAndDamagedSavesRemainVisibleAndIndividuallyRemovable() async throws {
        let base = root(), source = try fixture(), track = await source.track
        defer { try? FileManager.default.removeItem(at: base) }
        let cache = OfflineMusicCache(origin: origin, baseDirectory: base, transport: source)
        try await cache.download(track, source: source)
        for now in [Date().addingTimeInterval(8 * 86400), Date().addingTimeInterval(-60)] {
            let listed = try await cache.songs(now: now)
            XCTAssertEqual(listed.map(\.id), [track.id]); XCTAssertEqual(listed.first?.unavailable, true)
        }
        let local = try await cache.playable(track)
        let file = try XCTUnwrap(local?.url)
        try Data([0]).write(to: file)
        let damaged = try await cache.songs()
        XCTAssertEqual(damaged.first?.unavailable, true)
        try await cache.remove(track.id)
        let remaining = try await cache.usage(); XCTAssertEqual(remaining, 0)
        try await cache.download(track, source: source)
        let restored = try await cache.playable(track); XCTAssertNotNil(restored)
    }
    func testRepeatedResumeDoesNotRehashUnchangedFileButChangedBytesAreRejected() async throws {
        let base = root(), source = try fixture(), track = await source.track
        defer { try? FileManager.default.removeItem(at: base) }
        let cache = OfflineMusicCache(origin: origin, baseDirectory: base, transport: source)
        try await cache.download(track, source: source)
        let reopened = OfflineMusicCache(origin: origin, baseDirectory: base, transport: source)
        let initial = try await reopened.playable(track)
        for _ in 0..<10 { let value = try await reopened.playable(track); XCTAssertNotNil(value) }
        let checks = await reopened.integrityChecks; XCTAssertEqual(checks, 1)
        let file = try XCTUnwrap(initial?.url)
        var bytes = try Data(contentsOf: file); bytes[0] ^= 1; try bytes.write(to: file, options: .atomic)
        let rejected = try await reopened.playable(track); XCTAssertNil(rejected)
        let listed = try await reopened.songs(); XCTAssertEqual(listed.first?.unavailable, true)
    }
    func testReplacementFailurePreservesPreviousPlayableCopyAndRetryReplacesIt() async throws {
        let base = root(), source = try fixture(), track = await source.track
        defer { try? FileManager.default.removeItem(at: base) }
        let cache = OfflineMusicCache(origin: origin, baseDirectory: base, transport: source)
        try await cache.download(track, source: source)
        let first = try await cache.playable(track), url = try XCTUnwrap(first?.url)
        let receipt = url.deletingLastPathComponent().appending(path: "receipt.json")
        let before = try Data(contentsOf: receipt)
        let failed = OfflineMusicCache(origin: origin, baseDirectory: base, transport: source, publishFiles: { temporary, destination in
            // Exercise the real safe-replace error with a missing staged item.
            try FileManager.default.removeItem(at: temporary)
            try OfflineMusicCache.publish(temporary, destination)
        })
        do { try await failed.download(track, source: source); XCTFail() } catch {}
        XCTAssertEqual(try Data(contentsOf: receipt), before)
        let retained = try await cache.playable(track); XCTAssertNotNil(retained)
        try await cache.download(track, source: source)
        XCTAssertNotEqual(try Data(contentsOf: receipt), before)
        let replaced = try await cache.playable(track); XCTAssertNotNil(replaced)
    }
    func testCancellationAfterFilesWrittenCannotPublishEvenWithoutTaskCancellation() async throws {
        let base = root(), source = try fixture(), track = await source.track, barrier = SealBarrier()
        defer { try? FileManager.default.removeItem(at: base) }
        let cache = OfflineMusicCache(origin: origin, baseDirectory: base, transport: source, beforePublication: { await barrier.wait() })
        let ticket = OfflineDownloadTicket()
        let task = Task { try await cache.download(track, source: source, cancellation: ticket) }
        while !(await barrier.reached) { await Task.yield() }
        ticket.cancel(); await barrier.release()
        do { try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        let saved = try await cache.songs(); XCTAssertTrue(saved.isEmpty)
    }
    func testReconcilePartialFailureRetainsBothRemovedAndFailedResults() async throws {
        let base = root(), source = try fixture(), other = try fixture(), track = await source.track, second = await other.track
        defer { try? FileManager.default.removeItem(at: base) }
        let cache = OfflineMusicCache(origin: origin, baseDirectory: base, transport: source)
        try await cache.download(track, source: source); try await cache.download(second, source: other)
        let secondFile = try await cache.playable(second), blocked = try XCTUnwrap(secondFile?.url.deletingLastPathComponent())
        let failing = OfflineMusicCache(origin: origin, baseDirectory: base, transport: source, removeFiles: { url in
            if url.lastPathComponent == blocked.lastPathComponent { throw APIError.storageUnavailable }; try FileManager.default.removeItem(at: url)
        })
        let candidates = try await failing.reconciliationCandidates([])
        let result = await failing.removeInvalidated(candidates)
        XCTAssertEqual(result.removed, [track.id]); XCTAssertEqual(result.failed, [second.id])
        let saved = try await failing.songs(); XCTAssertEqual(saved.map(\.id), [second.id]); XCTAssertEqual(saved.first?.unavailable, true)
        let denied = try await failing.playable(second); XCTAssertNil(denied)
    }
    func testCatalogRevocationReleasesAVPlayerBeforeRemovingFile() async throws {
        let base = root(), source = try fixture(), track = await source.track
        defer { try? FileManager.default.removeItem(at: base) }
        let player = PlaybackService(transport: source), observer = RemovalObserver(player)
        defer { player.shutdown() }
        let cache = OfflineMusicCache(origin: origin, baseDirectory: base, transport: source, removeFiles: { try observer.remove($0) })
        try await cache.download(track, source: source)
        let model = AppModel(client: OfflineCatalog(items: []), playback: player, offlineStorage: cache)
        player.configure(authorizer: source); player.select(track); player.requestPlay()
        try await wait { player.isOfflinePlayback && player.position > 0.1 }
        await model.load()
        XCTAssertFalse(player.hasAudioSource); XCTAssertEqual(player.state, .verificationRequired)
        XCTAssertEqual(model.offlineBytes, 0); XCTAssertTrue(model.offlineSongs.isEmpty)
    }
    func testFullBudgetExpiredSaveCanBeRemovedWithoutClearingOtherSavedSongs() async throws {
        let base = root(), source = try fixture(), other = try fixture(), track = await source.track, second = await other.track
        defer { try? FileManager.default.removeItem(at: base) }
        let bytes = await source.data.count
        let cache = OfflineMusicCache(origin: origin, baseDirectory: base, capacity: bytes + 32768, transport: source)
        try await cache.download(track, source: source)
        let first = try await cache.playable(track), url = try XCTUnwrap(first?.url)
        let receipt = url.deletingLastPathComponent().appending(path: "receipt.json")
        let saved = try JSONDecoder().decode(OfflineSong.self, from: Data(contentsOf: receipt))
        let expired = OfflineSong(track: saved.track, permit: saved.permit, savedAt: Date().addingTimeInterval(-8 * 86400), expiresAt: Date().addingTimeInterval(-86400))
        try JSONEncoder().encode(expired).write(to: receipt, options: .atomic)
        do { try await cache.download(second, source: other); XCTFail() } catch { XCTAssertEqual(error as? APIError, .storageUnavailable) }
        let listed = try await cache.songs(); XCTAssertEqual(listed.first?.id, track.id); XCTAssertEqual(listed.first?.unavailable, true)
        try await cache.remove(track.id)
        try await cache.download(second, source: other)
        let new = try await cache.playable(second); XCTAssertNotNil(new)
    }
    func testCompleteVerifiedFileReopensAndPlaysWithAllNetworkingDisabled() async throws {
        let base = root(), source = try fixture(), track = await source.track
        defer { try? FileManager.default.removeItem(at: base) }
        let cache = OfflineMusicCache(origin: origin, baseDirectory: base, transport: source)
        try await cache.download(track, source: source)
        let reopened = OfflineMusicCache(origin: origin, baseDirectory: base, transport: source)
        let songs = try await reopened.songs(); XCTAssertEqual(songs.map(\.id), [track.id])
        let before = await source.ranges, permits = await source.permissions, grants = await source.grants
        XCTAssertEqual(permits, 2); XCTAssertEqual(grants, 1)
        await source.setNetwork(false)
        let player = PlaybackService(transport: source); player.configure(authorizer: source); player.offlineCache = reopened
        defer { player.shutdown() }
        player.select(track); player.requestPlay()
        try await wait { player.position > 0.3 }
        XCTAssertTrue(player.isOfflinePlayback); XCTAssertTrue(player.isPlaying)
        player.seek(to: 1.4); try await wait { player.position > 1.6 }
        player.pause(); let paused = player.position
        player.requestPlay(); try await wait { player.position > paused + 0.1 }
        XCTAssertGreaterThan(player.position, paused); XCTAssertTrue(player.isOfflinePlayback)
        player.deny(); let interrupted = player.position
        player.requestPlay(); try await wait { player.position > interrupted + 0.1 }
        XCTAssertTrue(player.isOfflinePlayback)
        try await wait { player.state == .completed }
        XCTAssertEqual(player.position, 0)
        player.requestPlay(); try await wait { player.position > 0.2 }
        XCTAssertLessThan(player.position, 1); XCTAssertTrue(player.isOfflinePlayback)
        let after = await source.ranges, afterGrants = await source.grants
        XCTAssertEqual(before, after); XCTAssertEqual(afterGrants, grants)
    }
    func testOfflineLeaseExpiryStopsBufferedPlayback() async throws {
        let base = root(), source = try fixture(), track = await source.track
        defer { try? FileManager.default.removeItem(at: base) }
        let cache = OfflineMusicCache(origin: origin, baseDirectory: base, transport: source)
        try await cache.download(track, source: source)
        let value = try await cache.playable(track), local = try XCTUnwrap(value)
        let short = OfflineSong(track: track, permit: local.song.permit, savedAt: Date(), expiresAt: Date().addingTimeInterval(3))
        try JSONEncoder().encode(short).write(to: local.url.deletingLastPathComponent().appending(path: "receipt.json"), options: .atomic)
        await source.setNetwork(false)
        let player = PlaybackService(transport: source); player.configure(authorizer: source); player.offlineCache = cache
        defer { player.shutdown() }
        player.select(track); player.requestPlay(); try await wait { player.position > 0.1 }
        try await wait { player.state == .verificationRequired }
        XCTAssertFalse(player.hasAudioSource); XCTAssertFalse(player.isPlaying)
    }
    func testOnlineFailureRetainsPositionAndManualResumeSeeksBeforePlaying() async throws {
        let source = try fixture(), track = await source.track
        let player = PlaybackService(transport: source); player.configure(authorizer: source)
        defer { player.shutdown() }
        player.select(track); player.requestPlay(); try await wait { player.position > 1 }
        player.deny(); let stopped = player.position
        XCTAssertGreaterThan(stopped, 0.9)
        await source.setNetwork(false); player.requestPlay(); try await wait { player.state == .verificationRequired }
        XCTAssertEqual(player.position, stopped, accuracy: 0.1); XCTAssertFalse(player.hasAudioSource)
        await source.setNetwork(true); player.requestPlay(); try await wait { player.position > stopped + 0.1 }
        XCTAssertGreaterThan(player.position, stopped); let count = await source.grants; XCTAssertEqual(count, 2)
    }
    func testPolicyEligibilityAndRevisionAreRequiredEvenIfAccessSaysFree() async throws {
        let base = root(), source = try fixture(), track = await source.track
        defer { try? FileManager.default.removeItem(at: base) }
        let cache = OfflineMusicCache(origin: origin, baseDirectory: base, transport: source)
        for eligibility in [nil, false] as [Bool?] {
            var limited = track; limited.offlineEligible = eligibility
            do { try await cache.download(limited, source: source); XCTFail() } catch {}
        }
        try await cache.download(track, source: source)
        let revised = Track(id: track.id, title: track.title, artist: track.artist, durationSeconds: track.durationSeconds, audioVersion: 2, access: .free, offlineEligible: true)
        let missing = try await cache.playable(revised); XCTAssertNil(missing)
        let paid = Track(id: track.id, title: track.title, artist: track.artist, durationSeconds: track.durationSeconds, audioVersion: 1, access: .vip, offlineEligible: false)
        let candidates = try await cache.reconciliationCandidates([paid]); let result = await cache.removeInvalidated(candidates); XCTAssertEqual(result.removed, [track.id])
        let songs = try await cache.songs(); XCTAssertTrue(songs.isEmpty)
    }
    func testIncompleteOrCorruptDownloadNeverAppearsAsOffline() async throws {
        let base = root(), source = try fixture(), track = await source.track
        defer { try? FileManager.default.removeItem(at: base) }
        let cache = OfflineMusicCache(origin: origin, baseDirectory: base, transport: source)
        await source.setCorrupt()
        do { try await cache.download(track, source: source); XCTFail() } catch {}
        let songs = try await cache.songs(), used = try await cache.usage()
        XCTAssertTrue(songs.isEmpty); XCTAssertEqual(used, 0)
    }
    func testDiskCorruptionExpiryClockRollbackAndOriginIsolationFailClosed() async throws {
        let base = root(), source = try fixture(), track = await source.track
        defer { try? FileManager.default.removeItem(at: base) }
        let cache = OfflineMusicCache(origin: origin, baseDirectory: base, transport: source)
        try await cache.download(track, source: source)
        let valid = try await cache.playable(track), local = try XCTUnwrap(valid)
        let expired = try await cache.playable(track, now: Date().addingTimeInterval(7 * 86400 + 1))
        let rollback = try await cache.playable(track, now: Date().addingTimeInterval(-60))
        XCTAssertNil(expired); XCTAssertNil(rollback)
        let other = OfflineMusicCache(origin: URL(string: "https://other.test")!, baseDirectory: base, transport: source)
        let isolated = try await other.playable(track); XCTAssertNil(isolated)
        let bytes = try Data(contentsOf: local.url); var corrupt = bytes; corrupt[0] ^= 1
        try corrupt.write(to: local.url)
        let rejected = try await cache.playable(track); XCTAssertNil(rejected)
        try await cache.clear(); let usage = try await cache.usage(); XCTAssertEqual(usage, 0)
    }
    func testCapacityFailureDoesNotDeleteAnotherDownload() async throws {
        let base = root(), source = try fixture(), track = await source.track
        defer { try? FileManager.default.removeItem(at: base) }
        let cache = OfflineMusicCache(origin: origin, baseDirectory: base, capacity: 1, transport: source)
        do { try await cache.download(track, source: source); XCTFail() } catch { XCTAssertEqual(error as? APIError, .storageUnavailable) }
        let grants = await source.grants; XCTAssertEqual(grants, 0)
    }
    func testClearDuringDownloadCancelsLateCommitAndAllowsRetry() async throws {
        let base = root(), source = try fixture(), track = await source.track
        defer { try? FileManager.default.removeItem(at: base) }
        let cache = OfflineMusicCache(origin: origin, baseDirectory: base, transport: source)
        await source.setDelay()
        let work = Task { try await cache.download(track, source: source) }
        while await source.ranges == 0 { await Task.yield() }
        try await cache.clear()
        do { try await work.value; XCTFail() } catch {}
        let songs = try await cache.songs(); XCTAssertTrue(songs.isEmpty)
        try await cache.download(track, source: source)
        let final = try await cache.songs(); XCTAssertEqual(final.count, 1)
    }
    func testPolicyChangedDuringDownloadCannotSealOldFreeFile() async throws {
        let base = root(), source = try fixture(), track = await source.track
        defer { try? FileManager.default.removeItem(at: base) }
        let cache = OfflineMusicCache(origin: origin, baseDirectory: base, transport: source)
        await source.setDelay()
        let work = Task { try await cache.download(track, source: source) }
        while await source.ranges == 0 { await Task.yield() }
        await source.withdraw()
        do { try await work.value; XCTFail() } catch {}
        let songs = try await cache.songs(); XCTAssertTrue(songs.isEmpty)
    }
}
