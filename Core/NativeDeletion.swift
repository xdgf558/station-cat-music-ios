import Foundation

nonisolated struct NativeDeletionStatus: Decodable, Sendable {
    let deletionRequestId: String
    let status: String
    let confirmAccepted: Bool
    let receiptExpiresAt: Date
    let scopeVersion: String?
    let prepareExpiresAt: Date?
    let stage: String?
}
actor NativeDeletionService {
    private let journal: DeletionJournal
    private let auth: NativeAuthenticationService
    private let api: NativeAuthAPI
    private var preparedDeadline: ContinuousClock.Instant?
    private var busy = false
    init(journal: DeletionJournal, auth: NativeAuthenticationService, api: NativeAuthAPI) { self.journal = journal; self.auth = auth; self.api = api }
    func prepare() async throws -> NativeDeletionStatus {
        guard !busy else { throw APIError.staleResponse }; busy = true; defer { busy = false }
        let context = try await auth.requestContext()
        guard let account = context.scope.accountID else { throw APIError.requiresAuthentication }
        let record = try await journal.prepare(accountID: account)
        guard !record.confirmAttempted else { throw APIError.invalidRequest }
        let started = ContinuousClock().now
        let result = try await api.request("/me/deletion-requests/prepare", body: ["deletionRequestId": record.deletionRequestID,
            "deletionReceiptHash": try DeletionReceipt.hash(record.receipt), "scopeVersion": record.scopeVersion], authorization: "Bearer " + context.bearer,
            key: record.prepareRequestID, as: NativeDeletionStatus.self)
        guard await auth.isCurrent(context) else { throw APIError.staleResponse }
        try await acceptPrepared(result, record: record, started: started)
        return result.data
    }
    private func acceptPrepared(_ response: NativeResponse<NativeDeletionStatus>, record: DeletionRecoveryEnvelope, started: ContinuousClock.Instant) async throws {
        let r = response.data
        guard r.deletionRequestId == record.deletionRequestID, r.status == "prepared", !r.confirmAccepted,
              r.scopeVersion == record.scopeVersion, let expires = r.prepareExpiresAt, response.serverNow < expires,
              expires <= r.receiptExpiresAt else { throw APIError.invalidPayload }
        try await journal.recordPrepared(id: r.deletionRequestId, scopeVersion: record.scopeVersion, prepareUntil: expires, receiptUntil: r.receiptExpiresAt)
        let now = ContinuousClock().now
        let budget = Duration.seconds(expires.timeIntervalSince(response.serverNow)) - started.duration(to: now) - .seconds(2)
        guard budget > .zero else { throw APIError.invalidPayload }; preparedDeadline = now.advanced(by: budget)
    }
    func explicitlyConfirm() async throws -> NativeDeletionStatus {
        guard !busy else { throw APIError.staleResponse }; busy = true; defer { busy = false }
        let context = try await auth.requestContext()
        guard let deadline = preparedDeadline, ContinuousClock().now < deadline,
              let record = try await journal.read(), let account = record.accountID,
              context.scope == AccountScope(environment: record.environment, accountID: account),
              let expiry = record.prepareExpiresAt else { throw APIError.requiresAuthentication }
        // Deadline was projected from serverNow + monotonic time. Device wall clock is not authority.
        let confirmed = try await journal.explicitlyConfirm(scopeVersion: record.scopeVersion, now: expiry.addingTimeInterval(-1))
        preparedDeadline = nil
        guard await auth.isCurrent(context) else { throw APIError.staleResponse }
        do {
            let result = try await api.request("/me/deletion-requests/\(record.deletionRequestID)/confirm", body: ["confirmedScopeVersion": record.scopeVersion],
                authorization: "Bearer " + context.bearer, key: confirmed.confirmRequestID, as: NativeDeletionStatus.self)
            guard result.data.deletionRequestId == record.deletionRequestID, result.data.confirmAccepted else { throw APIError.invalidPayload }
            try await auth.signOut(ifCurrent: context)
            return result.data
        } catch {
            // A lost response can already mean accepted. Persisted confirmation never gets auto-retried.
            try? await auth.signOut(ifCurrent: context)
            throw error
        }
    }
    func queryRecovery() async throws -> NativeDeletionStatus? {
        guard let record = try await journal.read() else { return nil }
        let result = try await api.request("/deletion-requests/\(record.deletionRequestID)/status",
            authorization: "DeletionReceipt " + (try DeletionReceipt.encode(record.receipt)), method: "GET", as: NativeDeletionStatus.self)
        guard result.data.deletionRequestId == record.deletionRequestID,
              ["prepared", "preparation_expired", "accepted", "processing", "retrying", "attention_required", "completed"].contains(result.data.status) else { throw APIError.invalidPayload }
        // Relaunch is query-only, never prepare/confirm or a new receipt. No account credentials needed.
        return result.data
    }
}
