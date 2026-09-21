import XCTest
@testable import StationCatMusic

private actor CleanupRemote: LibraryRemote {
    var waiting = false
    var release: CheckedContinuation<Void, Never>?
    var block = false
    func setBlocking() { block = true }
    func resume() { release?.resume(); release = nil; block = false }
    func snapshot(scope: AccountScope) async throws -> LibrarySnapshot {
        if block { waiting = true; await withCheckedContinuation { release = $0 } }
        return .init(favorites: [.init(trackId: "remote", favorite: true, version: 1, updatedAt: Date())], recent: [], preferences: .init())
    }
    func apply(_ operation: LibraryOperation, scope: AccountScope) async throws -> LibraryPreferences? { nil }
}
@MainActor final class LocalAccountCleanupTests: XCTestCase {
    let a = AccountScope(environment: .development, accountID: "1")
    let b = AccountScope(environment: .development, accountID: "2")
    let c = AccountScope(environment: .development, accountID: "3")
    func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
    func testOnlySyncedInactiveAccountFilesAreRemovedAndDiskSpaceReclaimed() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let library = ScopedLibrary(directory: dir), remote = CleanupRemote()
        try await library.synchronize(scope: a, remote: remote)
        try await library.synchronize(scope: b, remote: remote)
        try await library.setFavorite("pending", value: true, scope: c)
        try await library.setFavorite("guest", value: true, scope: .guest)
        let before = try FileManager.default.contentsOfDirectory(atPath: dir.path).count
        await library.selectScope(a)
        let removed = try await library.removeInactiveAccountFiles(keeping: a)
        XCTAssertEqual(removed, 1); XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).count, before - 1)
        let reopened = ScopedLibrary(directory: dir)
        let current = try await reopened.view(in: a), forgotten = try await reopened.view(in: b)
        let pending = try await reopened.view(in: c), guest = try await reopened.view(in: .guest)
        XCTAssertEqual(current.favorites, ["remote"]); XCTAssertTrue(forgotten.favorites.isEmpty)
        XCTAssertEqual(pending.pending, 1); XCTAssertEqual(pending.favorites, ["pending"]); XCTAssertEqual(guest.favorites, ["guest"])
        // A later explicit sign-in can download a fresh server baseline.
        try await reopened.synchronize(scope: b, remote: remote)
        let restored = try await reopened.view(in: b); XCTAssertEqual(restored.favorites, ["remote"])
    }
    func testInFlightSnapshotCannotBeReclaimed() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let library = ScopedLibrary(directory: dir), remote = CleanupRemote()
        try await library.synchronize(scope: b, remote: remote)
        await remote.setBlocking()
        let task = Task { try await library.synchronize(scope: b, remote: remote) }
        while !(await remote.waiting) { await Task.yield() }
        await library.selectScope(a)
        let count = try await library.removeInactiveAccountFiles(keeping: a); XCTAssertEqual(count, 0)
        await remote.resume(); try await task.value
        let view = try await library.view(in: b); XCTAssertEqual(view.favorites, ["remote"])
    }
    func testUnknownCorruptAndSymlinkFilesAreKeptWithoutFollowingTarget() async throws {
        let dir = try directory(), outside = try directory()
        defer { try? FileManager.default.removeItem(at: dir); try? FileManager.default.removeItem(at: outside) }
        let target = outside.appending(path: "keep.json"); try Data("external".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: dir.appending(path: "link.json"), withDestinationURL: target)
        try Data("broken".utf8).write(to: dir.appending(path: "unknown.json"))
        let library = ScopedLibrary(directory: dir)
        await library.selectScope(a)
        let count = try await library.removeInactiveAccountFiles(keeping: a); XCTAssertEqual(count, 0)
        XCTAssertEqual(try Data(contentsOf: target), Data("external".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).count, 2)
    }
    func testNewUnsyncedPrivacyIntentIsNotReclaimed() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let library = ScopedLibrary(directory: dir)
        try await library.synchronize(scope: b, remote: CleanupRemote())
        try await library.setHistory(false, scope: b)
        await library.selectScope(a)
        let count = try await library.removeInactiveAccountFiles(keeping: a); XCTAssertEqual(count, 0)
        let reopened = try await ScopedLibrary(directory: dir).view(in: b)
        XCTAssertFalse(reopened.historyEnabled); XCTAssertEqual(reopened.pending, 1)
    }
    func testStaleUserConfirmationAfterAccountChangeDoesNotDelete() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let library = ScopedLibrary(directory: dir)
        try await library.synchronize(scope: a, remote: CleanupRemote())
        let model = AppModel(client: APIClient(environment: .mock, transport: MockTransport(data: Data())), library: library, environment: .development)
        await model.removeInactiveAccountData(confirmedScope: a)
        XCTAssertEqual(model.localCleanupStatus, "localCleanupChanged")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).count, 1)
    }
    func testActorRejectsConfirmationForPreviouslySelectedAccount() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let library = ScopedLibrary(directory: dir)
        try await library.synchronize(scope: b, remote: CleanupRemote())
        await library.selectScope(a)
        await library.selectScope(b)
        do { _ = try await library.removeInactiveAccountFiles(keeping: a); XCTFail("Stale confirmation") } catch {}
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).count, 1)
    }

    func testUnresolvedPrivacyOverlayAndOtherEnvironmentAreRetained() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let library = ScopedLibrary(directory: dir)
        try await library.synchronize(scope: b, remote: CleanupRemote())
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first)
        var state = try JSONDecoder().decode(LibraryFile.self, from: Data(contentsOf: file))
        state.historyBlockedLocally = true; state.preferences.historyEnabled = false; state.conflict = true
        try JSONEncoder().encode(state).write(to: file, options: .atomic)
        let reopened = ScopedLibrary(directory: dir)
        try await reopened.synchronize(scope: .init(environment: .production, accountID: "2"), remote: CleanupRemote())
        await reopened.selectScope(a)
        let removed = try await reopened.removeInactiveAccountFiles(keeping: a)
        XCTAssertEqual(removed, 0); XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).count, 2)
        let view = try await reopened.view(in: b); XCTAssertFalse(view.historyEnabled)
    }

}
