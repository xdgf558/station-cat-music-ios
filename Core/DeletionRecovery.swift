import Foundation

// One atomic Keychain item preserves active and terminal progress receipts.
nonisolated private struct DeletionJournalState: Codable {
    var schema = 2
    var current: DeletionRecoveryEnvelope
    var archives: [DeletionRecoveryEnvelope] = []
}
actor DeletionJournal {
    private let store: any SecureStore
    private let environment: AppEnvironment
    private var busy = false
    private var key: String { "deletion.\(environment.rawValue)" }
    init(store: any SecureStore, environment: AppEnvironment) { self.store = store; self.environment = environment }
    private func state() async throws -> DeletionJournalState? {
        guard let data = try await store.read(key) else { return nil }
        let decoder = JSONDecoder()
        let state: DeletionJournalState
        if let modern = try? decoder.decode(DeletionJournalState.self, from: data) { state = modern }
        else if let legacy = try? decoder.decode(DeletionRecoveryEnvelope.self, from: data) { state = DeletionJournalState(current: legacy) }
        else { throw SecureStoreError.corrupt }
        guard state.schema == 2, ([state.current] + state.archives).allSatisfy({ $0.environment == environment && $0.receipt.count == 32 }),
              Set(([state.current] + state.archives).map(\.deletionRequestID)).count == state.archives.count + 1,
              state.archives.allSatisfy({ ["completed", "preparation_expired"].contains($0.lastKnownStatus) }) else { throw SecureStoreError.corrupt }
        return state
    }
    private func save(_ state: DeletionJournalState) async throws { try await store.write(JSONEncoder().encode(state), key: key) }
    func read() async throws -> DeletionRecoveryEnvelope? { try await state()?.current }
    func records() async throws -> [DeletionRecoveryEnvelope] {
        guard let state = try await state() else { return [] }
        return [state.current] + state.archives
    }
    func prepare(accountID: String? = nil) async throws -> DeletionRecoveryEnvelope {
        guard !busy else { throw APIError.staleResponse }; busy = true; defer { busy = false }
        let previous = try await state()
        if let existing = previous?.current, !["completed", "preparation_expired"].contains(existing.lastKnownStatus) {
            guard existing.accountID == accountID else { throw APIError.staleResponse }; return existing
        }
        let record = DeletionRecoveryEnvelope(accountID: accountID, environment: environment, deletionRequestID: UUID().uuidString,
            prepareRequestID: UUID().uuidString, receipt: try DeletionReceipt.generate(), scopeVersion: "station-account-v1",
            confirmAttempted: false, lastKnownStatus: "preparing")
        // The previous terminal receipt and new intent publish together, never delete-then-add.
        var replacement = DeletionJournalState(current: record, archives: previous?.archives ?? [])
        if let previous { replacement.archives.append(previous.current) }
        try await save(replacement)
        return record
    }
    func recordPrepared(id: String, scopeVersion: String, prepareUntil: Date, receiptUntil: Date) async throws {
        guard !busy else { throw APIError.staleResponse }; busy = true; defer { busy = false }
        guard var state = try await state(), state.current.deletionRequestID == id, state.current.scopeVersion == scopeVersion,
              !state.current.confirmAttempted, prepareUntil <= receiptUntil else { throw APIError.staleResponse }
        state.current.prepareExpiresAt = prepareUntil; state.current.receiptExpiresAt = receiptUntil; state.current.lastKnownStatus = "prepared"
        try await save(state)
    }
    func explicitlyConfirm(scopeVersion: String, now: Date) async throws -> DeletionRecoveryEnvelope {
        guard !busy else { throw APIError.staleResponse }; busy = true; defer { busy = false }
        guard var state = try await state(), !state.current.confirmAttempted, state.current.lastKnownStatus == "prepared",
              state.current.scopeVersion == scopeVersion, let prepared = state.current.prepareExpiresAt, let receipt = state.current.receiptExpiresAt,
              now < prepared, now < receipt else { throw APIError.invalidRequest }
        state.current.confirmRequestID = UUID().uuidString; state.current.confirmAttempted = true
        try await save(state)
        return state.current
    }
    func recordStatus(_ result: NativeDeletionStatus, serverNow: Date, expected: DeletionRecoveryEnvelope) async throws {
        guard !busy else { throw APIError.staleResponse }; busy = true; defer { busy = false }
        try result.validate(record: expected, serverNow: serverNow)
        guard var state = try await state() else { throw APIError.staleResponse }
        let archive = state.archives.firstIndex { $0.deletionRequestID == expected.deletionRequestID }
        var current = archive.map { state.archives[$0] } ?? state.current
        guard current.deletionRequestID == expected.deletionRequestID, current.receipt == expected.receipt else { throw APIError.staleResponse }
        try result.validate(record: current, serverNow: serverNow)
        if ["completed", "preparation_expired"].contains(current.lastKnownStatus), current.lastKnownStatus != result.status { throw APIError.staleResponse }
        current.lastKnownStatus = result.status; current.receiptExpiresAt = result.receiptExpiresAt
        if let deadline = result.prepareExpiresAt { current.prepareExpiresAt = deadline }
        current.confirmedAt = result.confirmedAt; current.completedAt = result.completedAt
        if let archive { state.archives[archive] = current } else { state.current = current }
        try await save(state)
    }
    func recordLocalCleanup(id: String) async throws {
        guard !busy else { throw APIError.staleResponse }; busy = true; defer { busy = false }
        guard var state = try await state() else { throw APIError.staleResponse }
        if state.current.deletionRequestID == id, state.current.confirmedAt != nil { state.current.localCleanupCompleted = true }
        else if let index = state.archives.firstIndex(where: { $0.deletionRequestID == id && $0.confirmedAt != nil }) { state.archives[index].localCleanupCompleted = true }
        else { throw APIError.staleResponse }
        try await save(state)
    }
    // Relaunch only yields a status query instruction, never an automatic confirmation.
    func recoveryAction() async throws -> RecoveryAction {
        guard let record = try await read() else { return .none }
        return .queryStatus(record.deletionRequestID)
    }
    enum RecoveryAction: Equatable, Sendable { case none, queryStatus(String) }
}
