import XCTest
import Darwin
@testable import StationCatMusic

@MainActor final class KeychainCrashRecoveryTests: XCTestCase {
    let service = "org.stationcat.music.dev.m2.crash-fixture"
    func testAExitAfterDurablePendingWrite() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["M2_CRASH_PROBE"] == "YES", "Explicit process-termination probe only")
        let store = KeychainStore(service: service)
        try await store.remove("auth.development"); try await store.remove("deletion.development")
        let journal = AuthJournal(store: store, environment: .development)
        let saved = CredentialEnvelope(schemaVersion: 1, scope: AccountScope(environment: .development, accountID: "crash-fixture-A"),
            sessionID: "crash-fixture-session", familyID: "crash-fixture-family", generation: 0,
            refreshToken: String(repeating: "T", count: 43), pending: nil, refreshExpiresAt: Date(timeIntervalSince1970: 2_000_000_000), absoluteExpiresAt: Date(timeIntervalSince1970: 2_100_000_000))
        try await journal.install(saved)
        let record = try await journal.prepare(digest: "crash-fixture-digest")
        let deletion = DeletionJournal(store: store, environment: .development)
        let receipt = try await deletion.prepare(accountID: "crash-fixture-A")
        try await store.write(Data(record.pending!.requestID.utf8), key: "expected-request")
        try await store.write(receipt.receipt, key: "expected-receipt")
        print("M2_CRASH_POINT_REACHED: durable refresh and deletion journals written; exiting test-host without cleanup")
        fflush(nil)
        _exit(73)
    }
    func testBRecoverAfterProcessTermination() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["M2_CRASH_PROBE"] == "RECOVER", "Run after the explicit crash probe")
        let store = KeychainStore(service: service)
        let record = try await AuthJournal(store: store, environment: .development).read()
        let expected = try await store.read("expected-request")
        XCTAssertEqual(record?.pending?.requestID, expected.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertNotNil(record?.pending); XCTAssertEqual(record?.generation, 0)
        let journal = DeletionJournal(store: store, environment: .development)
        let deletion = try await journal.read(), expectedReceipt = try await store.read("expected-receipt")
        XCTAssertEqual(deletion?.receipt, expectedReceipt); XCTAssertNotNil(expectedReceipt)
        let action = try await journal.recoveryAction(); XCTAssertEqual(action, .queryStatus(deletion!.deletionRequestID))
        for key in ["auth.development", "deletion.development", "expected-request", "expected-receipt"] { try await store.remove(key) }
    }
}
