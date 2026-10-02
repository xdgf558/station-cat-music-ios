import Foundation

nonisolated struct DeletionReceiptSummary: Identifiable, Sendable {
    let id: String
    let status: String
    let confirmedAt: Date?
    let completedAt: Date?
    let receiptExpiresAt: Date?
}
nonisolated private struct DeletionField: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
nonisolated struct NativeDeletionStatus: Decodable, Sendable {
    let deletionRequestId: String
    let status: String
    let confirmAccepted: Bool
    let receiptExpiresAt: Date
    let scopeVersion: String?
    let prepareExpiresAt: Date?
    let stage: String?
    let confirmedAt: Date?
    let completedAt: Date?
    private enum CodingKeys: String, CodingKey { case deletionRequestId, status, confirmAccepted, receiptExpiresAt, scopeVersion, prepareExpiresAt, stage, confirmedAt, completedAt }
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: DeletionField.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        status = try values.decode(String.self, forKey: .status)
        let required: Set<String>
        switch status {
        case "prepared": required = ["deletionRequestId", "status", "confirmAccepted", "receiptExpiresAt", "scopeVersion", "prepareExpiresAt"]
        case "preparation_expired": required = ["deletionRequestId", "status", "confirmAccepted", "receiptExpiresAt"]
        case "accepted", "processing", "retrying", "attention_required", "completed": required = ["deletionRequestId", "status", "confirmAccepted", "receiptExpiresAt", "stage", "confirmedAt", "completedAt"]
        default: throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown deletion status"))
        }
        guard Set(fields.allKeys.map(\.stringValue)) == required else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid deletion receipt fields"))
        }
        deletionRequestId = try values.decode(String.self, forKey: .deletionRequestId)
        confirmAccepted = try values.decode(Bool.self, forKey: .confirmAccepted)
        receiptExpiresAt = try values.decode(Date.self, forKey: .receiptExpiresAt)
        scopeVersion = try values.decodeIfPresent(String.self, forKey: .scopeVersion)
        prepareExpiresAt = try values.decodeIfPresent(Date.self, forKey: .prepareExpiresAt)
        stage = try values.decodeIfPresent(String.self, forKey: .stage)
        confirmedAt = try values.decodeIfPresent(Date.self, forKey: .confirmedAt)
        completedAt = try values.decodeIfPresent(Date.self, forKey: .completedAt)
    }
    var stageMessageKey: String? {
        guard let stage, ["queued", "credentials", "private_data", "comments", "identity", "verify", "retention_policy_review", "financial_review", "external_cleanup", "backup_review", "completed"].contains(stage) else { return nil }
        return "deletion.stage." + stage
    }
    func validate(record: DeletionRecoveryEnvelope, serverNow: Date) throws {
        guard deletionRequestId == record.deletionRequestID, receiptExpiresAt > serverNow,
              receiptExpiresAt <= serverNow.addingTimeInterval(14 * 86400),
              record.receiptExpiresAt == nil || record.receiptExpiresAt == receiptExpiresAt else { throw APIError.invalidPayload }
        // Once accepted, confirmation is irreversible, including while local cleanup is pending.
        if let previousConfirmation = record.confirmedAt {
            guard confirmAccepted, confirmedAt == previousConfirmation else { throw APIError.invalidPayload }
        }
        switch status {
        case "prepared":
            guard !confirmAccepted, confirmedAt == nil, completedAt == nil, stage == nil,
                  scopeVersion == record.scopeVersion, let deadline = prepareExpiresAt,
                  deadline > serverNow, deadline <= receiptExpiresAt,
                  deadline <= serverNow.addingTimeInterval(600) else { throw APIError.invalidPayload }
        case "preparation_expired":
            guard !confirmAccepted, confirmedAt == nil, completedAt == nil, stage == nil,
                  scopeVersion == nil, prepareExpiresAt == nil else { throw APIError.invalidPayload }
        case "accepted", "processing", "retrying", "attention_required", "completed":
            guard record.confirmAttempted, confirmAccepted, scopeVersion == nil, prepareExpiresAt == nil,
                  let stage, !stage.isEmpty, stage.count <= 200, let confirmedAt,
                  confirmedAt <= serverNow, confirmedAt < receiptExpiresAt,
                  record.prepareExpiresAt.map({ confirmedAt < $0 }) ?? false,
                  record.confirmedAt == nil || record.confirmedAt == confirmedAt else { throw APIError.invalidPayload }
            if status == "completed" {
                guard stage == "completed", let completedAt, completedAt >= confirmedAt, completedAt <= serverNow,
                      record.completedAt == nil || record.completedAt == completedAt else { throw APIError.invalidPayload }
            } else { guard completedAt == nil else { throw APIError.invalidPayload } }
        default: throw APIError.invalidPayload
        }
    }
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
        try r.validate(record: record, serverNow: response.serverNow)
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
            try await journal.recordStatus(result.data, serverNow: result.serverNow, expected: confirmed)
            guard result.data.confirmAccepted else { throw APIError.invalidPayload }
            try await auth.signOut(ifCurrent: context)
            return result.data
        } catch {
            // A lost response can already mean accepted. Persisted confirmation never gets auto-retried.
            try? await auth.signOut(ifCurrent: context)
            throw error
        }
    }
    func queryRecovery(id: String? = nil) async throws -> NativeDeletionStatus? {
        guard !busy else { throw APIError.staleResponse }; busy = true; defer { busy = false }
        let record: DeletionRecoveryEnvelope?
        if let id {
            record = try await journal.records().first { $0.deletionRequestID == id }
            guard record != nil else { throw APIError.invalidRequest }
        } else { record = try await journal.read() }
        guard let record else { return nil }
        let result = try await api.request("/deletion-requests/\(record.deletionRequestID)/status",
            authorization: "DeletionReceipt " + (try DeletionReceipt.encode(record.receipt)), method: "GET", as: NativeDeletionStatus.self)
        try await journal.recordStatus(result.data, serverNow: result.serverNow, expected: record)
        // Relaunch is query-only, never prepare/confirm or a new receipt. No account credentials needed.
        return result.data
    }
    func confirmedRecords() async throws -> [DeletionRecoveryEnvelope] {
        try await journal.records().filter { $0.confirmedAt != nil && $0.accountID != nil }
    }
    func earlierReceipts() async throws -> [DeletionReceiptSummary] {
        try await journal.records().dropFirst().reversed().map {
            DeletionReceiptSummary(id: $0.deletionRequestID, status: $0.lastKnownStatus, confirmedAt: $0.confirmedAt,
                completedAt: $0.completedAt, receiptExpiresAt: $0.receiptExpiresAt)
        }
    }
    func recordLocalCleanup(id: String) async throws { try await journal.recordLocalCleanup(id: id) }
    func currentReceiptID() async throws -> String? { try await journal.read()?.deletionRequestID }
}
