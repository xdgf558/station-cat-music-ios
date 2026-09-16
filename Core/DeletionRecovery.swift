import Foundation

// Durable client journal only. No deletion endpoint or destructive service exists in M1.
actor DeletionJournal {
    private let store: any SecureStore
    private let environment: AppEnvironment
    private var busy = false
    private var key: String { "deletion.\(environment.rawValue)" }
    init(store: any SecureStore, environment: AppEnvironment) { self.store = store; self.environment = environment }
    func read() async throws -> DeletionRecoveryEnvelope? {
        guard let data = try await store.read(key) else { return nil }
        guard let record = try? JSONDecoder().decode(DeletionRecoveryEnvelope.self, from: data), record.environment == environment,
              record.receipt.count == 32 else { throw SecureStoreError.corrupt }
        return record
    }
    func prepare(accountID: String? = nil) async throws -> DeletionRecoveryEnvelope {
        guard !busy else { throw APIError.staleResponse }; busy = true; defer { busy = false }
        if let existing = try await read() {
            guard existing.accountID == accountID else { throw APIError.staleResponse }; return existing
        }
        let record = DeletionRecoveryEnvelope(accountID: accountID, environment: environment, deletionRequestID: UUID().uuidString,
            prepareRequestID: UUID().uuidString, receipt: try DeletionReceipt.generate(), scopeVersion: "station-account-v1",
            confirmAttempted: false, lastKnownStatus: "preparing")
        try await store.write(JSONEncoder().encode(record), key: key)
        return record
    }
    func recordPrepared(id: String, scopeVersion: String, prepareUntil: Date, receiptUntil: Date) async throws {
        guard !busy else { throw APIError.staleResponse }; busy = true; defer { busy = false }
        guard var record = try await read(), record.deletionRequestID == id, record.scopeVersion == scopeVersion,
              !record.confirmAttempted, prepareUntil <= receiptUntil else { throw APIError.staleResponse }
        record.prepareExpiresAt = prepareUntil; record.receiptExpiresAt = receiptUntil; record.lastKnownStatus = "prepared"
        try await store.write(JSONEncoder().encode(record), key: key)
    }
    func explicitlyConfirm(scopeVersion: String, now: Date) async throws -> DeletionRecoveryEnvelope {
        guard !busy else { throw APIError.staleResponse }; busy = true; defer { busy = false }
        guard var record = try await read(), !record.confirmAttempted, record.lastKnownStatus == "prepared",
              record.scopeVersion == scopeVersion, let prepared = record.prepareExpiresAt, let receipt = record.receiptExpiresAt,
              now < prepared, now < receipt else { throw APIError.invalidRequest }
        record.confirmRequestID = UUID().uuidString; record.confirmAttempted = true
        try await store.write(JSONEncoder().encode(record), key: key)
        return record
    }
    // Relaunch only yields a status query instruction, never an automatic confirmation.
    func recoveryAction() async throws -> RecoveryAction {
        guard let record = try await read() else { return .none }
        return .queryStatus(record.deletionRequestID)
    }
    enum RecoveryAction: Equatable, Sendable { case none, queryStatus(String) }
}
