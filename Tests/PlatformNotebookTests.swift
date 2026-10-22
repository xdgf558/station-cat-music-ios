import XCTest
@testable import StationCatMusic

private final class NotebookClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_790_000_000)
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; value.addTimeInterval(seconds) }
}

/// Real atomic writes except at the injected storage failure boundary.
private final class NotebookWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var failing = false
    func setFailing(_ value: Bool) { lock.lock(); defer { lock.unlock() }; failing = value }
    func write(_ data: Data, to url: URL) throws {
        lock.lock(); let shouldFail = failing; lock.unlock()
        if shouldFail { throw CocoaError(.fileWriteOutOfSpace) }
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

@MainActor final class PlatformNotebookTests: XCTestCase {
    private let work = NotebookWork(id: "11111111-1111-4111-8111-111111111111", slug: "first-song")
    private func folder() -> URL {
        FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appending(path: "notebook-" + UUID().uuidString)
    }
    private func file(in directory: URL) throws -> URL {
        try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
    }
    private func expect(_ expected: NotebookError, operation: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Expected \(expected)", file: file, line: line) }
        catch { XCTAssertEqual(error as? NotebookError, expected, file: file, line: line) }
    }

    func testOfflineReopenCreateEditAndDeletePreserveUserWriting() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let clock = NotebookClock(), store = PlatformNotebookStore(directory: root, now: { clock.now() })
        let empty = try await store.snapshot(scope: .guest)
        var draft = NotebookDraft(work: work, title: "  夜里的想法  ", body: "这是我自己写的文字。\n第二行\t保留缩进。")
        let saved = try await store.save(draft, expectedEpoch: empty.epoch, expectedVersion: nil, scope: .guest)
        let reopened = PlatformNotebookStore(directory: root, now: { clock.now() })
        let loaded = try await reopened.snapshot(scope: .guest)
        XCTAssertEqual(loaded, saved); XCTAssertEqual(loaded.notes[0].title, "夜里的想法")
        XCTAssertEqual(loaded.notes[0].body, draft.body); XCTAssertEqual(loaded.notes[0].work, work)
        clock.advance(10); draft.title = "改过的标题"; draft.body += "\n后来的补充。"
        let edited = try await reopened.save(draft, expectedEpoch: loaded.epoch, expectedVersion: 1, scope: .guest)
        XCTAssertEqual(edited.notes[0].version, 2)
        XCTAssertEqual(edited.notes[0].createdAt, loaded.notes[0].createdAt)
        XCTAssertEqual(edited.notes[0].updatedAt.timeIntervalSince(loaded.notes[0].updatedAt), 10)
        let removed = try await reopened.remove(id: draft.id, expectedEpoch: edited.epoch, scope: .guest)
        let final = try await PlatformNotebookStore(directory: root).snapshot(scope: .guest)
        XCTAssertTrue(final.notes.isEmpty); XCTAssertEqual(final, removed)
    }

    func testTitleLineBreakInputKeepsTextAndDoesNotTruncate() {
        let examples = [
            ("Night thoughts", "Night thoughts"),
            ("Night\nthoughts", "Night thoughts"),
            ("Night\r\nthoughts", "Night thoughts"),
            ("夜里的想法\n第二行", "夜里的想法 第二行"),
            ("夜里的想法\r\n第二行", "夜里的想法 第二行"),
            ("First\rsecond\u{2028}third\u{2029}fourth", "First second third fourth"),
            ("  First\n\nlast  ", "  First  last  ")
        ]
        for (input, expected) in examples {
            XCTAssertEqual(NotebookTitleInput.singleLine(input), expected)
        }
        let longTitle = String(repeating: "字", count: 121)
        XCTAssertEqual(NotebookTitleInput.singleLine(longTitle), longTitle)
        // Other invalid controls must reach validation, not silently disappear.
        XCTAssertEqual(NotebookTitleInput.singleLine("Night\u{0}thoughts"), "Night\u{0}thoughts")
    }

    func testLFAndCRLFTitlesRejectRawInputAndRoundTripNormalizedInput() async throws {
        for separator in ["\n", "\r\n"] {
            let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
            let store = PlatformNotebookStore(directory: root), initial = try await store.snapshot(scope: .guest)
            var draft = NotebookDraft(title: "夜里的想法", body: "已有文字")
            let saved = try await store.save(draft, expectedEpoch: initial.epoch, expectedVersion: nil, scope: .guest)
            let url = try file(in: root), bytes = try Data(contentsOf: url)
            draft.title = "夜里的想法" + separator + "第二行"
            draft.body = "正文第一行" + separator + "正文第二行"
            let invalidDraft = draft
            await expect(.invalidInput) {
                _ = try await store.save(draft, expectedEpoch: saved.epoch, expectedVersion: 1, scope: .guest)
            }
            XCTAssertEqual(draft, invalidDraft)
            XCTAssertEqual(try Data(contentsOf: url), bytes)
            let unchanged = try await PlatformNotebookStore(directory: root).snapshot(scope: .guest)
            XCTAssertEqual(unchanged, saved)
            draft.title = NotebookTitleInput.singleLine(draft.title)
            let corrected = try await store.save(draft, expectedEpoch: saved.epoch, expectedVersion: 1, scope: .guest)
            let reopened = try await PlatformNotebookStore(directory: root).snapshot(scope: .guest)
            XCTAssertEqual(reopened, corrected)
            XCTAssertEqual(reopened.notes[0].title, "夜里的想法 第二行")
            XCTAssertEqual(reopened.notes[0].body, invalidDraft.body)
            XCTAssertEqual(reopened.notes[0].version, 2)
        }
    }

    func testNormalizedTitleSaveFailureKeepsDraftAndSavedFileForRetry() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let writer = NotebookWriter(), store = PlatformNotebookStore(directory: root, writeAtomically: { try writer.write($0, to: $1) })
        let initial = try await store.snapshot(scope: .guest)
        var draft = NotebookDraft(title: "Original", body: "Saved body")
        let saved = try await store.save(draft, expectedEpoch: initial.epoch, expectedVersion: nil, scope: .guest)
        let url = try file(in: root), bytes = try Data(contentsOf: url)
        draft.title = NotebookTitleInput.singleLine("Night\r\nthoughts")
        draft.body = "Unsaved body\nsecond line"
        let unsavedDraft = draft
        writer.setFailing(true)
        await expect(.storageUnavailable) {
            _ = try await store.save(draft, expectedEpoch: saved.epoch, expectedVersion: 1, scope: .guest)
        }
        XCTAssertEqual(draft, unsavedDraft)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        writer.setFailing(false)
        let retried = try await store.save(draft, expectedEpoch: saved.epoch, expectedVersion: 1, scope: .guest)
        XCTAssertEqual(retried.notes[0].title, "Night thoughts")
        XCTAssertEqual(retried.notes[0].body, unsavedDraft.body)
        XCTAssertEqual(retried.notes[0].version, 2)
    }

    func testScopeAndEnvironmentIsolationIncludingGuestLikeAccountName() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let store = PlatformNotebookStore(directory: root)
        let scopes: [AccountScope] = [.guest, .init(environment: .mock, accountID: "guest"),
                                     .init(environment: .production, accountID: nil),
                                     .init(environment: .production, accountID: UUID().uuidString)]
        for (index, scope) in scopes.enumerated() {
            let state = try await store.snapshot(scope: scope)
            _ = try await store.save(NotebookDraft(body: "Private \(index)"), expectedEpoch: state.epoch, expectedVersion: nil, scope: scope)
        }
        let reopened = PlatformNotebookStore(directory: root)
        for (index, scope) in scopes.enumerated() {
            let state = try await reopened.snapshot(scope: scope)
            XCTAssertEqual(state.notes.map(\.body), ["Private \(index)"])
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).count, 4)
    }

    func testPersistedShapeContainsOnlyUserTextAndStableWorkReference() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let store = PlatformNotebookStore(directory: root), empty = try await store.snapshot(scope: .guest)
        // URLs typed by the user are their writing, not automatically copied server metadata.
        _ = try await store.save(NotebookDraft(work: work, body: "My own reference: https://example.org"), expectedEpoch: empty.epoch, expectedVersion: nil, scope: .guest)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file(in: root))) as? [String: Any])
        let state = try XCTUnwrap(json["state"] as? [String: Any])
        let note = try XCTUnwrap((state["notes"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(note.keys), ["id", "work", "title", "body", "createdAt", "updatedAt", "version"])
        XCTAssertEqual(Set(try XCTUnwrap(note["work"] as? [String: Any]).keys), ["id", "slug"])
        XCTAssertEqual(note["body"] as? String, "My own reference: https://example.org")
    }

    func testStaleEditorCannotOverwriteNewerNote() async throws {
        let store = PlatformNotebookStore(), initial = try await store.snapshot(scope: .guest)
        var draft = NotebookDraft(body: "first")
        let first = try await store.save(draft, expectedEpoch: initial.epoch, expectedVersion: nil, scope: .guest)
        draft.body = "second"
        let second = try await store.save(draft, expectedEpoch: first.epoch, expectedVersion: 1, scope: .guest)
        draft.body = "late first editor"
        await expect(.staleEdit) { _ = try await store.save(draft, expectedEpoch: first.epoch, expectedVersion: 1, scope: .guest) }
        await expect(.staleEdit) { _ = try await store.save(draft, expectedEpoch: first.epoch, expectedVersion: nil, scope: .guest) }
        let actual = try await store.snapshot(scope: .guest)
        XCTAssertEqual(actual, second)
    }

    func testDeletionAndClearInvalidateLateDraftsAcrossReopen() async throws {
        for clear in [false, true] {
            let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
            let store = PlatformNotebookStore(directory: root), initial = try await store.snapshot(scope: .guest)
            let draft = NotebookDraft(body: "must stay deleted")
            let saved = try await store.save(draft, expectedEpoch: initial.epoch, expectedVersion: nil, scope: .guest)
            let removed: NotebookState
            if clear { removed = try await store.clear(expectedEpoch: saved.epoch, scope: .guest) }
            else { removed = try await store.remove(id: draft.id, expectedEpoch: saved.epoch, scope: .guest) }
            XCTAssertNotEqual(saved.epoch, removed.epoch)
            let reopened = PlatformNotebookStore(directory: root)
            for version in [nil, Optional(1)] {
                await expect(.staleEdit) { _ = try await reopened.save(draft, expectedEpoch: saved.epoch, expectedVersion: version, scope: .guest) }
            }
            let actual = try await reopened.snapshot(scope: .guest)
            XCTAssertEqual(actual, removed)
        }
    }

    func testEmptyEpochPersistsAndClearEvenWhenEmptyRejectsAnUnsavedEditor() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let initial = try await PlatformNotebookStore(directory: root).snapshot(scope: .guest)
        let reopened = PlatformNotebookStore(directory: root)
        let before = try await reopened.snapshot(scope: .guest)
        XCTAssertEqual(initial, before)
        let cleared = try await reopened.clear(expectedEpoch: before.epoch, scope: .guest)
        await expect(.staleEdit) {
            _ = try await reopened.save(NotebookDraft(body: "late"), expectedEpoch: initial.epoch, expectedVersion: nil, scope: .guest)
        }
        XCTAssertNotEqual(initial.epoch, cleared.epoch)
    }

    func testTopicRemovalUncategorizesNotesAndProtectsStaleEditors() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let store = PlatformNotebookStore(directory: root), initial = try await store.snapshot(scope: .guest)
        let grouped = try await store.saveTopic(id: nil, name: "  夜晚  ", expectedEpoch: initial.epoch, scope: .guest)
        let topic = try XCTUnwrap(grouped.topics.first)
        XCTAssertEqual(topic.name, "夜晚")
        let draft = NotebookDraft(body: "不丢失的文字", topicID: topic.id)
        let saved = try await store.save(draft, expectedEpoch: grouped.epoch, expectedVersion: nil, scope: .guest)
        let removed = try await store.removeTopic(id: topic.id, expectedEpoch: saved.epoch, scope: .guest)
        XCTAssertTrue(removed.topics.isEmpty); XCTAssertNil(removed.notes[0].topicID)
        XCTAssertEqual(removed.notes[0].body, draft.body); XCTAssertEqual(removed.notes[0].version, 2)
        let reopened = PlatformNotebookStore(directory: root)
        await expect(.staleEdit) { _ = try await reopened.save(draft, expectedEpoch: saved.epoch, expectedVersion: 1, scope: .guest) }
        await expect(.staleEdit) { _ = try await reopened.save(NotebookDraft(body: "new", topicID: topic.id), expectedEpoch: removed.epoch, expectedVersion: nil, scope: .guest) }
        let final = try await reopened.snapshot(scope: .guest); XCTAssertEqual(final, removed)
    }

    func testInputLimitsAndCorruptWorkReferencesDoNotChangeSavedText() async throws {
        let store = PlatformNotebookStore(), initial = try await store.snapshot(scope: .guest)
        let invalid = [NotebookDraft(), NotebookDraft(title: "\u{0}"),
                       NotebookDraft(title: String(repeating: "a", count: 121)),
                       NotebookDraft(body: String(repeating: "字", count: 8001)),
                       NotebookDraft(work: NotebookWork(id: work.id, slug: "song?utm_source=bad"), body: "text"),
                       NotebookDraft(work: NotebookWork(id: "bad", slug: "song"), body: "text")]
        for draft in invalid {
            await expect(.invalidInput) { _ = try await store.save(draft, expectedEpoch: initial.epoch, expectedVersion: nil, scope: .guest) }
        }
        let first = try await store.saveTopic(id: nil, name: "Night", expectedEpoch: initial.epoch, scope: .guest)
        await expect(.invalidInput) { _ = try await store.saveTopic(id: nil, name: "night", expectedEpoch: first.epoch, scope: .guest) }
        let actual = try await store.snapshot(scope: .guest); XCTAssertEqual(actual, first)
    }

    func testCorruptJSONAndInvalidStateArePreservedAndNeverReset() async throws {
        for corruption in 0..<4 {
            let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
            let store = PlatformNotebookStore(directory: root), initial = try await store.snapshot(scope: .guest)
            _ = try await store.save(NotebookDraft(body: "keep"), expectedEpoch: initial.epoch, expectedVersion: nil, scope: .guest)
            let url = try file(in: root)
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            var state = try XCTUnwrap(json["state"] as? [String: Any])
            var notes = try XCTUnwrap(state["notes"] as? [[String: Any]])
            if corruption == 1 { notes.append(notes[0]); state["notes"] = notes }
            if corruption == 2 { notes[0]["topicID"] = UUID().uuidString; state["notes"] = notes }
            if corruption == 3 { state["revision"] = -1 }
            json["state"] = state
            let data = corruption == 0 ? Data("broken".utf8) : try JSONSerialization.data(withJSONObject: json)
            try data.write(to: url)
            await expect(.storageUnavailable) { _ = try await store.snapshot(scope: .guest) }
            await expect(.storageUnavailable) { _ = try await store.clear(expectedEpoch: initial.epoch, scope: .guest) }
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
    }

    func testRegularAndDanglingSymlinksAndSymlinkDirectoryAreRefused() async throws {
        for dangling in [false, true] {
            let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
            let store = PlatformNotebookStore(directory: root), initial = try await store.snapshot(scope: .guest)
            let url = try file(in: root), target = root.deletingLastPathComponent().appending(path: "target-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: target) }
            if !dangling { try Data("keep".utf8).write(to: target) }
            try FileManager.default.removeItem(at: url)
            try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
            await expect(.storageUnavailable) { _ = try await store.save(NotebookDraft(body: "write"), expectedEpoch: initial.epoch, expectedVersion: nil, scope: .guest) }
            if !dangling { XCTAssertEqual(try Data(contentsOf: target), Data("keep".utf8)) }
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: url.path), target.path)
        }
        let root = folder(), alias = folder(); defer { try? FileManager.default.removeItem(at: alias); try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        await expect(.storageUnavailable) { _ = try await PlatformNotebookStore(directory: alias.appending(path: "child")).snapshot(scope: .guest) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testAtomicWriteFailureKeepsPreviousBytesAndDoesNotAdvanceEpochOrVersion() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let writer = NotebookWriter(), store = PlatformNotebookStore(directory: root, writeAtomically: { try writer.write($0, to: $1) })
        let initial = try await store.snapshot(scope: .guest)
        var draft = NotebookDraft(body: "saved text")
        let saved = try await store.save(draft, expectedEpoch: initial.epoch, expectedVersion: nil, scope: .guest)
        let url = try file(in: root), bytes = try Data(contentsOf: url)
        writer.setFailing(true); draft.body = "unsaved edit"
        await expect(.storageUnavailable) { _ = try await store.save(draft, expectedEpoch: saved.epoch, expectedVersion: 1, scope: .guest) }
        await expect(.storageUnavailable) { _ = try await store.clear(expectedEpoch: saved.epoch, scope: .guest) }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        let reopened = try await PlatformNotebookStore(directory: root).snapshot(scope: .guest)
        XCTAssertEqual(reopened, saved)
        writer.setFailing(false)
        let retried = try await store.save(draft, expectedEpoch: saved.epoch, expectedVersion: 1, scope: .guest)
        XCTAssertEqual(retried.notes[0].body, "unsaved edit"); XCTAssertEqual(retried.notes[0].version, 2)
    }

    func testQuotaRejectsGrowthButAllowsClearWithoutDeletingOtherScopes() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let store = PlatformNotebookStore(directory: root), initial = try await store.snapshot(scope: .guest)
        let saved = try await store.save(NotebookDraft(body: String(repeating: "a", count: 1000)), expectedEpoch: initial.epoch, expectedVersion: nil, scope: .guest)
        let url = try file(in: root), bytes = try Data(contentsOf: url)
        let foreign = root.appending(path: "other-scope.json")
        try Data(repeating: 65, count: PlatformNotebookStore.maximumTotalBytes).write(to: foreign)
        await expect(.limitReached) { _ = try await store.save(NotebookDraft(body: "growth"), expectedEpoch: saved.epoch, expectedVersion: nil, scope: .guest) }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        let cleared = try await store.clear(expectedEpoch: saved.epoch, scope: .guest)
        XCTAssertTrue(cleared.notes.isEmpty)
        XCTAssertEqual(try foreign.resourceValues(forKeys: [.fileSizeKey]).fileSize, PlatformNotebookStore.maximumTotalBytes)
    }

    func testCountLimitsRejectNewEntriesButPermitEditingAndDeleting() async throws {
        let store = PlatformNotebookStore()
        var state = try await store.snapshot(scope: .guest)
        for index in 0..<PlatformNotebookStore.maximumTopics {
            state = try await store.saveTopic(id: nil, name: "Topic \(index)", expectedEpoch: state.epoch, scope: .guest)
        }
        await expect(.limitReached) { _ = try await store.saveTopic(id: nil, name: "Extra", expectedEpoch: state.epoch, scope: .guest) }
        for index in 0..<PlatformNotebookStore.maximumNotes {
            state = try await store.save(NotebookDraft(body: "Note \(index)"), expectedEpoch: state.epoch, expectedVersion: nil, scope: .guest)
        }
        await expect(.limitReached) { _ = try await store.save(NotebookDraft(body: "Extra"), expectedEpoch: state.epoch, expectedVersion: nil, scope: .guest) }
        let note = try XCTUnwrap(state.notes.first)
        state = try await store.save(NotebookDraft(id: note.id, body: "edited at capacity"), expectedEpoch: state.epoch, expectedVersion: note.version, scope: .guest)
        XCTAssertEqual(state.notes.count, PlatformNotebookStore.maximumNotes)
        state = try await store.remove(id: note.id, expectedEpoch: state.epoch, scope: .guest)
        XCTAssertEqual(state.notes.count, PlatformNotebookStore.maximumNotes - 1)
    }

    func testClockRollbackKeepsCompleteNotesAndMonotonicModifiedDate() async throws {
        let clock = NotebookClock(), store = PlatformNotebookStore(now: { clock.now() })
        let initial = try await store.snapshot(scope: .guest)
        var draft = NotebookDraft(body: "before")
        let saved = try await store.save(draft, expectedEpoch: initial.epoch, expectedVersion: nil, scope: .guest)
        clock.advance(-3600); draft.body = "after clock change"
        let edited = try await store.save(draft, expectedEpoch: saved.epoch, expectedVersion: 1, scope: .guest)
        XCTAssertEqual(edited.notes[0].updatedAt, saved.notes[0].updatedAt)
        XCTAssertEqual(edited.notes[0].body, draft.body)
    }

    func testDeletedAccountCannotBeRepopulatedAndGuestIsUntouched() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let store = PlatformNotebookStore(directory: root), account = AccountScope(environment: .mock, accountID: UUID().uuidString)
        let guest = try await store.snapshot(scope: .guest), member = try await store.snapshot(scope: account)
        let guestSaved = try await store.save(NotebookDraft(body: "guest"), expectedEpoch: guest.epoch, expectedVersion: nil, scope: .guest)
        let accountSaved = try await store.save(NotebookDraft(body: "member"), expectedEpoch: member.epoch, expectedVersion: nil, scope: account)
        try await store.removeDeletedAccount(scope: account)
        await expect(.storageUnavailable) { _ = try await store.save(NotebookDraft(body: "late"), expectedEpoch: accountSaved.epoch, expectedVersion: nil, scope: account) }
        let guestAfter = try await store.snapshot(scope: .guest)
        XCTAssertEqual(guestAfter, guestSaved)
        let reopened = PlatformNotebookStore(directory: root)
        await expect(.staleEdit) { _ = try await reopened.save(NotebookDraft(body: "late"), expectedEpoch: accountSaved.epoch, expectedVersion: nil, scope: account) }
        let recreated = try await reopened.snapshot(scope: account); XCTAssertTrue(recreated.notes.isEmpty)
    }
}
