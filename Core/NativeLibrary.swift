import Foundation

actor NativeLibraryAPI: LibraryRemote {
    private let configuration: NativeAuthConfiguration
    private let auth: NativeAuthenticationService
    private let transport: any HTTPTransport
    init(configuration: NativeAuthConfiguration, explicitlyEnabled: Bool, auth: NativeAuthenticationService, transport: any HTTPTransport) throws {
        guard explicitlyEnabled else { throw APIError.networkDisabled }
        self.configuration = configuration; self.auth = auth; self.transport = transport
    }
    private func request<T: Decodable & Sendable>(_ path: String, method: String = "GET", body: [String: Any]? = nil, scope: AccountScope, as type: T.Type) async throws -> T {
        let context = try await auth.requestContext()
        guard context.scope == scope else { throw APIError.staleResponse }
        let url = URL(string: configuration.origin.absoluteString + "/api/mobile/v1/me/music/" + path)!
        var request = URLRequest(url: url); request.httpMethod = method
        request.setValue("Bearer " + context.bearer, forHTTPHeaderField: "Authorization")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        try Task.checkCancellation()
        guard await auth.isCurrent(context) else { throw APIError.staleResponse }
        let response = try await transport.send(request)
        try Task.checkCancellation()
        guard await auth.isCurrent(context) else { throw APIError.staleResponse }
        guard response.status == 200 else { throw APIError.rejected(response.status) }
        return try NativeJSON.decoder().decode(NativeResponse<T>.self, from: response.data).data
    }
    private struct Favorites: Decodable, Sendable { let items: [LibraryFavorite]; let nextCursor: String?; let syncVersion: Int }
    private struct Recent: Decodable, Sendable { let items: [LibraryRecent]; let nextCursor: String?; let historyEpoch: Int }
    func snapshot(scope: AccountScope) async throws -> LibrarySnapshot {
        let before = try await request("preferences", scope: scope, as: LibraryPreferences.self)
        var favorites: [LibraryFavorite] = [], recent: [LibraryRecent] = [], cursor: String?, seen = Set<String>(), version: Int?
        repeat {
            let query = cursor.map { "&cursor=" + $0 } ?? ""
            let result = try await request("favorites?limit=100" + query, scope: scope, as: Favorites.self)
            if let version { guard result.syncVersion == version else { throw APIError.staleResponse } }
            version = result.syncVersion; favorites += result.items; cursor = result.nextCursor
            guard favorites.count <= 100000 else { throw APIError.invalidPayload }
            if let cursor { guard cursor.range(of: "^[0-9]+:[0-9]+$", options: .regularExpression) != nil, seen.insert(cursor).inserted else { throw APIError.invalidPayload } }
        } while cursor != nil
        seen = []
        repeat {
            let result = try await request("recent?limit=100" + (cursor.map { "&cursor=" + $0 } ?? ""), scope: scope, as: Recent.self)
            guard result.historyEpoch == before.historyEpoch else { throw APIError.staleResponse }
            recent += result.items; cursor = result.nextCursor
            guard recent.count <= 1000 else { throw APIError.invalidPayload }
            if let cursor { guard cursor.range(of: "^[0-9]+:[0-9]+$", options: .regularExpression) != nil, seen.insert(cursor).inserted else { throw APIError.invalidPayload } }
        } while cursor != nil
        let after = try await request("preferences", scope: scope, as: LibraryPreferences.self)
        guard before == after, Set(favorites.map(\.trackId)).count == favorites.count, Set(recent.map(\.trackId)).count == recent.count else { throw APIError.staleResponse }
        guard after.version >= 0, after.historyEpoch >= 0,
              favorites.allSatisfy({ UUID(uuidString: $0.trackId) != nil && $0.version >= 0 }),
              recent.allSatisfy({ UUID(uuidString: $0.trackId) != nil && $0.positionSeconds.isFinite && $0.positionSeconds >= 0 }) else { throw APIError.invalidPayload }
        return .init(favorites: favorites, recent: recent, preferences: after)
    }
    func apply(_ op: LibraryOperation, scope: AccountScope) async throws {
        switch op.kind {
        case .favorite:
            guard let id = op.trackID, UUID(uuidString: id) != nil, let value = op.value, let version = op.version else { throw APIError.invalidRequest }
            let _: LibraryFavorite = try await request("favorites/" + id, method: "PUT", body: ["favorite": value, "expectedVersion": version, "mutationId": op.id], scope: scope, as: LibraryFavorite.self)
        case .preference:
            guard let value = op.value, let version = op.version else { throw APIError.invalidRequest }
            let _: LibraryPreferences = try await request("preferences", method: "PATCH", body: ["historyEnabled": value, "expectedVersion": version, "mutationId": op.id], scope: scope, as: LibraryPreferences.self)
        case .clear:
            guard let epoch = op.epoch else { throw APIError.invalidRequest }
            let _: LibraryPreferences = try await request("recent", method: "DELETE", body: ["confirmed": true, "historyEpoch": epoch, "mutationId": op.id], scope: scope, as: LibraryPreferences.self)
        case .listen:
            guard let id = op.trackID, let version = op.audioVersion, let epoch = op.epoch, let variant = op.variant, let audible = op.audibleSeconds, let position = op.position else { throw APIError.invalidRequest }
            struct Accepted: Decodable, Sendable { let accepted: Bool }
            let date = ISO8601DateFormatter(); date.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let _: Accepted = try await request("listens", method: "POST", body: ["trackId": id, "audioVersion": version, "eventId": op.id, "historyEpoch": epoch, "variant": variant, "audibleSeconds": audible, "positionSeconds": position, "occurredAt": date.string(from: op.created)], scope: scope, as: Accepted.self)
        }
    }
}
