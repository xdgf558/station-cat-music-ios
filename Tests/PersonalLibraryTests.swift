import XCTest
@testable import StationCatMusic

private actor LibraryServer: LibraryRemote {
    var values: [AccountScope: LibrarySnapshot] = [:]
    var calls: [LibraryOperation] = []
    var seen = Set<String>()
    var failAfterCommit = false
    var conflict = false
    var delay: Duration = .zero
    func configure(failAfterCommit: Bool = false, conflict: Bool = false, delay: Duration = .zero) { self.failAfterCommit = failAfterCommit; self.conflict = conflict; self.delay = delay }
    func snapshot(scope: AccountScope) async throws -> LibrarySnapshot { try await Task.sleep(for: delay); return values[scope] ?? .init(favorites: [], recent: [], preferences: .init()) }
    func apply(_ op: LibraryOperation, scope: AccountScope) async throws {
        calls.append(op); try await Task.sleep(for: delay)
        if conflict { throw APIError.rejected(409) }
        if seen.insert(op.id).inserted {
            var value = values[scope] ?? .init(favorites: [], recent: [], preferences: .init())
            switch op.kind {
            case .favorite: value.favorites.removeAll { $0.trackId == op.trackID }; value.favorites.append(.init(trackId: op.trackID!, favorite: op.value!, version: op.version! + 1, updatedAt: Date()))
            case .preference: value.preferences.historyEnabled = op.value!; value.preferences.version += 1; value.preferences.historyEpoch += 1
            case .clear: value.recent = []; value.preferences.version += 1; value.preferences.historyEpoch += 1
            case .listen:
                guard op.epoch == value.preferences.historyEpoch && value.preferences.historyEnabled else { throw APIError.rejected(409) }
                value.recent = [.init(trackId: op.trackID!, lastPlayedAt: op.created, positionSeconds: op.position!)]
            }
            values[scope] = value
        }
        if failAfterCommit { failAfterCommit = false; throw APIError.unavailable }
    }
}
@MainActor final class PersonalLibraryTests: XCTestCase {
    let a = AccountScope(environment: .development, accountID: "1")
    let b = AccountScope(environment: .development, accountID: "2")
    let track = Track(id: "00000000-0000-4000-8000-000000000001", title: "Test", artist: "Test", durationSeconds: 60, audioVersion: 1, access: .free)
    func directory() throws -> URL { let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url }
    func testRelaunchPreservesScopedGuestFavoritesAndPendingOperations() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let library = ScopedLibrary(directory: dir)
        try await library.setFavorite("guest", value: true, scope: .guest)
        try await library.setFavorite(track.id, value: true, scope: a)
        let reopened = ScopedLibrary(directory: dir)
        let guest = try await reopened.view(in: .guest), member = try await reopened.view(in: a), other = try await reopened.view(in: b)
        XCTAssertEqual(guest.favorites, ["guest"]); XCTAssertEqual(guest.pending, 0)
        XCTAssertEqual(member.favorites, [track.id]); XCTAssertEqual(member.pending, 1); XCTAssertTrue(other.favorites.isEmpty)
    }
    func testUnknownCommitOutcomeReusesPersistedMutationIDAfterRelaunch() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let remote = LibraryServer(), library = ScopedLibrary(directory: dir)
        try await library.setFavorite(track.id, value: true, scope: a)
        await remote.configure(failAfterCommit: true)
        do { try await library.synchronize(scope: a, remote: remote); XCTFail() } catch {}
        let reopened = ScopedLibrary(directory: dir); try await reopened.synchronize(scope: a, remote: remote)
        let calls = await remote.calls, value = try await reopened.view(in: a)
        XCTAssertEqual(calls.count, 2); XCTAssertEqual(calls[0].id, calls[1].id); XCTAssertEqual(value.pending, 0); XCTAssertEqual(value.favorites, [track.id])
    }
    func testConflictDoesNotOverwriteServerOrLoop() async throws {
        let library = ScopedLibrary(), remote = LibraryServer(); await remote.configure(conflict: true)
        try await library.setFavorite(track.id, value: true, scope: a)
        try await library.setFavorite(track.id, value: false, scope: a)
        try await library.synchronize(scope: a, remote: remote)
        let calls = await remote.calls, value = try await library.view(in: a)
        XCTAssertEqual(calls.count, 1); XCTAssertEqual(value.pending, 0); XCTAssertTrue(value.conflict); XCTAssertTrue(value.favorites.isEmpty)
    }
    func testDisableOfflineCancelsListensAndStaysLocallyOffOnConflict() async throws {
        let library = ScopedLibrary(), remote = LibraryServer(); await remote.configure(conflict: true)
        try await library.record(track, variant: "full", audible: 5, position: 5, eventID: UUID().uuidString, scope: a)
        try await library.setHistory(false, scope: a)
        try await library.synchronize(scope: a, remote: remote)
        try await library.record(track, variant: "full", audible: 6, position: 6, eventID: UUID().uuidString, scope: a)
        let calls = await remote.calls, value = try await library.view(in: a)
        XCTAssertEqual(calls.map(\.kind), [.preference]); XCTAssertFalse(value.historyEnabled); XCTAssertEqual(value.pending, 0)
    }
    func testClearHistoryDoesNotUploadQueuedOldListen() async throws {
        let library = ScopedLibrary(), remote = LibraryServer()
        try await library.record(track, variant: "full", audible: 5, position: 5, eventID: UUID().uuidString, scope: a)
        try await library.clearHistory(scope: a)
        try await library.synchronize(scope: a, remote: remote)
        let calls = await remote.calls, value = try await library.view(in: a)
        XCTAssertEqual(calls.map(\.kind), [.clear]); XCTAssertTrue(value.recent.isEmpty)
    }
    func testLocalWriteFailureDoesNotPublishFavorite() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let invalid = dir.appending(path: "file"); try Data().write(to: invalid)
        let library = ScopedLibrary(directory: invalid)
        do { try await library.setFavorite(track.id, value: true, scope: a); XCTFail() } catch {}
        let value = try await library.view(in: a); XCTAssertTrue(value.favorites.isEmpty)
    }
    func testCorruptedFileFailsClosedWithoutOverwriting() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let library = ScopedLibrary(directory: dir); try await library.setFavorite(track.id, value: true, scope: a)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first)
        try Data("broken".utf8).write(to: file)
        do { _ = try await ScopedLibrary(directory: dir).view(in: a); XCTFail() } catch {}
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "broken")
    }
    func testEditsArrivingDuringSnapshotArePreserved() async throws {
        let library = ScopedLibrary(), remote = LibraryServer(); await remote.configure(delay: .milliseconds(50))
        let work = Task { try await library.synchronize(scope: a, remote: remote) }
        try await Task.sleep(for: .milliseconds(10)); try await library.setFavorite(track.id, value: true, scope: a)
        try await work.value
        let value = try await library.view(in: a); XCTAssertEqual(value.favorites, [track.id]); XCTAssertEqual(value.pending, 1)
    }
    func testRecentUsesItsOwnQueueSnapshot() async throws {
        let model = AppModel(client: APIClient(environment: .mock, transport: MockTransport(data: Data())))
        let other = Track(id: "other", title: "Other", artist: "Test", durationSeconds: 60, audioVersion: 1, access: .free)
        model.tracks = [other, track]; model.query = "Other"
        try await model.library.record(track, variant: "full", audible: 5, position: 5, eventID: UUID().uuidString, scope: .guest)
        await model.refreshLibrary(); model.select(track, from: model.recentTracks)
        XCTAssertEqual(model.playback.queue.entries.map { $0.track.id }, [track.id])
    }
    func testAudibleMeterRejectsSeekPauseAndLoadingAndCountsOnce() {
        var meter = AudibleListenMeter()
        XCTAssertFalse(meter.sample(wall: 0, media: 0, playing: true))
        XCTAssertFalse(meter.sample(wall: 0.2, media: 30, playing: true))
        XCTAssertFalse(meter.sample(wall: 10, media: 30, playing: false))
        var events = 0
        for i in 0...35 { if meter.sample(wall: 11 + Double(i) * 0.2, media: 30 + Double(i) * 0.2, playing: true) { events += 1 } }
        XCTAssertEqual(events, 1); XCTAssertGreaterThanOrEqual(meter.seconds, 5)
    }
    func testExpiredOfflineMutationIsNotReplayed() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let library = ScopedLibrary(directory: dir), remote = LibraryServer()
        try await library.setFavorite(track.id, value: true, scope: a)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first)
        var value = try JSONDecoder().decode(LibraryFile.self, from: Data(contentsOf: file))
        value.operations = [.init(id: UUID().uuidString, created: Date().addingTimeInterval(-31 * 86400), kind: .favorite, trackID: track.id, value: true, version: 0)]
        try JSONEncoder().encode(value).write(to: file, options: .atomic)
        let reopened = ScopedLibrary(directory: dir); try await reopened.synchronize(scope: a, remote: remote)
        let calls = await remote.calls, current = try await reopened.view(in: a)
        XCTAssertTrue(calls.isEmpty); XCTAssertTrue(current.conflict); XCTAssertTrue(current.favorites.isEmpty)
    }
    func testAccountChangeCancelsOldSyncAndCannotPopulateNewAccount() async throws {
        let remote = LibraryServer(); await remote.configure(delay: .milliseconds(150))
        let model = AppModel(client: APIClient(environment: .mock, transport: MockTransport(data: Data())), libraryRemote: remote, environment: .development)
        await model.changeScope(a); await model.toggleFavorite(track)
        await model.changeScope(b); try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(model.scope, b); XCTAssertTrue(model.favorites.isEmpty); XCTAssertTrue(model.recent.isEmpty)
    }
    func testCacheClearPreservesFavoritesAndHistoryPreference() async throws {
        let envelope = APIEnvelope(data: Catalog(items: [track], nextCursor: nil), requestId: "fixture", serverNow: "2026-09-19T00:00:00Z")
        let model = AppModel(client: APIClient(environment: .mock, transport: MockTransport(data: try JSONEncoder().encode(envelope))))
        await model.toggleFavorite(track); await model.setHistory(false); await model.clearCache(); await model.refreshLibrary()
        XCTAssertEqual(model.favorites, [track.id]); XCTAssertFalse(model.historyEnabled)
    }
    func testAudibleEventStartsSyncWithoutLeavingForeground() async throws {
        let remote = LibraryServer()
        let model = AppModel(client: APIClient(environment: .mock, transport: MockTransport(data: Data())), libraryRemote: remote, environment: .development)
        await model.changeScope(a)
        for _ in 0..<100 { if !model.libraryBusy { break }; try await Task.sleep(for: .milliseconds(10)) }
        let id = UUID().uuidString
        model.playback.onListen?(track, "full", 5.1, 5.1, id)
        for _ in 0..<100 { if await remote.calls.contains(where: { $0.id == id }) { break }; try await Task.sleep(for: .milliseconds(10)) }
        let calls = await remote.calls
        XCTAssertEqual(calls.filter { $0.id == id }.count, 1)
        XCTAssertEqual(calls.last?.kind, .listen)
    }
    func testShortListenNeverEntersHistory() async throws {
        let library = ScopedLibrary(); try await library.record(track, variant: "preview", audible: 4.99, position: 55, eventID: UUID().uuidString, scope: .guest)
        let value = try await library.view(in: .guest); XCTAssertTrue(value.recent.isEmpty)
    }
}
