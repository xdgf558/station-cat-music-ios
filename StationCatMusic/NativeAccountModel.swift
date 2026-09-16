import SwiftUI
import Observation

@MainActor @Observable final class NativeAccountModel {
    let auth: NativeAuthenticationService?
    let deletion: NativeDeletionService?
    var scope: AccountScope = .guest
    var busy = false
    var messageKey = ""
    var deletionStatus = ""
    var confirmationReady = false
    var enabled: Bool { auth != nil }
    init(auth: NativeAuthenticationService? = nil, deletion: NativeDeletionService? = nil) { self.auth = auth; self.deletion = deletion }
    static func configured(environment: AppEnvironment) -> NativeAccountModel {
        // No configured host or entitlement is shipped. A separate approved isolated configuration is required.
        guard Bundle.main.object(forInfoDictionaryKey: "StationNativeAuthEnabled") as? String == "YES",
              let value = Bundle.main.object(forInfoDictionaryKey: "StationNativeAuthOrigin") as? String, let origin = URL(string: value),
              let config = try? NativeAuthConfiguration(environment: environment, origin: origin, explicitlyEnabled: true) else { return NativeAccountModel() }
        let store = KeychainStore(service: "org.stationcat.music.native.\(environment.rawValue)")
        let api = NativeAuthAPI(configuration: config, transport: URLSessionTransport())
        let auth = NativeAuthenticationService(configuration: config, api: api, journal: AuthJournal(store: store, environment: environment), browser: SystemAuthenticationBrowser())
        return NativeAccountModel(auth: auth, deletion: NativeDeletionService(journal: DeletionJournal(store: store, environment: environment), auth: auth, api: api))
    }
    private func updateScope() async {
        if case let .authenticated(value) = await auth?.state() { scope = value } else { scope = .guest }
    }
    private func run(_ action: () async throws -> Void) async {
        guard !busy, enabled else { return }; busy = true; messageKey = ""; defer { busy = false }
        do { try await action() }
        catch is CancellationError { messageKey = "authCancelled" }
        catch let error as NativeFailure { messageKey = "error." + error.code.lowercased() }
        catch { messageKey = "authRetry" }
        await updateScope()
    }
    func restore() async { await run { try await auth?.restore(); if let status = try await deletion?.queryRecovery() { deletionStatus = status.status } } }
    func signIn(locale: String) async { await run { confirmationReady = false; try await auth?.signIn(locale: locale) } }
    func signOut() async { await run { confirmationReady = false; try await auth?.signOut() } }
    func prepareDeletion(password: String, totp: String) async {
        await run {
            confirmationReady = false
            try await auth?.reauthenticate(password: password, totp: totp)
            guard let result = try await deletion?.prepare() else { throw APIError.unavailable }
            deletionStatus = result.status; confirmationReady = result.status == "prepared"
        }
    }
    func confirmDeletion() async {
        await run {
            confirmationReady = false
            guard let result = try await deletion?.explicitlyConfirm() else { throw APIError.unavailable }
            deletionStatus = result.status
        }
    }
    func queryDeletion() async {
        await run { if let result = try await deletion?.queryRecovery() { deletionStatus = result.status } }
    }
}
