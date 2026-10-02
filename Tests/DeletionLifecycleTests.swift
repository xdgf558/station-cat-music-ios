import XCTest
import CryptoKit
@testable import StationCatMusic

private actor DeletionWaitingRemote: LibraryRemote {
    var entered = false
    var release: CheckedContinuation<Void, Never>?
    var writes = 0
    func snapshot(scope: AccountScope) async throws -> LibrarySnapshot {
        entered = true; await withCheckedContinuation { release = $0 }
        return .init(favorites: [], recent: [], preferences: .init())
    }
    func resume() { release?.resume(); release = nil }
    func apply(_ operation: LibraryOperation, scope: AccountScope) async throws -> LibraryPreferences? { writes += 1; return nil }
}
@MainActor final class DeletionLifecycleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let a = AccountScope(environment: .development, accountID: "fixture-A")
    private let b = AccountScope(environment: .development, accountID: "fixture-B")
    private func text(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    private func status(_ record: DeletionRecoveryEnvelope, state: String = "completed", override: [String: Any] = [:]) throws -> NativeDeletionStatus {
        var json: [String: Any] = ["deletionRequestId": record.deletionRequestID, "status": state, "confirmAccepted": true,
            "receiptExpiresAt": text(record.receiptExpiresAt ?? now.addingTimeInterval(86400)), "stage": state == "completed" ? "completed" : "private_data",
            "confirmedAt": text(now.addingTimeInterval(-5)), "completedAt": state == "completed" ? text(now) : NSNull()]
        for (key, value) in override { json[key] = value }
        return try NativeJSON.decoder().decode(NativeDeletionStatus.self, from: JSONSerialization.data(withJSONObject: json))
    }
    private func confirmed(_ journal: DeletionJournal, account: String = "fixture-A") async throws -> DeletionRecoveryEnvelope {
        let record = try await journal.prepare(accountID: account)
        try await journal.recordPrepared(id: record.deletionRequestID, scopeVersion: record.scopeVersion,
            prepareUntil: now.addingTimeInterval(600), receiptUntil: now.addingTimeInterval(86400))
        return try await journal.explicitlyConfirm(scopeVersion: record.scopeVersion, now: now)
    }
    private func setup(_ store: MemorySecureStore = MemorySecureStore()) throws -> (NativeAccountModel, NativeAuthenticationService, NativeDeletionService, DeletionJournal, AuthFixtureTransport) {
        let configuration = try NativeAuthConfiguration(environment: .development, origin: URL(string: "https://native.example.test")!, explicitlyEnabled: true)
        let transport = AuthFixtureTransport(), api = NativeAuthAPI(configuration: configuration, transport: transport)
        let auth = NativeAuthenticationService(configuration: configuration, api: api, journal: AuthJournal(store: store, environment: .development), browser: FixtureBrowser())
        let journal = DeletionJournal(store: store, environment: .development), deletion = NativeDeletionService(journal: journal, auth: auth, api: api)
        return (NativeAccountModel(auth: auth, deletion: deletion), auth, deletion, journal, transport)
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
    private func file(_ scope: AccountScope, in directory: URL) -> URL {
        let key = SHA256.hash(data: Data((scope.environment.rawValue + ":" + (scope.accountID ?? "guest")).utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: key + ".json")
    }
    func testCompletedRequiresAcceptedConfirmationAndConsistentTimes() async throws {
        let journal = DeletionJournal(store: MemorySecureStore(), environment: .development), record = try await confirmed(journal)
        for bad: [String: Any] in [
            ["confirmAccepted": false], ["confirmedAt": NSNull()], ["completedAt": NSNull()],
            ["completedAt": text(now.addingTimeInterval(1))], ["completedAt": text(now.addingTimeInterval(-6))],
            ["confirmedAt": text(now.addingTimeInterval(1))], ["receiptExpiresAt": text(now)],
            ["receiptExpiresAt": text(now.addingTimeInterval(15 * 86400))], ["stage": ""],
            ["stage": "processing"],
            ["deletionRequestId": UUID().uuidString], ["scopeVersion": "station-account-v1"]
        ] {
            XCTAssertThrowsError(try status(record, override: bad).validate(record: record, serverNow: now))
        }
        XCTAssertNoThrow(try status(record).validate(record: record, serverNow: now))
        let afterDeadline = try status(record, override: ["confirmedAt": text(now.addingTimeInterval(601)), "completedAt": text(now.addingTimeInterval(602))])
        XCTAssertThrowsError(try afterDeadline.validate(record: record, serverNow: now.addingTimeInterval(603)))
        for state in ["accepted", "processing", "retrying", "attention_required"] {
            XCTAssertNoThrow(try status(record, state: state).validate(record: record, serverNow: now))
            XCTAssertThrowsError(try status(record, state: state, override: ["completedAt": text(now)]).validate(record: record, serverNow: now))
        }
    }
    func testUnknownAndUnconfirmedStatusesNeverCompleteDeletion() async throws {
        let journal = DeletionJournal(store: MemorySecureStore(), environment: .development)
        let record = try await journal.prepare(accountID: "fixture-A")
        XCTAssertThrowsError(try status(record).validate(record: record, serverNow: now))
        XCTAssertThrowsError(try status(record, state: "unknown").validate(record: record, serverNow: now))
    }
    func testInvalidQueryPreservesReceiptThenValidQueryCompletes() async throws {
        let (_, auth, deletion, journal, transport) = try setup(); try await auth.signIn()
        _ = try await deletion.prepare(); _ = try await deletion.explicitlyConfirm()
        let before = try await journal.read()
        await transport.setDeletionReply("completed")
        do { _ = try await deletion.queryRecovery(); XCTFail("Accepted completion without time") } catch {}
        let rejected = try await journal.read(); XCTAssertEqual(before, rejected)
        await transport.setDeletionReply("completed", completionOffset: 0)
        let completed = try await deletion.queryRecovery(); XCTAssertEqual(completed?.status, "completed")
        let after = try await journal.read(); XCTAssertEqual(after?.receipt, before?.receipt); XCTAssertNotNil(after?.completedAt)
        let requests = await transport.requests.filter { $0.url?.path.hasSuffix("/status") == true }
        XCTAssertEqual(requests.count, 2); XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "GET" && $0.value(forHTTPHeaderField: "Authorization")?.hasPrefix("DeletionReceipt ") == true && $0.value(forHTTPHeaderField: "Cookie") == nil })
    }
    func testCompletedReceiptArchivesAtomicallyAndAllowsAnotherAccount() async throws {
        let store = MemorySecureStore(), journal = DeletionJournal(store: store, environment: .development), record = try await confirmed(journal)
        try await journal.recordStatus(status(record), serverNow: now, expected: record)
        await store.setFailure(true)
        do { _ = try await journal.prepare(accountID: "fixture-B"); XCTFail("Lost receipt under storage failure") } catch {}
        let retained = try await journal.read(); XCTAssertEqual(retained?.receipt, record.receipt)
        await store.setFailure(false)
        let next = try await journal.prepare(accountID: "fixture-B")
        let reopened = DeletionJournal(store: store, environment: .development), records = try await reopened.records()
        XCTAssertEqual(records.count, 2); XCTAssertEqual(records[0], next); XCTAssertEqual(records[1].receipt, record.receipt)
        XCTAssertEqual(records[1].lastKnownStatus, "completed"); XCTAssertNotEqual(next.receipt, record.receipt)
    }
    func testExpiredPreparationCanRestartWithoutLosingOldReceipt() async throws {
        let journal = DeletionJournal(store: MemorySecureStore(), environment: .development), record = try await journal.prepare(accountID: "fixture-A")
        let json: [String: Any] = ["deletionRequestId": record.deletionRequestID, "status": "preparation_expired", "confirmAccepted": false, "receiptExpiresAt": text(now.addingTimeInterval(86400))]
        let expired = try NativeJSON.decoder().decode(NativeDeletionStatus.self, from: JSONSerialization.data(withJSONObject: json))
        try await journal.recordStatus(expired, serverNow: now, expected: record)
        let next = try await journal.prepare(accountID: "fixture-A"), records = try await journal.records()
        XCTAssertNotEqual(next.deletionRequestID, record.deletionRequestID); XCTAssertEqual(records[1].receipt, record.receipt)
    }
    func testPendingAndUncertainConfirmationNeverArchiveOrSwitchAccounts() async throws {
        let journal = DeletionJournal(store: MemorySecureStore(), environment: .development), record = try await confirmed(journal)
        do { _ = try await journal.prepare(accountID: "fixture-B"); XCTFail("Discarded in-flight deletion") } catch {}
        let same = try await journal.prepare(accountID: "fixture-A"); XCTAssertEqual(same, record)
        let records = try await journal.records(); XCTAssertEqual(records.count, 1)
    }
    func testLegacyEnvelopeMigratesWithoutChangingReceiptOrConfirmationID() async throws {
        let store = MemorySecureStore(), journal = DeletionJournal(store: store, environment: .development), record = try await confirmed(journal)
        try await store.write(JSONEncoder().encode(record), key: "deletion.development")
        let reopened = DeletionJournal(store: store, environment: .development), before = try await reopened.read()
        XCTAssertEqual(before, record)
        try await reopened.recordStatus(status(record, state: "attention_required"), serverNow: now, expected: record)
        let after = try await DeletionJournal(store: store, environment: .development).read()
        XCTAssertEqual(after?.receipt, record.receipt); XCTAssertEqual(after?.confirmRequestID, record.confirmRequestID)
        XCTAssertEqual(after?.lastKnownStatus, "attention_required")
    }
    func testTerminalStatusCannotRegressOnLateResponse() async throws {
        let journal = DeletionJournal(store: MemorySecureStore(), environment: .development), record = try await confirmed(journal)
        try await journal.recordStatus(status(record), serverNow: now, expected: record)
        do { try await journal.recordStatus(status(record, state: "processing"), serverNow: now, expected: record); XCTFail("Regressed completed receipt") } catch {}
        let saved = try await journal.read(); XCTAssertEqual(saved?.lastKnownStatus, "completed")
        let changed = try status(record, override: ["completedAt": text(now.addingTimeInterval(1))])
        do { try await journal.recordStatus(changed, serverNow: now.addingTimeInterval(2), expected: record); XCTFail("Changed terminal completion time") } catch {}
        let unchanged = try await journal.read(); XCTAssertEqual(unchanged?.completedAt, saved?.completedAt)
    }
    func testConfirmedLocalCleanupPreservesOtherScopesAndPublicFiles() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let library = ScopedLibrary(directory: dir), staging = AccountScope(environment: .staging, accountID: "fixture-A")
        for scope in [a, b, .guest, staging] { try await library.setFavorite("favorite", value: true, scope: scope) }
        let publicAudio = dir.appending(path: "public-free-audio.mp3"); try Data("public audio".utf8).write(to: publicAudio)
        try await library.removeDeletedAccountData(scope: a)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file(a, in: dir).path))
        for scope in [b, .guest, staging] { XCTAssertTrue(FileManager.default.fileExists(atPath: file(scope, in: dir).path)) }
        XCTAssertEqual(try Data(contentsOf: publicAudio), Data("public audio".utf8))
        do { try await library.setFavorite("late", value: true, scope: a); XCTFail("Deleted scope recreated") } catch {}
        try await library.removeDeletedAccountData(scope: a) // Idempotent.
        do { try await library.removeDeletedAccountData(scope: .guest); XCTFail("Deleted guest") } catch {}
    }
    func testLocalCleanupFailureKeepsReceiptAndCanRetryAfterRelaunch() async throws {
        let dir = try directory(), outside = try directory(); defer { try? FileManager.default.removeItem(at: dir); try? FileManager.default.removeItem(at: outside) }
        let library = ScopedLibrary(directory: dir), store = MemorySecureStore()
        let (model, auth, _, journal, _) = try setup(store)
        model.onDeleteLocalAccount = { try await library.removeDeletedAccountData(scope: $0) }
        try await library.setFavorite("favorite", value: true, scope: a)
        let privateFile = file(a, in: dir), saved = try Data(contentsOf: privateFile), target = outside.appending(path: "keep.json")
        try Data("outside".utf8).write(to: target); try FileManager.default.removeItem(at: privateFile)
        try FileManager.default.createSymbolicLink(at: privateFile, withDestinationURL: target)
        try await auth.signIn(); await model.prepareDeletion(password: "fixture", totp: ""); await model.confirmDeletion()
        XCTAssertEqual(model.deletionStatus, "accepted"); XCTAssertEqual(model.deletionLocalStatusKey, "deletion.local.retry")
        let failed = try await journal.read(); XCTAssertNotNil(failed?.confirmedAt); XCTAssertNotEqual(failed?.localCleanupCompleted, true)
        XCTAssertEqual(try Data(contentsOf: target), Data("outside".utf8))
        try FileManager.default.removeItem(at: privateFile); try saved.write(to: privateFile)
        let freshLibrary = ScopedLibrary(directory: dir), (relaunch, _, _, _, offlineTransport) = try setup(store)
        relaunch.onDeleteLocalAccount = { try await freshLibrary.removeDeletedAccountData(scope: $0) }
        await offlineTransport.setFailStatus(true)
        await relaunch.restore()
        let retried = try await journal.read(); XCTAssertEqual(retried?.receipt, failed?.receipt); XCTAssertEqual(retried?.localCleanupCompleted, true)
        XCTAssertEqual(relaunch.deletionLocalStatusKey, "deletion.local.completed"); XCTAssertFalse(FileManager.default.fileExists(atPath: privateFile.path))
        XCTAssertFalse(relaunch.messageKey.isEmpty) // Failed network status query stays visible.
    }
    func testArchivedConfirmedCleanupIsRetriedAfterNewAccountPreparation() async throws {
        let store = MemorySecureStore(), journal = DeletionJournal(store: store, environment: .development), record = try await confirmed(journal)
        try await journal.recordStatus(status(record), serverNow: now, expected: record)
        _ = try await journal.prepare(accountID: "fixture-B")
        try await journal.recordLocalCleanup(id: record.deletionRequestID)
        let records = try await DeletionJournal(store: store, environment: .development).records()
        XCTAssertEqual(records[1].localCleanupCompleted, true); XCTAssertEqual(records[1].receipt, record.receipt)
        XCTAssertNil(records[0].confirmedAt)
    }
    func testConfirmedDeletionWhileSyncIsWaitingCannotRecreateOrUploadPrivateData() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let library = ScopedLibrary(directory: dir), remote = DeletionWaitingRemote()
        try await library.setFavorite("pending", value: true, scope: a)
        let syncing = Task { try await library.synchronize(scope: a, remote: remote) }
        while !(await remote.entered) { await Task.yield() }
        try await library.removeDeletedAccountData(scope: a)
        await remote.resume()
        do { try await syncing.value; XCTFail("Old synchronization survived deletion") } catch {}
        let writes = await remote.writes; XCTAssertEqual(writes, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file(a, in: dir).path))
    }
    func testArchivedReceiptRemainsQueryableWithoutChangingCurrentRequest() async throws {
        let (_, auth, deletion, journal, transport) = try setup(); try await auth.signIn()
        _ = try await deletion.prepare(); _ = try await deletion.explicitlyConfirm()
        await transport.setDeletionReply("completed", completionOffset: 0)
        _ = try await deletion.queryRecovery(); let oldRecord = try await journal.read(), old = try XCTUnwrap(oldRecord)
        let next = try await journal.prepare(accountID: "fixture-B")
        let status = try await deletion.queryRecovery(id: old.deletionRequestID)
        XCTAssertEqual(status?.status, "completed")
        let current = try await journal.read(); XCTAssertEqual(current, next)
        let records = try await journal.records(); XCTAssertEqual(records[1].receipt, old.receipt)
    }
    func testAccountProgressModelListsAndQueriesArchivedReceiptWhileSignedOut() async throws {
        let (model, auth, deletion, journal, transport) = try setup(); try await auth.signIn()
        _ = try await deletion.prepare(); _ = try await deletion.explicitlyConfirm()
        await transport.setDeletionReply("completed", completionOffset: 0)
        _ = try await deletion.queryRecovery(); let oldRecord = try await journal.read(), old = try XCTUnwrap(oldRecord)
        let next = try await journal.prepare(accountID: "fixture-B")
        await model.queryDeletion(id: old.deletionRequestID)
        XCTAssertTrue(model.deletionQueryIsArchived); XCTAssertEqual(model.deletionStatus, "completed")
        XCTAssertEqual(model.deletionStageKey, "deletion.stage.completed")
        XCTAssertEqual(model.deletionHistory.count, 1); XCTAssertEqual(model.deletionHistory[0].id, old.deletionRequestID)
        XCTAssertNotNil(model.deletionHistory[0].confirmedAt); XCTAssertNotNil(model.deletionHistory[0].receiptExpiresAt)
        XCTAssertEqual(model.scope.accountID, nil)
        let current = try await journal.read(); XCTAssertEqual(current, next)
        let requests = await transport.requests.filter { $0.url?.path.hasSuffix("/status") == true }
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "GET" && $0.value(forHTTPHeaderField: "Authorization")?.hasPrefix("DeletionReceipt ") == true })
    }
    func testStatusWireShapeRejectsMissingNullAndPrivateFieldInjection() async throws {
        let journal = DeletionJournal(store: MemorySecureStore(), environment: .development), record = try await confirmed(journal)
        let original: [String: Any] = ["deletionRequestId": record.deletionRequestID, "status": "accepted", "confirmAccepted": true,
            "receiptExpiresAt": text(now.addingTimeInterval(86400)), "stage": "queued", "confirmedAt": text(now), "completedAt": NSNull()]
        XCTAssertNoThrow(try NativeJSON.decoder().decode(NativeDeletionStatus.self, from: JSONSerialization.data(withJSONObject: original)))
        for omitted in ["completedAt", "confirmedAt", "stage"] {
            var invalid = original; invalid.removeValue(forKey: omitted)
            XCTAssertThrowsError(try NativeJSON.decoder().decode(NativeDeletionStatus.self, from: JSONSerialization.data(withJSONObject: invalid)))
        }
        for injected in ["accountId", "email", "receipt", "balance"] {
            var invalid = original; invalid[injected] = "must not be exposed"
            XCTAssertThrowsError(try NativeJSON.decoder().decode(NativeDeletionStatus.self, from: JSONSerialization.data(withJSONObject: invalid)))
        }
    }
    func testOlderAccountCleanupCannotLabelNewUnconfirmedAccountAsCleared() async throws {
        let store = MemorySecureStore(), journal = DeletionJournal(store: store, environment: .development), old = try await confirmed(journal)
        try await journal.recordStatus(status(old), serverNow: now, expected: old)
        _ = try await journal.prepare(accountID: "fixture-B")
        let (model, _, _, _, transport) = try setup(store)
        model.onDeleteLocalAccount = { _ in }
        await transport.setFailStatus(true); await model.restore()
        XCTAssertEqual(model.deletionLocalStatusKey, "")
        let records = try await journal.records(); XCTAssertEqual(records[1].localCleanupCompleted, true); XCTAssertNil(records[0].confirmedAt)
    }
}
