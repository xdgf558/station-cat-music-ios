import Foundation
import CryptoKit

nonisolated struct NativeAuthConfiguration: Sendable {
    let environment: AppEnvironment
    let origin: URL
    var callback: URL { origin.appending(path: "auth/mobile/callback") }
    init(environment: AppEnvironment, origin: URL, explicitlyEnabled: Bool) throws {
        guard explicitlyEnabled, [.development, .staging].contains(environment), origin.scheme == "https",
              let host = origin.host, !host.isEmpty, origin.user == nil, origin.password == nil,
              origin.query == nil, origin.fragment == nil, origin.path.isEmpty || origin.path == "/",
              origin.port == nil || origin.port == 443 else { throw APIError.networkDisabled }
        self.environment = environment; self.origin = origin
    }
}
nonisolated struct PKCEFlow: Sendable {
    let verifier: String
    let state: String
    init() throws {
        verifier = try DeletionReceipt.encode(DeletionReceipt.generate())
        state = try DeletionReceipt.encode(DeletionReceipt.generate())
    }
    var challenge: String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    func authorizationURL(_ configuration: NativeAuthConfiguration, locale: String) throws -> URL {
        var c = URLComponents(url: configuration.origin.appending(path: "auth/mobile/authorize"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "client_id", value: "station-cat-ios"), .init(name: "redirect_uri", value: configuration.callback.absoluteString),
                       .init(name: "state", value: state), .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"), .init(name: "locale", value: locale)]
        guard let url = c.url else { throw APIError.invalidRequest }; return url
    }
    func code(from url: URL, configuration: NativeAuthConfiguration) throws -> String {
        guard url.scheme == "https", url.host == configuration.callback.host, url.port == configuration.callback.port,
              url.path == configuration.callback.path, url.fragment == nil, url.user == nil, url.password == nil,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.count == 2, Set(items.map(\.name)) == Set(["code", "state"]),
              items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value,
              code.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else { throw APIError.invalidPayload }
        return code
    }
}
nonisolated protocol AuthenticationBrowser: Sendable {
    @MainActor func authorize(url: URL, callback: URL) async throws -> URL
}
nonisolated struct NativeTokens: Codable, Sendable {
    let accountId: String
    let sessionId: String
    let tokenFamilyId: String
    let generation: Int
    let accessToken: String
    let accessExpiresAt: Date
    let refreshToken: String
    let refreshExpiresAt: Date
    let absoluteExpiresAt: Date
    var refreshRequestId: String?
    var previousGeneration: Int?
    var replayUntil: Date?
    func credential(environment: AppEnvironment, serverNow: Date) throws -> CredentialEnvelope {
        guard !accountId.isEmpty, !sessionId.isEmpty, !tokenFamilyId.isEmpty, generation >= 0,
              accessToken.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
              refreshToken.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
              serverNow < accessExpiresAt, accessExpiresAt <= refreshExpiresAt, refreshExpiresAt <= absoluteExpiresAt else { throw APIError.invalidPayload }
        return CredentialEnvelope(schemaVersion: 1, scope: AccountScope(environment: environment, accountID: accountId), sessionID: sessionId,
                                  familyID: tokenFamilyId, generation: generation, refreshToken: refreshToken, pending: nil,
                                  refreshExpiresAt: refreshExpiresAt, absoluteExpiresAt: absoluteExpiresAt)
    }
}
nonisolated struct NativeResponse<Value: Decodable & Sendable>: Decodable, Sendable {
    let data: Value
    let serverNow: Date
    let requestId: String
}
nonisolated struct NativeFailure: Error, Equatable, Sendable { let code: String; let status: Int }
nonisolated struct NativeErrorEnvelope: Decodable { struct Detail: Decodable { let code: String }; let error: Detail }
nonisolated enum NativeJSON {
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: value) { return date }
            f.formatOptions = [.withInternetDateTime]
            guard let date = f.date(from: value) else { throw APIError.invalidPayload }; return date
        }
        return d
    }
}
actor NativeAuthAPI {
    let configuration: NativeAuthConfiguration
    private let transport: any HTTPTransport
    init(configuration: NativeAuthConfiguration, transport: any HTTPTransport) { self.configuration = configuration; self.transport = transport }
    func request<Value: Decodable & Sendable>(_ path: String, body: [String: String]? = nil, generation: Int? = nil,
                                             authorization: String? = nil, key: String? = nil, method: String = "POST", as: Value.Type) async throws -> NativeResponse<Value> {
        let allowed = ["/auth/token", "/auth/refresh", "/auth/logout", "/auth/reauth", "/me", "/me/deletion-requests/prepare"]
        let dynamic = path.range(of: "^/(me/)?deletion-requests/[A-Za-z0-9_-]{16,128}/(confirm|status)$", options: .regularExpression) != nil
        guard allowed.contains(path) || dynamic else { throw APIError.invalidRequest }
        let url = configuration.origin.appending(path: "api/mobile/v1" + path)
        var request = URLRequest(url: url); request.httpMethod = method; request.timeoutInterval = 5
        if var payload = body?.mapValues({ $0 as Any }) {
            if let generation { payload["generation"] = generation }
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue(authorization, forHTTPHeaderField: "Authorization"); request.setValue(key, forHTTPHeaderField: "Idempotency-Key")
        let result = try await transport.send(request)
        try Task.checkCancellation()
        guard (200..<300).contains(result.status) else {
            if let error = try? JSONDecoder().decode(NativeErrorEnvelope.self, from: result.data) { throw NativeFailure(code: error.error.code, status: result.status) }
            throw APIError.rejected(result.status)
        }
        guard let response = try? NativeJSON.decoder().decode(NativeResponse<Value>.self, from: result.data) else { throw APIError.invalidPayload }
        return response
    }
}
nonisolated struct NativeAcknowledged: Decodable, Sendable { let accepted: Bool }
nonisolated struct RecentAuthentication: Decodable, Sendable { let validUntil: Date }
nonisolated struct NativeAuthContext: Equatable, Sendable { let epoch: Int; let scope: AccountScope; let bearer: String }
actor NativeAuthenticationService: AuthenticationServicing {
    private let configuration: NativeAuthConfiguration
    private let api: NativeAuthAPI
    private let journal: AuthJournal
    private let browser: any AuthenticationBrowser
    private var current: AuthenticationState = .guest
    private var epoch = 0
    private var bearer: String?
    private var accessDeadline: ContinuousClock.Instant?
    private var refreshTask: Task<String, Error>?
    private(set) var coalescedRefreshes = 0
    private var signingIn = false
    init(configuration: NativeAuthConfiguration, api: NativeAuthAPI, journal: AuthJournal, browser: any AuthenticationBrowser) {
        self.configuration = configuration; self.api = api; self.journal = journal; self.browser = browser
    }
    func state() -> AuthenticationState { current }
    func signIn() async throws { try await signIn(locale: "en") }
    func signIn(locale: String) async throws {
        guard !signingIn else { throw APIError.staleResponse }
        signingIn = true; defer { signingIn = false }
        // Switching identities first invalidates all old work and durable credentials.
        try await signOut()
        let ticket = epoch; let journalEpoch = await journal.epoch; let flow = try PKCEFlow()
        let callback = try await browser.authorize(url: flow.authorizationURL(configuration, locale: locale), callback: configuration.callback)
        guard ticket == epoch else { throw APIError.staleResponse }
        let code = try flow.code(from: callback, configuration: configuration)
        let clock = ContinuousClock(); let started = clock.now
        let result = try await api.request("/auth/token", body: ["clientId": "station-cat-ios", "code": code, "codeVerifier": flow.verifier, "redirectUri": configuration.callback.absoluteString], as: NativeTokens.self)
        guard ticket == epoch, result.data.generation == 0 else { throw APIError.staleResponse }
        let credential = try result.data.credential(environment: configuration.environment, serverNow: result.serverNow)
        try await journal.install(credential, expectedEpoch: journalEpoch)
        guard ticket == epoch else { throw APIError.staleResponse }
        try publish(result, started: started, scope: credential.scope)
    }
    private func publish(_ result: NativeResponse<NativeTokens>, started: ContinuousClock.Instant, scope: AccountScope) throws {
        let clock = ContinuousClock(); let elapsed = started.duration(to: clock.now)
        let budget = Duration.seconds(result.data.accessExpiresAt.timeIntervalSince(result.serverNow)) - elapsed - .seconds(2)
        guard budget > .zero else { bearer = nil; accessDeadline = nil; throw APIError.requiresAuthentication }
        bearer = result.data.accessToken; accessDeadline = clock.now.advanced(by: budget); current = .authenticated(scope)
    }
    func restore() async throws {
        let ticket = epoch
        do {
            let saved = try await journal.read()
            guard ticket == epoch else { throw APIError.staleResponse }
            guard saved != nil else { current = .guest; return }
            _ = try await accessToken(forceRefresh: true)
        } catch { if ticket == epoch { current = .unavailable }; throw error } // Protected Keychain or 503 is not a successful logout.
    }
    func accessToken(forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh, let bearer, let accessDeadline, ContinuousClock().now < accessDeadline { return bearer }
        if let refreshTask { coalescedRefreshes += 1; return try await refreshTask.value }
        let ticket = epoch
        let work = Task { try await self.performRefresh(ticket: ticket) }; refreshTask = work
        defer { if ticket == epoch { refreshTask = nil } }
        do { return try await work.value }
        catch { if ticket == epoch { bearer = nil; accessDeadline = nil; current = .unavailable }; throw error }
    }
    private func performRefresh(ticket: Int) async throws -> String {
        guard let old = try await journal.read(), ticket == epoch else { throw APIError.requiresAuthentication }
        let canonical = "station-cat-ios:\(old.generation):\(old.refreshToken)"
        let digest = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
        let pending = try await journal.prepare(digest: digest)
        guard ticket == epoch, let operation = pending.pending else { throw APIError.staleResponse }
        let clock = ContinuousClock(); let started = clock.now
        let result = try await api.request("/auth/refresh", body: ["clientId": "station-cat-ios", "refreshToken": pending.refreshToken, "refreshRequestId": operation.requestID], generation: pending.generation, as: NativeTokens.self)
        guard ticket == epoch, result.data.refreshRequestId == operation.requestID, result.data.previousGeneration == pending.generation,
              let replayUntil = result.data.replayUntil, result.serverNow < replayUntil else { throw APIError.staleResponse }
        let replacement = try result.data.credential(environment: configuration.environment, serverNow: result.serverNow)
        try await journal.complete(expected: pending, replacement: replacement)
        guard ticket == epoch else { throw APIError.staleResponse }
        try publish(result, started: started, scope: replacement.scope)
        return result.data.accessToken
    }
    func reauthenticate(password: String, totp: String) async throws {
        let ticket = epoch; let token = try await accessToken()
        let _: NativeResponse<RecentAuthentication> = try await api.request("/auth/reauth", body: ["password": password, "totpCode": totp], authorization: "Bearer " + token, as: RecentAuthentication.self)
        guard ticket == epoch else { throw APIError.staleResponse }
    }
    func requestContext() async throws -> NativeAuthContext {
        let ticket = epoch; let token = try await accessToken()
        guard ticket == epoch, case let .authenticated(scope) = current else { throw APIError.staleResponse }
        return NativeAuthContext(epoch: ticket, scope: scope, bearer: token)
    }
    func isCurrent(_ context: NativeAuthContext) -> Bool { context.epoch == epoch && current == .authenticated(context.scope) }
    func signOut(ifCurrent context: NativeAuthContext) async throws {
        guard isCurrent(context) else { return }; try await signOut()
    }
    func signOut() async throws {
        epoch += 1; refreshTask?.cancel(); refreshTask = nil
        let ticket = epoch
        let old = bearer; bearer = nil; accessDeadline = nil; current = .unavailable
        let credential = try await journal.logoutReturningCredential()
        if ticket == epoch { current = .guest }
        if let credential {
            // A refresh may already have rotated the old access token. A known refresh token
            // can only revoke its own family, including a just-created next generation.
            do { let _: NativeResponse<NativeAcknowledged> = try await api.request("/auth/logout", body: ["refreshToken": credential.refreshToken], as: NativeAcknowledged.self) }
            catch { throw NativeFailure(code: "LOGOUT_UNCONFIRMED", status: 503) }
        } else if let old {
            // Local invalidation is complete first. No interceptor or automatic refresh on logout failure.
            do { let _: NativeResponse<NativeAcknowledged> = try await api.request("/auth/logout", authorization: "Bearer " + old, as: NativeAcknowledged.self) }
            catch { throw NativeFailure(code: "LOGOUT_UNCONFIRMED", status: 503) }
        }
    }
}
