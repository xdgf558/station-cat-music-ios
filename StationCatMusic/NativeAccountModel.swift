import SwiftUI
import Observation

@MainActor @Observable final class NativeAccountModel {
    let auth: NativeAuthenticationService?
    let deletion: NativeDeletionService?
    var scope: AccountScope = .guest
    var onInvalidate: (@MainActor () -> Void)?
    var onDeleteLocalAccount: (@MainActor (AccountScope) async throws -> Void)?
    var busy = false
    var messageKey = ""
    var deletionStatus = ""
    var deletionStageKey = ""
    var deletionLocalStatusKey = ""
    var deletionHistory: [DeletionReceiptSummary] = []
    var deletionQueryIsArchived = false
    private var displayedDeletionRequestID: String?
    var confirmationReady = false
    var enabled: Bool { auth != nil }
    var deletionEnabled: Bool { deletion != nil }
    let environment: AppEnvironment
    var isolatedAuthentication: Bool { environment == .development || environment == .staging }
    init(auth: NativeAuthenticationService? = nil, deletion: NativeDeletionService? = nil, environment: AppEnvironment = .mock) {
        self.auth = auth; self.deletion = deletion; self.environment = environment
        scope = AccountScope(environment: environment, accountID: nil)
    }
    static func configured(runtime: NativeRuntimeConfiguration) -> NativeAccountModel {
        let environment = runtime.environment
        guard let config = runtime.authentication else { return NativeAccountModel(environment: environment) }
        let store = KeychainStore(service: "org.stationcat.music.native.\(environment.rawValue)")
        let api = NativeAuthAPI(configuration: config, transport: URLSessionTransport())
        let auth = NativeAuthenticationService(configuration: config, api: api, journal: AuthJournal(store: store, environment: environment), browser: SystemAuthenticationBrowser())
        let deletion = config.accountDeletionAllowed ? NativeDeletionService(journal: DeletionJournal(store: store, environment: environment), auth: auth, api: api) : nil
        return NativeAccountModel(auth: auth, deletion: deletion, environment: environment)
    }
    private func updateScope() async {
        if case let .authenticated(value) = await auth?.state() { scope = value } else { scope = AccountScope(environment: environment, accountID: nil) }
    }
    private func run(_ action: () async throws -> Void) async {
        guard !busy, enabled else { return }; busy = true; messageKey = ""; defer { busy = false }
        do { try await action() }
        catch is CancellationError { messageKey = "authCancelled" }
        catch let error as NativeFailure { messageKey = "error." + error.code.lowercased() }
        catch { messageKey = "authRetry" }
        await updateScope()
    }
    private func accept(_ status: NativeDeletionStatus) {
        displayedDeletionRequestID = status.deletionRequestId
        deletionStatus = status.status; deletionStageKey = status.stageMessageKey ?? ""
    }
    private func cleanConfirmedLocalData() async {
        guard let deletion else { return }
        do {
            deletionHistory = try await deletion.earlierReceipts()
            guard let onDeleteLocalAccount else { return }
            if displayedDeletionRequestID == nil { displayedDeletionRequestID = try await deletion.currentReceiptID() }
            let records = try await deletion.confirmedRecords()
            var failed = false
            for record in records {
                guard let accountID = record.accountID else { continue }
                // Reassert the write barrier after every process restart, even after an earlier cleanup.
                do {
                    try await onDeleteLocalAccount(AccountScope(environment: record.environment, accountID: accountID))
                    if record.localCleanupCompleted != true { try await deletion.recordLocalCleanup(id: record.deletionRequestID) }
                } catch { failed = true }
            }
            deletionLocalStatusKey = failed ? "deletion.local.retry" : records.contains(where: { $0.deletionRequestID == displayedDeletionRequestID }) ? "deletion.local.completed" : ""
        } catch { deletionLocalStatusKey = "deletion.local.retry" }
    }
    func restore() async {
        await run {
            await cleanConfirmedLocalData()
            try await auth?.restore()
            if let status = try await deletion?.queryRecovery() { accept(status) }
            await cleanConfirmedLocalData()
        }
    }
    func signIn(locale: String) async { await run { onInvalidate?(); confirmationReady = false; try await auth?.signIn(locale: locale) } }
    func signOut() async { await run { onInvalidate?(); confirmationReady = false; try await auth?.signOut() } }
    func prepareDeletion(password: String, totp: String) async {
        guard deletionEnabled else { return }
        await run {
            confirmationReady = false
            try await auth?.reauthenticate(password: password, totp: totp)
            guard let result = try await deletion?.prepare() else { throw APIError.unavailable }
            accept(result); deletionQueryIsArchived = false; confirmationReady = result.status == "prepared"
            await cleanConfirmedLocalData()
        }
    }
    func confirmDeletion() async {
        guard deletionEnabled else { return }
        await run {
            confirmationReady = false
            onInvalidate?()
            do {
                guard let result = try await deletion?.explicitlyConfirm() else { throw APIError.unavailable }
                accept(result)
            } catch {
                await cleanConfirmedLocalData()
                throw error
            }
            await cleanConfirmedLocalData()
        }
    }
    func queryDeletion(id: String? = nil) async {
        guard deletionEnabled else { return }
        await run {
            if id != nil { confirmationReady = false }
            // An already-confirmed cleanup is independent of a later network outage/expired receipt.
            await cleanConfirmedLocalData()
            if let result = try await deletion?.queryRecovery(id: id) { accept(result); deletionQueryIsArchived = id != nil }
            await cleanConfirmedLocalData()
        }
    }
}
