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
    func apply(_ op: LibraryOperation, scope: AccountScope) async throws -> LibraryPreferences? {
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
        return op.kind == .preference || op.kind == .clear ? values[scope]?.preferences : nil
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
        try await library.synchronize(scope: a, remote: LibraryServer())
        try await library.record(track, variant: "full", audible: 5, position: 5, eventID: UUID().uuidString, scope: a)
        try await library.setHistory(false, scope: a)
        try await library.synchronize(scope: a, remote: remote)
        try await library.record(track, variant: "full", audible: 6, position: 6, eventID: UUID().uuidString, scope: a)
        let calls = await remote.calls, value = try await library.view(in: a)
        XCTAssertEqual(calls.map(\.kind), [.preference]); XCTAssertFalse(value.historyEnabled); XCTAssertEqual(value.pending, 1)
    }
    func testClearHistoryDoesNotUploadQueuedOldListen() async throws {
        let library = ScopedLibrary(), remote = LibraryServer()
        try await library.synchronize(scope: a, remote: LibraryServer())
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
        try await library.synchronize(scope: a, remote: LibraryServer())
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

private actor HeldLibraryServer: LibraryRemote {
    enum Mode { case listen, snapshot }
    let mode: Mode
    var value: LibrarySnapshot
    var calls: [LibraryOperation.Kind] = []
    private var held = false
    private var used = false
    private var started: [CheckedContinuation<Void, Never>] = []
    private var release: CheckedContinuation<Void, Error>?
    init(mode: Mode, recent: [LibraryRecent]) { self.mode = mode; value = .init(favorites: [], recent: recent, preferences: .init()) }
    func waitUntilHeld() async { if held { return }; await withCheckedContinuation { started.append($0) } }
    private func hold() async throws {
        try await withCheckedThrowingContinuation { continuation in
            release = continuation; held = true; started.forEach { $0.resume() }; started = []
        }
    }
    func finish(code: Int? = nil) { if let code { release?.resume(throwing: APIError.rejected(code)) } else { release?.resume() }; release = nil }
    func apply(_ op: LibraryOperation, scope: AccountScope) async throws -> LibraryPreferences? {
        calls.append(op.kind)
        if mode == .listen && !used { used = true; try await hold() }
        if op.kind == .clear { value.recent = []; value.preferences.historyEpoch += 1; value.preferences.version += 1 }
        if op.kind == .preference { value.preferences.historyEnabled = op.value!; value.preferences.historyEpoch += 1; value.preferences.version += 1 }
        return op.kind == .preference || op.kind == .clear ? value.preferences : nil
    }
    func snapshot(scope: AccountScope) async throws -> LibrarySnapshot {
        let captured = value
        if mode == .snapshot && !used { used = true; try await hold() }
        return captured
    }
}

extension PersonalLibraryTests {
    func testLateRejectedListenCannotEatNewClearOrDisable() async throws {
        for code in [404, 409] {
            for clear in [true, false] {
                let old = LibraryRecent(trackId: track.id, lastPlayedAt: Date().addingTimeInterval(-60), positionSeconds: 40)
                let remote = HeldLibraryServer(mode: .listen, recent: [old]), library = ScopedLibrary()
                try await library.synchronize(scope: a, remote: LibraryServer())
                try await library.record(track, variant: "full", audible: 5, position: 5, eventID: UUID().uuidString, scope: a)
                let work = Task { try await library.synchronize(scope: a, remote: remote) }
                await remote.waitUntilHeld()
                if clear { try await library.clearHistory(scope: a) } else { try await library.setHistory(false, scope: a) }
                let before = try await library.view(in: a); XCTAssertEqual(before.pending, 1)
                await remote.finish(code: code); try await work.value
                let after = try await library.view(in: a), calls = await remote.calls, server = await remote.value
                XCTAssertEqual(calls, [.listen, clear ? .clear : .preference]); XCTAssertEqual(after.pending, 0)
                if clear { XCTAssertTrue(after.recent.isEmpty); XCTAssertTrue(server.recent.isEmpty) }
                else { XCTAssertFalse(after.historyEnabled); XCTAssertFalse(server.preferences.historyEnabled) }
            }
        }
    }
    func testSnapshotMergeKeepsNewerLocalPositionAndSortsAndCapsWithoutDroppingUploads() async throws {
        let old = Date().addingTimeInterval(-60)
        var rows = (1...999).map { LibraryRecent(trackId: "old-\($0)", lastPlayedAt: old.addingTimeInterval(-Double($0)), positionSeconds: 5) }
        rows.append(.init(trackId: track.id, lastPlayedAt: old, positionSeconds: 5))
        let library = ScopedLibrary(), remote = HeldLibraryServer(mode: .snapshot, recent: rows)
        try await library.synchronize(scope: a, remote: LibraryServer())
        let work = Task { try await library.synchronize(scope: a, remote: remote) }
        await remote.waitUntilHeld()
        try await library.record(track, variant: "full", audible: 40, position: 40, eventID: UUID().uuidString, scope: a)
        let newer = Track(id: "new", title: "New", artist: "Test", durationSeconds: 60, audioVersion: 1, access: .free)
        try await library.record(newer, variant: "full", audible: 5, position: 5, eventID: UUID().uuidString, scope: a)
        await remote.finish(); try await work.value
        let after = try await library.view(in: a)
        XCTAssertEqual(after.recent.count, 1000); XCTAssertEqual(after.pending, 2)
        XCTAssertEqual(after.recent.first?.trackId, newer.id)
        XCTAssertEqual(after.recent.first(where: { $0.trackId == track.id })?.positionSeconds, 40)
        XCTAssertGreaterThan(try XCTUnwrap(after.recent.first(where: { $0.trackId == track.id })?.lastPlayedAt), old)
        XCTAssertFalse(after.recent.contains(where: { $0.trackId == "old-999" }))
    }
    func testTransientContentionKeepsDurableFavoriteForRetry() async throws {
        struct Busy: LibraryRemote {
            func apply(_ op: LibraryOperation, scope: AccountScope) throws -> LibraryPreferences? { throw APIError.rejected(503) }
            func snapshot(scope: AccountScope) throws -> LibrarySnapshot { throw APIError.unavailable }
        }
        let library = ScopedLibrary(); try await library.setFavorite(track.id, value: true, scope: a)
        do { try await library.synchronize(scope: a, remote: Busy()); XCTFail() } catch {}
        let after = try await library.view(in: a)
        XCTAssertEqual(after.pending, 1); XCTAssertEqual(after.favorites, [track.id]); XCTAssertFalse(after.conflict)
    }
}

// Matches the server's CAS, epoch, and immutable idempotent privacy receipts.
private actor PrivacyCASServer: LibraryRemote {
    var prefs = LibraryPreferences()
    var recent: [LibraryRecent] = []
    var calls: [LibraryOperation] = []
    var receipts: [String: LibraryPreferences] = [:]
    var loseNextReceipt = false
    var failAfterConflict = false
    private var snapshotFailure = false
    func loseReceipt() { loseNextReceipt = true }
    func failConflictSnapshot() { failAfterConflict = true }
    func otherDeviceClears() { prefs.version += 1; prefs.historyEpoch += 1; recent = [] }
    func snapshot(scope: AccountScope) throws -> LibrarySnapshot {
        if snapshotFailure { snapshotFailure = false; throw APIError.unavailable }
        return .init(favorites: [], recent: recent, preferences: prefs)
    }
    func apply(_ op: LibraryOperation, scope: AccountScope) throws -> LibraryPreferences? {
        calls.append(op)
        if let receipt = receipts[op.id] { return receipt }
        if op.kind == .preference || op.kind == .clear {
            guard op.kind == .clear ? op.epoch == prefs.historyEpoch : op.version == prefs.version else {
                snapshotFailure = failAfterConflict; throw APIError.rejected(409)
            }
            if op.kind == .clear { recent = [] } else { prefs.historyEnabled = op.value! }
            prefs.version += 1; prefs.historyEpoch += 1; receipts[op.id] = prefs
            if loseNextReceipt { loseNextReceipt = false; throw APIError.unavailable }
            return prefs
        }
        if op.kind == .listen {
            guard prefs.historyEnabled, op.epoch == prefs.historyEpoch else { throw APIError.rejected(409) }
            recent = [.init(trackId: op.trackID!, lastPlayedAt: op.created, positionSeconds: op.position!)]
        }
        return nil
    }
}

extension PersonalLibraryTests {
    func testPrivacyConflictCannotResurrectEventsAcrossReopenEvenWhenSnapshotFails() async throws {
        for restart in [false, true] {
            for snapshotFailure in [false, true] {
                let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
                let remote = PrivacyCASServer(), library = ScopedLibrary(directory: dir)
                try await library.synchronize(scope: a, remote: remote)
                try await library.setHistory(false, scope: a); try await library.setHistory(true, scope: a)
                try await library.record(track, variant: "full", audible: 5, position: 5, eventID: UUID().uuidString, scope: a)
                let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first)
                let queued = try JSONDecoder().decode(LibraryFile.self, from: Data(contentsOf: file))
                XCTAssertEqual(queued.confirmedPreferences?.historyEpoch, 0)
                XCTAssertEqual(queued.operations.count, 3)
                XCTAssertNil(queued.operations[1].version); XCTAssertNil(queued.operations[2].epoch)
                XCTAssertEqual(queued.operations[1].privacyDependency, queued.operations[0].id)
                XCTAssertEqual(queued.operations[2].privacyDependency, queued.operations[1].id)
                await remote.otherDeviceClears()
                if snapshotFailure { await remote.failConflictSnapshot() }
                do { try await library.synchronize(scope: a, remote: remote); XCTAssertFalse(snapshotFailure) }
                catch { XCTAssertTrue(snapshotFailure) }
                let persisted = try JSONDecoder().decode(LibraryFile.self, from: Data(contentsOf: file))
                XCTAssertFalse(persisted.operations.contains { $0.kind == .listen || ($0.kind == .preference && $0.value == true) })
                XCTAssertEqual(persisted.operations.count, 1) // Restrictive intent remains, with a new ID.
                XCTAssertNotEqual(persisted.operations[0].id, queued.operations[0].id)
                let resumed = restart ? ScopedLibrary(directory: dir) : library
                try await resumed.synchronize(scope: a, remote: remote)
                let calls = await remote.calls, rows = await remote.recent, value = try await resumed.view(in: a)
                XCTAssertTrue(rows.isEmpty); XCTAssertTrue(value.recent.isEmpty); XCTAssertEqual(value.pending, 0)
                XCTAssertFalse(calls.contains { $0.kind == .listen || ($0.kind == .preference && $0.value == true) })
                XCTAssertFalse(value.historyEnabled)
            }
        }
    }
    func testAcknowledgedPrivacyChainReplaysSamePayloadAfterLostReceiptAndReopen() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let remote = PrivacyCASServer(), library = ScopedLibrary(directory: dir)
        try await library.synchronize(scope: a, remote: remote)
        try await library.setHistory(false, scope: a); try await library.setHistory(true, scope: a)
        try await library.record(track, variant: "full", audible: 5, position: 5, eventID: UUID().uuidString, scope: a)
        await remote.loseReceipt()
        do { try await library.synchronize(scope: a, remote: remote); XCTFail() } catch {}
        let reopened = ScopedLibrary(directory: dir); try await reopened.synchronize(scope: a, remote: remote)
        let calls = await remote.calls, rows = await remote.recent
        XCTAssertEqual(calls.count, 4); XCTAssertEqual(calls[0], calls[1])
        XCTAssertEqual(calls[2].version, 1); XCTAssertNil(calls[2].privacyDependency)
        XCTAssertEqual(calls[3].epoch, 2); XCTAssertNil(calls[3].privacyDependency)
        XCTAssertEqual(rows.count, 1)
    }
    func testLaterRestrictiveCommandsSurviveFailedPrivacyAncestor() async throws {
        let remote = PrivacyCASServer(), library = ScopedLibrary()
        try await library.synchronize(scope: a, remote: remote)
        try await library.setHistory(false, scope: a); try await library.setHistory(true, scope: a)
        try await library.clearHistory(scope: a); try await library.setHistory(false, scope: a)
        await remote.otherDeviceClears()
        try await library.synchronize(scope: a, remote: remote)
        let first = try await library.view(in: a); XCTAssertEqual(first.pending, 3)
        try await library.synchronize(scope: a, remote: remote)
        let calls = await remote.calls, prefs = await remote.prefs
        XCTAssertEqual(calls.map(\.kind), [.preference, .preference, .clear, .preference])
        XCTAssertFalse(calls.contains { $0.value == true }); XCTAssertFalse(prefs.historyEnabled)
    }
    func testLegacyJournalCannotReplayUnprovenPrivacyLineage() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let library = ScopedLibrary(directory: dir); try await library.setFavorite(track.id, value: true, scope: a)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first)
        var legacy = try JSONDecoder().decode(LibraryFile.self, from: Data(contentsOf: file))
        legacy.schema = 1; legacy.preferences.historyEpoch = 2; legacy.preferences.version = 2
        legacy.operations = [
            .init(id: UUID().uuidString, created: Date(), kind: .preference, value: true, version: 1),
            .init(id: UUID().uuidString, created: Date(), kind: .listen, trackID: track.id, epoch: 2, audioVersion: 1, variant: "full", audibleSeconds: 5, position: 5),
            .init(id: UUID().uuidString, created: Date(), kind: .clear, epoch: 2)]
        try JSONEncoder().encode(legacy).write(to: file, options: .atomic)
        let reopened = ScopedLibrary(directory: dir), remote = PrivacyCASServer()
        await remote.otherDeviceClears(); await remote.otherDeviceClears()
        try await reopened.synchronize(scope: a, remote: remote)
        let calls = await remote.calls, migrated = try JSONDecoder().decode(LibraryFile.self, from: Data(contentsOf: file))
        XCTAssertEqual(calls.map(\.kind), [.clear]); XCTAssertEqual(migrated.schema, 2)
        XCTAssertTrue(migrated.historyBlockedLocally)
        XCTAssertNotEqual(calls.first?.id, legacy.operations.last?.id)
    }
    func testNoAccountHistoryUploadsBeforeConfirmedBaseline() async throws {
        let library = ScopedLibrary()
        try await library.setHistory(false, scope: a); try await library.setHistory(true, scope: a)
        try await library.record(track, variant: "full", audible: 5, position: 5, eventID: UUID().uuidString, scope: a)
        let value = try await library.view(in: a); XCTAssertEqual(value.pending, 2); XCTAssertTrue(value.recent.isEmpty)
    }
}
