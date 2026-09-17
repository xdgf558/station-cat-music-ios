import Foundation

nonisolated protocol CatalogProviding: Sendable { func catalog() async throws -> Catalog }
extension APIClient: CatalogProviding {}
nonisolated struct LyricLine: Codable, Equatable, Sendable { let startSeconds: Double; let text: String }
nonisolated struct MusicLyrics: Codable, Sendable {
    let kind: String; let text: String; let lines: [LyricLine]; let audioVersion: Int
    func current(at seconds: Double) -> Int? { lines.lastIndex { $0.startSeconds <= seconds } }
}
nonisolated struct TrackDetail: Codable, Sendable {
    let track: Track; let summary: String; let coverUrl: URL?; let lyrics: MusicLyrics
    let genres: [String]; let moods: [String]; let previewAvailable: Bool
    let previewSourceStartSeconds: Double?; let previewDurationSeconds: Double?
}
nonisolated struct MusicCollection: Codable, Identifiable, Sendable {
    let id: String; let slug: String; let title: String; let description: String; let version: Int
    let tracks: [Track]; let nextCursor: String?
}
nonisolated struct FeaturedMusic: Codable, Sendable { let tracks: [Track]; let collections: [MusicCollection] }
nonisolated struct AuthorizedPlayback: Sendable {
    let grant: PlaybackGrant; let serverNow: Date; let context: NativeAuthContext?
    let scope: AccountScope
}
nonisolated protocol PlaybackAuthorizing: Sendable {
    func authorize(track: Track, variant: String) async throws -> AuthorizedPlayback
    func isCurrent(_ authorization: AuthorizedPlayback) async -> Bool
    func bearer(for authorization: AuthorizedPlayback, refresh: Bool) async throws -> String?
}
actor NativeMusicAPI: CatalogProviding, PlaybackAuthorizing {
    let configuration: NativeAuthConfiguration
    private let transport: any HTTPTransport
    private let auth: NativeAuthenticationService?
    private var locale = "en"
    func setLocale(_ value: String) { locale = ["en", "zh-Hans", "zh-Hant", "ja"].contains(value) ? value : "en" }
    init(configuration: NativeAuthConfiguration, explicitlyEnabled: Bool, transport: any HTTPTransport, auth: NativeAuthenticationService? = nil) throws {
        guard explicitlyEnabled else { throw APIError.networkDisabled }
        self.configuration = configuration; self.transport = transport; self.auth = auth
    }
    private func request<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = [], body: Data? = nil, context: NativeAuthContext? = nil, as: T.Type) async throws -> NativeResponse<T> {
        guard path.hasPrefix("/music/"), !path.contains(".."), !path.contains("?"), !path.contains("#") else { throw APIError.invalidRequest }
        var components = URLComponents(url: configuration.origin.appending(path: "api/mobile/v1" + path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!); request.httpMethod = body == nil ? "GET" : "POST"; request.timeoutInterval = 5
        request.httpBody = body; if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let context { request.setValue("Bearer " + context.bearer, forHTTPHeaderField: "Authorization") }
        let result = try await transport.send(request); try Task.checkCancellation()
        if let context { guard await auth?.isCurrent(context) == true else { throw APIError.staleResponse } }
        guard result.status == 200 else { throw APIError.rejected(result.status) }
        return try NativeJSON.decoder().decode(NativeResponse<T>.self, from: result.data)
    }
    func catalog() async throws -> Catalog {
        var items: [Track] = [], cursor: String?, seen = Set<String>()
        repeat {
            var query = [URLQueryItem(name: "limit", value: "100"), .init(name: "locale", value: locale)]
            if let cursor { guard seen.insert(cursor).inserted else { throw APIError.invalidPayload }; query.append(.init(name: "cursor", value: cursor)) }
            let result = try await request("/music/catalog", query: query, as: Catalog.self)
            items += result.data.items; cursor = result.data.nextCursor
            guard items.count <= 500, seen.count <= 5 else { throw APIError.invalidPayload }
        } while cursor != nil
        guard Set(items.map(\.id)).count == items.count else { throw APIError.invalidPayload }
        return Catalog(items: items, nextCursor: nil)
    }
    func detail(_ track: Track, locale: String) async throws -> TrackDetail {
        guard UUID(uuidString: track.id) != nil else { throw APIError.invalidRequest }
        let r = try await request("/music/tracks/" + track.id, query: [.init(name: "locale", value: locale)], as: TrackDetail.self)
        guard r.data.track.id == track.id, r.data.track.audioVersion == track.audioVersion, r.data.lyrics.audioVersion == track.audioVersion else { throw APIError.staleResponse }
        return r.data
    }
    func collection(_ collection: MusicCollection) async throws -> MusicCollection {
        guard collection.slug.range(of: "^[a-z0-9-]{1,100}$", options: .regularExpression) != nil else { throw APIError.invalidRequest }
        var cursor: String?, seen = Set<String>(), tracks: [Track] = []
        var current: MusicCollection = collection
        repeat {
            var query = [URLQueryItem(name: "limit", value: "100"), .init(name: "locale", value: locale)]
            if let cursor { guard seen.insert(cursor).inserted else { throw APIError.invalidPayload }; query.append(.init(name: "cursor", value: cursor)) }
            let result = try await request("/music/collections/" + collection.slug, query: query, as: MusicCollection.self).data
            guard result.id == collection.id, result.version == collection.version else { throw APIError.staleResponse }
            tracks += result.tracks; cursor = result.nextCursor; current = result
            guard tracks.count <= 500, seen.count <= 5 else { throw APIError.invalidPayload }
        } while cursor != nil
        return MusicCollection(id: current.id, slug: current.slug, title: current.title, description: current.description, version: current.version, tracks: tracks, nextCursor: nil)
    }
    func featured() async throws -> FeaturedMusic { try await request("/music/featured", query: [.init(name: "locale", value: locale)], as: FeaturedMusic.self).data }
    func authorize(track: Track, variant: String) async throws -> AuthorizedPlayback {
        guard UUID(uuidString: track.id) != nil, ["full", "preview"].contains(variant) else { throw APIError.invalidRequest }
        let before = await auth?.state()
        let context: NativeAuthContext?
        if case .authenticated = before { context = try await auth?.requestContext(minimumValidity: 65) }
        else if before == .unavailable { throw APIError.requiresAuthentication }
        else { context = nil }
        let body = try JSONSerialization.data(withJSONObject: ["audioVersion": track.audioVersion, "variant": variant])
        let response = try await request("/music/tracks/" + track.id + "/playback-grants", body: body, context: context, as: PlaybackGrant.self)
        let scope = context?.scope ?? AccountScope(environment: configuration.environment, accountID: nil)
        guard response.data.variant == variant else { throw APIError.invalidPayload }
        try response.data.validate(serverNow: response.serverNow, scope: scope, session: context?.sessionID, track: track, allowedHosts: [configuration.origin.host!])
        let result = AuthorizedPlayback(grant: response.data, serverNow: response.serverNow, context: context, scope: scope)
        guard await isCurrent(result) else { throw APIError.staleResponse }
        return result
    }
    func isCurrent(_ authorization: AuthorizedPlayback) async -> Bool {
        if let context = authorization.context { return await auth?.isCurrent(context) == true }
        // Guest responses arriving after sign-in must not restart playback.
        guard let auth else { return true }; return await auth.state() == .guest
    }
    func bearer(for authorization: AuthorizedPlayback, refresh: Bool) async throws -> String? {
        guard await isCurrent(authorization) else { throw APIError.staleResponse }
        guard authorization.grant.authMode == .sessionBearer else { return nil }
        guard let auth, let previous = authorization.context else { throw APIError.requiresAuthentication }
        if refresh { _ = try await auth.accessToken(forceRefresh: true) }
        let current = try await auth.requestContext()
        guard current.epoch == previous.epoch, current.scope == previous.scope, current.sessionID == previous.sessionID else { throw APIError.staleResponse }
        return current.bearer
    }
}
