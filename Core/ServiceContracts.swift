import Foundation

nonisolated struct NativeCapabilities: Decodable, Sendable {
    let musicCatalog: Bool
    let nativeAuthentication: Bool
    let musicPlayback: Bool
    let personalSync: Bool
    let accountDeletion: Bool
    enum CodingKeys: String, CodingKey { case musicCatalog, nativeAuthentication, musicPlayback, personalSync, accountDeletion }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Missing/unknown optional flags do not grant a capability.
        musicCatalog = (try? c.decode(Bool.self, forKey: .musicCatalog)) ?? false
        nativeAuthentication = (try? c.decode(Bool.self, forKey: .nativeAuthentication)) ?? false
        musicPlayback = (try? c.decode(Bool.self, forKey: .musicPlayback)) ?? false
        personalSync = (try? c.decode(Bool.self, forKey: .personalSync)) ?? false
        accountDeletion = (try? c.decode(Bool.self, forKey: .accountDeletion)) ?? false
    }
}
nonisolated enum MusicEntitlementKind: String, Codable, Sendable { case siteVIP = "site_vip", musicSubscription = "music_subscription" }
nonisolated enum AuthenticationState: Equatable, Sendable { case guest, unavailable, authenticated(AccountScope) }
nonisolated protocol AuthenticationServicing: Sendable {
    func state() async -> AuthenticationState
    func signIn() async throws
    func signOut() async throws
}
actor UnavailableAuthenticationService: AuthenticationServicing {
    func state() -> AuthenticationState { .guest }
    func signIn() throws { throw APIError.networkDisabled }
    func signOut() {} // Mock has no real session; it is not a server logout implementation.
}
nonisolated protocol EntitlementServicing: Sendable {
    func revalidate(scope: AccountScope) async throws
}
actor UnavailableEntitlementService: EntitlementServicing {
    func revalidate(scope: AccountScope) throws { throw APIError.unavailable }
}
