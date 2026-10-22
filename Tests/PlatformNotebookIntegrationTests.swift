import XCTest
@testable import StationCatMusic

private actor NotebookCatalog: PlatformMusicProviding {
    nonisolated let webOrigin = PlatformMusicAPI.productionOrigin
    nonisolated static let work = NotebookWork(id: "11111111-1111-4111-8111-111111111111", slug: "notebook-song")
    var offline = false
    var wrongIdentity = false
    private(set) var detailRequests = 0
    func configure(offline: Bool = false, wrongIdentity: Bool = false) { self.offline = offline; self.wrongIdentity = wrongIdentity }
    func setLocale(_ locale: String) {}
    func track() -> Track {
        Track(id: Self.work.id, title: "Published title", artist: "Station Cat", durationSeconds: 0, audioVersion: 1, access: .unavailable,
              release: PlatformTrackRelease(slug: Self.work.slug, summary: "", webURL: webOrigin.appending(path: "music/tracks/notebook-song/"), platforms: [], availability: "unconfirmed", previewAvailable: false))
    }
    func catalog() throws -> Catalog {
        if offline { throw URLError(.notConnectedToInternet) }
        return Catalog(items: [track()], nextCursor: nil)
    }
    func featuredTracks() throws -> [Track] { [] }
    func platformDetail(_ track: Track, locale: String) async throws -> PlatformTrackDetail { try await resolvePlatformTrack(slug: Self.work.slug, locale: locale) }
    func resolvePlatformTrack(slug: String, locale: String) throws -> PlatformTrackDetail {
        detailRequests += 1
        if offline { throw URLError(.notConnectedToInternet) }
        if wrongIdentity { throw APIError.rejected(410) }
        return PlatformTrackDetail(track: track(), story: "Server-owned story", lyricsURL: nil)
    }
    func bookmark(_ track: Track, locale: String) throws -> PlatformBookmark {
        if offline { throw URLError(.notConnectedToInternet) }
        return PlatformBookmark(id: track.id, slug: Self.work.slug, title: track.title, artist: track.artist,
                                revision: 1, locale: locale, savedAt: Date(), expires: Date().addingTimeInterval(3600))
    }
}

@MainActor final class PlatformNotebookIntegrationTests: XCTestCase {
    private func folder() -> URL { FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appending(path: "notebook-model-" + UUID().uuidString) }
    private func model(_ source: NotebookCatalog, root: URL) -> AppModel {
        AppModel(client: source, library: ScopedLibrary(directory: root.appending(path: "library")),
                 artwork: ArtworkLoader(cacheDirectory: root.appending(path: "artwork")), platformMode: true,
                 bookmarks: PlatformBookmarkStore(directory: root.appending(path: "bookmarks")),
                 personal: PlatformPersonalStore(directory: root.appending(path: "personal")),
                 notebook: PlatformNotebookStore(directory: root.appending(path: "notebook")))
    }
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 { if condition() { return }; try await Task.sleep(for: .milliseconds(10)) }
        XCTFail("Notebook state did not settle")
    }
    func testOfflineRestartPreservesOwnWritingAndOpeningWorkStillVerifies() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let source = NotebookCatalog(), first = model(source, root: root)
        await first.initialize()
        let state = try XCTUnwrap(first.notebookState)
        let draft = NotebookDraft(work: NotebookCatalog.work, title: "My own title", body: "A private thought, kept offline.")
        let saved = await first.saveNotebook(draft, expectedEpoch: state.epoch, expectedVersion: nil, scope: first.scope)
        XCTAssertTrue(saved)
        try await wait { first.notebookBookmark(for: NotebookCatalog.work) != nil }
        await source.configure(offline: true)
        let reopened = model(source, root: root)
        await reopened.initialize()
        XCTAssertEqual(reopened.notebookState?.notes.first?.body, draft.body)
        XCTAssertEqual(reopened.notebookBookmark(for: NotebookCatalog.work)?.title, "Published title")
        XCTAssertNil(reopened.notebookTrack(for: NotebookCatalog.work))
        reopened.openNotebookWork(NotebookCatalog.work)
        try await wait { reopened.platformDetailFailure }
        XCTAssertNil(reopened.platformDetail); XCTAssertFalse(reopened.playback.hasAudioSource)
        XCTAssertEqual(reopened.notebookState?.notes.first?.body, draft.body)
        let requests = await source.detailRequests; XCTAssertEqual(requests, 1)
        let path = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root.appending(path: "notebook"), includingPropertiesForKeys: nil).first)
        let text = try String(contentsOf: path, encoding: .utf8)
        for automaticData in ["Published title", "Server-owned story", "https://", "playbackUrl", "platforms", "utm_"] { XCTAssertFalse(text.contains(automaticData)) }
    }
    func testClearRejectsOldEditorAndCacheClearDoesNotEraseNotes() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let source = NotebookCatalog(), model = model(source, root: root)
        await model.initialize()
        let epoch = try XCTUnwrap(model.notebookState?.epoch)
        let draft = NotebookDraft(title: "Keep", body: "Written by me")
        let saved = await model.saveNotebook(draft, expectedEpoch: epoch, expectedVersion: nil, scope: model.scope)
        XCTAssertTrue(saved)
        await model.clearCache()
        XCTAssertEqual(model.notebookState?.notes.count, 1)
        let cleared = await model.clearNotebook(expectedEpoch: epoch)
        XCTAssertTrue(cleared)
        let replay = await model.saveNotebook(draft, expectedEpoch: epoch, expectedVersion: 1, scope: model.scope)
        XCTAssertFalse(replay); XCTAssertEqual(model.notebookErrorKey, "notebookStale")
        XCTAssertTrue(model.notebookState?.notes.isEmpty == true)
        let reopened = try await PlatformNotebookStore(directory: root.appending(path: "notebook")).snapshot(scope: .guest)
        XCTAssertTrue(reopened.notes.isEmpty)
    }
    func testCapturedEditorCannotSaveAcrossScopeChange() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let source = NotebookCatalog(), model = model(source, root: root)
        await model.initialize()
        let originalScope = model.scope, epoch = try XCTUnwrap(model.notebookState?.epoch)
        await model.changeScope(AccountScope(environment: .mock, accountID: UUID().uuidString))
        let saved = await model.saveNotebook(NotebookDraft(title: "Old editor"), expectedEpoch: epoch, expectedVersion: nil, scope: originalScope)
        XCTAssertFalse(saved); XCTAssertTrue(model.notebookState?.notes.isEmpty == true)
        let original = try await model.notebook.snapshot(scope: originalScope)
        XCTAssertTrue(original.notes.isEmpty)
    }
    func testSaveErrorKeepsEditorDataAndPreviousState() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let source = NotebookCatalog(), model = model(source, root: root)
        await model.initialize()
        let epoch = try XCTUnwrap(model.notebookState?.epoch)
        let original = NotebookDraft(title: "Keep", body: "Original")
        let saved = await model.saveNotebook(original, expectedEpoch: epoch, expectedVersion: nil, scope: model.scope)
        XCTAssertTrue(saved)
        let invalid = NotebookDraft(id: original.id, title: "Keep", body: String(repeating: "x", count: 8_001))
        let result = await model.saveNotebook(invalid, expectedEpoch: epoch, expectedVersion: 1, scope: model.scope)
        XCTAssertFalse(result); XCTAssertEqual(model.notebookErrorKey, "notebookInvalid")
        XCTAssertEqual(model.notebookState?.notes.first?.body, "Original"); XCTAssertFalse(model.notebookBusy)
    }
    func testRemovedWorkDoesNotDeleteUserWritingOrEnableListening() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let source = NotebookCatalog(), model = model(source, root: root)
        await model.initialize()
        let epoch = try XCTUnwrap(model.notebookState?.epoch)
        let saved = await model.saveNotebook(NotebookDraft(work: NotebookCatalog.work, body: "My words"), expectedEpoch: epoch, expectedVersion: nil, scope: model.scope)
        XCTAssertTrue(saved)
        await source.configure(wrongIdentity: true)
        model.openNotebookWork(NotebookCatalog.work)
        try await wait { model.platformDetailFailure }
        XCTAssertEqual(model.platformDetailFailureKey, "platformWorkRemoved")
        XCTAssertNil(model.platformDetail); XCTAssertEqual(model.notebookState?.notes.first?.body, "My words")
        XCTAssertFalse(model.playback.hasAudioSource)
    }
}
