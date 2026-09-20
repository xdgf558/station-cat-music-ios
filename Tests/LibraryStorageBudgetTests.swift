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
