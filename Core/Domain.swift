import Foundation

nonisolated enum AppEnvironment: String, Codable, Sendable, CaseIterable {
    case mock, development, staging, production
    var remoteNetworkingEnabled: Bool { false } // M2/M3 must explicitly introduce the verified transport.
}
nonisolated struct AccountScope: Codable, Equatable, Hashable, Sendable {
    let environment: AppEnvironment
    let accountID: String?
    static let guest = Self(environment: .mock, accountID: nil)
}
nonisolated enum AccessPolicy: String, Codable, Sendable {
    case free, vip, preview, unavailable
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .unavailable
    }
}
nonisolated struct Track: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let artist: String
    let durationSeconds: Double
    let audioVersion: Int
    let access: AccessPolicy
    var coverUrl: URL? = nil
    var offlineEligible: Bool? = nil
}
nonisolated struct Catalog: Codable, Sendable { let items: [Track]; let nextCursor: String? }
nonisolated struct APIEnvelope<T: Codable & Sendable>: Codable, Sendable {
    let data: T
    let requestId: String
    let serverNow: String
}
nonisolated enum APIError: Error, Equatable, Sendable {
    case networkDisabled, invalidRequest, unavailable, rejected(Int), invalidPayload, staleResponse, storageUnavailable, requiresAuthentication
}
nonisolated enum GrantAuthMode: String, Codable, Sendable { case publicAccess = "public", sessionBearer = "session_bearer" }
nonisolated struct PlaybackGrant: Codable, Sendable {
    let playbackUrl: URL
    let expiresAt: Date
    let playbackValidUntil: Date
    let revalidateAt: Date
    let durationSeconds: Double
    let previewSourceStartSeconds: Double?
    let authMode: GrantAuthMode
    let accountID: String?
    let sessionID: String?
    let trackID: String
    let audioVersion: Int
    let variant: String
    enum CodingKeys: String, CodingKey {
        case playbackUrl, expiresAt, playbackValidUntil, revalidateAt, durationSeconds, previewSourceStartSeconds, authMode, audioVersion, variant
        case accountID = "accountId", sessionID = "sessionId", trackID = "trackId"
    }
    func validate(serverNow: Date, scope: AccountScope, session: String?, track: Track, allowedHosts: Set<String>) throws {
        guard playbackUrl.scheme == "https", let host = playbackUrl.host, allowedHosts.contains(host),
              playbackUrl.user == nil, playbackUrl.password == nil, playbackUrl.query == nil, playbackUrl.fragment == nil,
              playbackUrl.port == nil || playbackUrl.port == 443,
              playbackUrl.path.range(of: "^/api/mobile/v1/music/media/[A-Za-z0-9_-]{43}/audio$", options: .regularExpression) != nil,
              serverNow < playbackValidUntil, serverNow <= revalidateAt, revalidateAt <= playbackValidUntil, durationSeconds > 0, durationSeconds.isFinite,
              playbackValidUntil.timeIntervalSince(serverNow) <= 600,
              track.access != .unavailable,
              expiresAt == playbackValidUntil, track.id == trackID, track.audioVersion == audioVersion,
              ["full", "preview"].contains(variant) else { throw APIError.invalidPayload }
        if variant == "preview" {
            guard let offset = previewSourceStartSeconds, offset.isFinite, offset >= 0,
                  durationSeconds <= min(45, track.durationSeconds / 2) + 0.25,
                  offset + durationSeconds <= track.durationSeconds + 0.25 else { throw APIError.invalidPayload }
        } else {
            guard previewSourceStartSeconds == nil, abs(durationSeconds - track.durationSeconds) < 0.001 else { throw APIError.invalidPayload }
        }
        switch authMode {
        case .sessionBearer:
            guard let id = scope.accountID, id == accountID, let session, session == sessionID else { throw APIError.requiresAuthentication }
        case .publicAccess:
            guard accountID == nil, sessionID == nil, track.access == .free || (variant == "preview" && track.access == .preview) else { throw APIError.requiresAuthentication }
        }
    }
}
nonisolated struct PendingRefresh: Codable, Equatable, Sendable {
    let requestID: String
    let oldGeneration: Int
    let canonicalDigest: String
}
nonisolated struct CredentialEnvelope: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let scope: AccountScope
    let sessionID: String
    let familyID: String
    var generation: Int
    var refreshToken: String
    var pending: PendingRefresh?
    var refreshExpiresAt: Date
    var absoluteExpiresAt: Date
}
nonisolated struct DeletionRecoveryEnvelope: Codable, Equatable, Sendable {
    var accountID: String? = nil
    let environment: AppEnvironment
    let deletionRequestID: String
    let prepareRequestID: String
    let receipt: Data
    let scopeVersion: String
    var prepareExpiresAt: Date?
    var receiptExpiresAt: Date?
    var confirmRequestID: String?
    var confirmAttempted: Bool
    var lastKnownStatus: String
}
