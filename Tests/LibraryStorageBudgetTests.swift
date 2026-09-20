import XCTest
@testable import StationCatMusic

@MainActor final class LibraryStorageBudgetTests: XCTestCase {
    let a = AccountScope(environment: .development, accountID: "1")
    let b = AccountScope(environment: .development, accountID: "2")
    func directory() -> URL { FileManager.default.temporaryDirectory.appending(path: UUID().uuidString) }
    func testGlobalBudgetRejectsNewAccountWithoutLosingOfflinePrivacyJournal() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let library = ScopedLibrary(directory: dir)
        try await library.setFavorite("favorite", value: true, scope: a)
        try await library.setHistory(false, scope: a)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first)
        let original = try Data(contentsOf: file)
        let limited = ScopedLibrary(directory: dir, maximumStorageBytes: original.count + 1)
        do { try await limited.setFavorite("other", value: true, scope: b); XCTFail("Should reject over-budget write") } catch { XCTAssertEqual(error as? APIError, .storageUnavailable) }
        XCTAssertEqual(try Data(contentsOf: file), original)
        await limited.releaseInactiveScopes(keeping: b)
        let restored = try await limited.view(in: a)
        XCTAssertEqual(restored.favorites, ["favorite"]); XCTAssertEqual(restored.pending, 2); XCTAssertFalse(restored.historyEnabled)
        let untouched = try await limited.view(in: b); XCTAssertTrue(untouched.favorites.isEmpty)
    }
    func testScopeCountBoundAndExistingOverBudgetCanShrink() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let library = ScopedLibrary(directory: dir, maximumScopeFiles: 1)
        try await library.setFavorite("guest", value: true, scope: .guest)
        do { try await library.setFavorite("other", value: true, scope: b); XCTFail() } catch { XCTAssertEqual(error as? APIError, .storageUnavailable) }
        let reduced = ScopedLibrary(directory: dir, maximumStorageBytes: 1)
        try await reduced.clear(scope: .guest) // Shrinking existing state can recover storage pressure.
        let guest = try await reduced.view(in: .guest); XCTAssertTrue(guest.favorites.isEmpty)
    }
    func testCorruptAndSymlinkedAccountFilesArePreservedAndRejected() async throws {
        let dir = directory(), target = directory(); defer { try? FileManager.default.removeItem(at: dir); try? FileManager.default.removeItem(at: target) }
        let library = ScopedLibrary(directory: dir); try await library.setHistory(false, scope: a)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first)
        try Data("broken journal".utf8).write(to: file)
        do { _ = try await ScopedLibrary(directory: dir).view(in: a); XCTFail() } catch {}
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "broken journal")
        try FileManager.default.moveItem(at: file, to: target)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        do { _ = try await ScopedLibrary(directory: dir).view(in: a); XCTFail() } catch { XCTAssertEqual(error as? APIError, .storageUnavailable) }
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "broken journal")
    }
    func testArtworkClearDoesNotClearLibraryOrPrivacyIntent() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let personal = root.appending(path: "personal"), images = root.appending(path: "images")
        let library = ScopedLibrary(directory: personal)
        try await library.setFavorite("offline", value: true, scope: a)
        try await library.setHistory(false, scope: a)
        let artwork = ArtworkLoader(cacheDirectory: images)
        let model = AppModel(client: APIClient(environment: .mock, transport: MockTransport(data: Data())), library: library, artwork: artwork)
        await model.clearCache()
        let view = try await ScopedLibrary(directory: personal).view(in: a)
        XCTAssertEqual(view.favorites, ["offline"]); XCTAssertFalse(view.historyEnabled); XCTAssertEqual(view.pending, 2)
    }
}

private actor StorageRecoveryRemote: LibraryRemote {
    var preferences = LibraryPreferences()
    var favorites: [LibraryFavorite] = []
    var calls: [LibraryOperation] = []
    var seen: [String: LibraryOperation] = [:]
    var receipts: [String: LibraryPreferences] = [:]
    var loseReceipt = false
    var failSnapshotAfterConflict = false
    var snapshotFailure = false
    var extraRows = false
    func configure(loseReceipt: Bool = false, failSnapshotAfterConflict: Bool = false, extraRows: Bool = false) {
        self.loseReceipt = loseReceipt; self.failSnapshotAfterConflict = failSnapshotAfterConflict; self.extraRows = extraRows
    }
    func otherDeviceClears() { preferences.version += 1; preferences.historyEpoch += 1 }
    func snapshot(scope: AccountScope) throws -> LibrarySnapshot {
        if snapshotFailure { snapshotFailure = false; throw APIError.unavailable }
        let additional: [LibraryFavorite] = extraRows ? (0..<2000).map { .init(trackId: "other-\($0)", favorite: true, version: 1, updatedAt: .distantPast) } : []
        return .init(favorites: favorites + additional, recent: [], preferences: preferences)
    }
    func apply(_ op: LibraryOperation, scope: AccountScope) throws -> LibraryPreferences? {
        calls.append(op)
        if let prior = seen[op.id] {
            guard prior == op else { throw APIError.invalidPayload }
            return receipts[op.id]
        }
        switch op.kind {
        case .favorite:
            favorites.removeAll { $0.trackId == op.trackID }
            favorites.append(.init(trackId: op.trackID!, favorite: op.value!, version: op.version! + 1, updatedAt: op.created))
        case .preference, .clear:
            guard op.kind == .clear ? op.epoch == preferences.historyEpoch : op.version == preferences.version else {
                snapshotFailure = failSnapshotAfterConflict; throw APIError.rejected(409)
            }
            if op.kind == .preference { preferences.historyEnabled = op.value! }
            preferences.version += 1; preferences.historyEpoch += 1; receipts[op.id] = preferences
        case .listen:
            guard op.epoch == preferences.historyEpoch, preferences.historyEnabled else { throw APIError.rejected(409) }
        }
        seen[op.id] = op
        if loseReceipt { loseReceipt = false; throw APIError.unavailable }
        return receipts[op.id]
    }
}

extension LibraryStorageBudgetTests {
    private func stored(_ dir: URL) throws -> (URL, Data, LibraryFile) {
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first)
        let bytes = try Data(contentsOf: file)
        return (file, bytes, try JSONDecoder().decode(LibraryFile.self, from: bytes))
    }
    func testColdStartAtFullQuotaDrainsOriginalFavoriteWithoutChangingPayload() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let setup = ScopedLibrary(directory: dir)
        try await setup.setFavorite("favorite", value: true, scope: a)
        let (_, original, before) = try stored(dir)
        XCTAssertEqual(original.count - (try JSONEncoder().encode(before)).count, ScopedLibrary.controlReserveBytes)
        let remote = StorageRecoveryRemote()
        let full = ScopedLibrary(directory: dir, maximumStorageBytes: original.count)
        try await full.synchronize(scope: a, remote: remote)
        let calls = await remote.calls, view = try await full.view(in: a)
        XCTAssertEqual(calls, before.operations); XCTAssertEqual(view.pending, 0); XCTAssertTrue(view.synced)
        XCTAssertLessThanOrEqual(try stored(dir).1.count, original.count)
    }
    func testFullQuotaDisablesAndClearsHistoryDurablyWhileOrdinaryGrowthIsRefused() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let remote = StorageRecoveryRemote(), setup = ScopedLibrary(directory: dir)
        try await setup.synchronize(scope: a, remote: remote)
        let (_, original, _) = try stored(dir)
        let full = ScopedLibrary(directory: dir, maximumStorageBytes: original.count)
        do { try await full.setFavorite("cannot-grow", value: true, scope: a); XCTFail() } catch { XCTAssertEqual(error as? APIError, .storageUnavailable) }
        try await full.setHistory(false, scope: a); try await full.clearHistory(scope: a)
        let (_, queued, before) = try stored(dir); XCTAssertLessThanOrEqual(queued.count, original.count)
        let reopened = ScopedLibrary(directory: dir, maximumStorageBytes: original.count)
        let off = try await reopened.view(in: a); XCTAssertFalse(off.historyEnabled); XCTAssertEqual(off.pending, 2)
        do { try await reopened.synchronize(scope: a, remote: remote) }
        catch { XCTAssertEqual(error as? APIError, .storageUnavailable) } // Final display refresh may need ordinary quota.
        let calls = await remote.calls, after = try await reopened.view(in: a), prefs = await remote.preferences
        XCTAssertEqual(calls.map(\.id), before.operations.map(\.id)); XCTAssertEqual(after.pending, 0)
        XCTAssertFalse(after.historyEnabled); XCTAssertFalse(prefs.historyEnabled)
        XCTAssertLessThanOrEqual(try stored(dir).1.count, original.count)
    }
    func testFullQuotaConflictRebasesOnlyRestrictiveIntentAcrossReopen() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let remote = StorageRecoveryRemote(), setup = ScopedLibrary(directory: dir)
        try await setup.synchronize(scope: a, remote: remote)
        try await setup.setHistory(false, scope: a); try await setup.setHistory(true, scope: a)
        let track = Track(id: "test", title: "test", artist: "test", durationSeconds: 60, audioVersion: 1, access: .free)
        try await setup.record(track, variant: "full", audible: 5, position: 5, eventID: UUID().uuidString, scope: a)
        let (_, original, old) = try stored(dir)
        await remote.otherDeviceClears(); await remote.configure(failSnapshotAfterConflict: true)
        do { try await ScopedLibrary(directory: dir, maximumStorageBytes: original.count).synchronize(scope: a, remote: remote); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unavailable) }
        let (_, _, conflict) = try stored(dir)
        XCTAssertNil(conflict.confirmedPreferences); XCTAssertEqual(conflict.operations.count, 1)
        XCTAssertNotEqual(conflict.operations.first?.id, old.operations.first?.id)
        let reopened = ScopedLibrary(directory: dir, maximumStorageBytes: original.count)
        try await reopened.synchronize(scope: a, remote: remote)
        let calls = await remote.calls, view = try await reopened.view(in: a)
        XCTAssertEqual(calls.count, 2); XCTAssertFalse(calls.contains { $0.kind == .listen || $0.value == true })
        XCTAssertEqual(view.pending, 0); XCTAssertFalse(view.historyEnabled)
        XCTAssertLessThanOrEqual(try stored(dir).1.count, original.count)
    }
    func testOversizedServerDisplayDoesNotBlockPendingUploadAndReceiptReplay() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let setup = ScopedLibrary(directory: dir), remote = StorageRecoveryRemote()
        try await setup.setFavorite("favorite", value: true, scope: a)
        let (_, original, before) = try stored(dir)
        await remote.configure(loseReceipt: true, extraRows: true)
        do { try await ScopedLibrary(directory: dir, maximumStorageBytes: original.count).synchronize(scope: a, remote: remote); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unavailable) }
        let pending = try stored(dir).2; XCTAssertEqual(pending.operations, before.operations)
        let reopened = ScopedLibrary(directory: dir, maximumStorageBytes: original.count)
        do { try await reopened.synchronize(scope: a, remote: remote); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .storageUnavailable) }
        let calls = await remote.calls, after = try await reopened.view(in: a)
        XCTAssertEqual(calls.count, 2); XCTAssertEqual(calls[0], calls[1]); XCTAssertEqual(after.pending, 0); XCTAssertFalse(after.synced)
        XCTAssertLessThanOrEqual(try stored(dir).1.count, original.count)
    }
}
