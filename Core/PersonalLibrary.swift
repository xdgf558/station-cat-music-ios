import Foundation
import CryptoKit

nonisolated struct LibraryFavorite: Codable, Equatable, Sendable { let trackId: String; let favorite: Bool; let version: Int; let updatedAt: Date }
nonisolated struct LibraryRecent: Codable, Equatable, Sendable { let trackId: String; let lastPlayedAt: Date; let positionSeconds: Double }
nonisolated struct LibraryPreferences: Codable, Equatable, Sendable {
    var historyEnabled = true; var historyEpoch = 0; var version = 0
}
nonisolated struct LibraryOperation: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case favorite, preference, clear, listen }
    let id: String; let created: Date; let kind: Kind
    var trackID: String?; var value: Bool?; var version: Int?; var epoch: Int?
    var audioVersion: Int?; var variant: String?; var audibleSeconds: Double?; var position: Double?
}
nonisolated struct LibrarySnapshot: Sendable {
    var favorites: [LibraryFavorite]; var recent: [LibraryRecent]; var preferences: LibraryPreferences
}
nonisolated protocol LibraryRemote: Sendable {
    func snapshot(scope: AccountScope) async throws -> LibrarySnapshot
    func apply(_ operation: LibraryOperation, scope: AccountScope) async throws
}
nonisolated struct LibraryView: Sendable {
    let favorites: Set<String>; let recent: [LibraryRecent]; let historyEnabled: Bool; let pending: Int; let conflict: Bool; let synced: Bool
}
nonisolated struct LibraryFile: Codable {
    var schema = 1; let scope: AccountScope
    var favorites: [String: LibraryFavorite] = [:]
    var recent: [LibraryRecent] = []
    var preferences = LibraryPreferences()
    var operations: [LibraryOperation] = []
    var conflict = false
    var historyBlockedLocally = false
    var synced = false
}
actor ScopedLibrary {
    private let directory: URL?
    private var scopes: [AccountScope: LibraryFile] = [:]
    private var syncing = Set<AccountScope>()
    init(directory: URL? = nil) { self.directory = directory }
    private func file(_ scope: AccountScope) -> URL? {
        let identity = scope.environment.rawValue + ":" + (scope.accountID ?? "guest")
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory?.appending(path: key + ".json")
    }
    private func state(_ scope: AccountScope) throws -> LibraryFile {
        if let value = scopes[scope] { return value }
        var value = LibraryFile(scope: scope)
        if let url = file(scope), FileManager.default.fileExists(atPath: url.path) {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 20 * 1024 * 1024 else { throw APIError.storageUnavailable }
            value = try JSONDecoder().decode(LibraryFile.self, from: Data(contentsOf: url))
            guard value.schema == 1, value.scope == scope else { throw APIError.storageUnavailable }
        }
        scopes[scope] = value; return value
    }
    private func save(_ value: LibraryFile) throws {
        let data = try JSONEncoder().encode(value)
        guard data.count <= 20 * 1024 * 1024 else { throw APIError.storageUnavailable }
        if let directory, let url = file(value.scope) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var protected = directory
            var resources = URLResourceValues(); resources.isExcludedFromBackup = true
            try protected.setResourceValues(resources)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        scopes[value.scope] = value // Publish only after durable write succeeds.
    }
    func view(in scope: AccountScope) throws -> LibraryView {
        let value = try state(scope)
        return LibraryView(favorites: Set(value.favorites.values.filter(\.favorite).map(\.trackId)), recent: value.recent.filter { $0.lastPlayedAt > Date().addingTimeInterval(-90 * 86400) }, historyEnabled: value.preferences.historyEnabled && !value.historyBlockedLocally, pending: value.operations.count, conflict: value.conflict, synced: value.synced)
    }
    func favorites(in scope: AccountScope) throws -> Set<String> { try view(in: scope).favorites }
    func setFavorite(_ track: String, value: Bool, scope: AccountScope) throws {
        var stored = try state(scope)
        guard stored.operations.count < 5000 else { throw APIError.storageUnavailable }
        guard !value || stored.favorites[track]?.favorite == true || stored.favorites.values.filter(\.favorite).count < 5000 else { throw APIError.storageUnavailable }
        let version = stored.favorites[track]?.version ?? 0
        stored.favorites[track] = .init(trackId: track, favorite: value, version: version + 1, updatedAt: Date())
        if scope.accountID != nil { stored.operations.append(.init(id: UUID().uuidString, created: Date(), kind: .favorite, trackID: track, value: value, version: version)) }
        try save(stored)
    }
    func setHistory(_ enabled: Bool, scope: AccountScope) throws {
        var stored = try state(scope)
        guard stored.operations.count < 5000 else { throw APIError.storageUnavailable }
        let version = stored.preferences.version
        stored.historyBlockedLocally = !enabled; stored.preferences.historyEnabled = enabled; stored.preferences.version += 1; stored.preferences.historyEpoch += 1
        stored.operations.removeAll { $0.kind == .listen }
        if scope.accountID != nil { stored.operations.append(.init(id: UUID().uuidString, created: Date(), kind: .preference, value: enabled, version: version)) }
        try save(stored)
    }
    func clearHistory(scope: AccountScope) throws {
        var stored = try state(scope)
        guard stored.operations.count < 5000 else { throw APIError.storageUnavailable }
        let epoch = stored.preferences.historyEpoch
        stored.recent = []; stored.preferences.historyEpoch += 1; stored.preferences.version += 1
        stored.operations.removeAll { $0.kind == .listen }
        if scope.accountID != nil { stored.operations.append(.init(id: UUID().uuidString, created: Date(), kind: .clear, epoch: epoch)) }
        try save(stored)
    }
    func record(_ track: Track, variant: String, audible: Double, position: Double, eventID: String, scope: AccountScope) throws {
        var stored = try state(scope)
        guard !stored.historyBlockedLocally, stored.preferences.historyEnabled, audible.isFinite, audible >= 5, position.isFinite, position >= 0 else { return }
        guard stored.operations.count < 5000 else { throw APIError.storageUnavailable }
        if stored.operations.contains(where: { $0.id == eventID }) { return }
        stored.recent.removeAll { $0.trackId == track.id || $0.lastPlayedAt <= Date().addingTimeInterval(-90 * 86400) }
        stored.recent.insert(.init(trackId: track.id, lastPlayedAt: Date(), positionSeconds: position), at: 0)
        stored.recent = Array(stored.recent.prefix(1000))
        if scope.accountID != nil { stored.operations.append(.init(id: eventID, created: Date(), kind: .listen, trackID: track.id, epoch: stored.preferences.historyEpoch, audioVersion: track.audioVersion, variant: variant, audibleSeconds: audible, position: position)) }
        try save(stored)
    }
    func synchronize(scope: AccountScope, remote: any LibraryRemote) async throws {
        guard scope.accountID != nil, syncing.insert(scope).inserted else { return }
        defer { syncing.remove(scope) }
        var value = try state(scope)
        let expired = value.operations.filter { $0.created < Date().addingTimeInterval(-30 * 86400) }
        if !expired.isEmpty { value.operations.removeAll { $0.created < Date().addingTimeInterval(-30 * 86400) }; value.conflict = true; try save(value) }
        // Bounded pass; no automatic retry loop. Unknown outcome keeps the same durable ID.
        for _ in 0..<100 {
            try Task.checkCancellation()
            guard let operation = try state(scope).operations.first else { break }
            do {
                try await remote.apply(operation, scope: scope)
                try Task.checkCancellation()
                var current = try state(scope); current.operations.removeAll { $0.id == operation.id }; try save(current)
            } catch APIError.rejected(let code) where [400, 404, 409].contains(code) {
                var current = try state(scope)
                current.operations.removeAll { $0.id == operation.id || (operation.kind == .favorite && $0.kind == .favorite && $0.trackID == operation.trackID) || (operation.kind != .favorite && $0.kind != .favorite) }
                current.conflict = true; try save(current)
                break // Refresh authoritative state, never silently overwrite a conflict.
            }
        }
        let snapshot = try await remote.snapshot(scope: scope)
        try Task.checkCancellation()
        var current = try state(scope)
        current.synced = true
        let pendingTracks = Set(current.operations.filter { $0.kind == .favorite }.compactMap(\.trackID))
        let overlays = current.favorites.filter { pendingTracks.contains($0.key) }
        current.favorites = Dictionary(uniqueKeysWithValues: snapshot.favorites.map { ($0.trackId, $0) })
        current.favorites.merge(overlays) { _, pending in pending }
        if !current.operations.contains(where: { $0.kind == .preference || $0.kind == .clear }) {
            current.preferences = snapshot.preferences
            current.operations.removeAll { $0.kind == .listen && ($0.epoch != snapshot.preferences.historyEpoch || !snapshot.preferences.historyEnabled || current.historyBlockedLocally) }
            current.recent = snapshot.recent
            for op in current.operations where op.kind == .listen {
                if let id = op.trackID, !current.recent.contains(where: { $0.trackId == id }) { current.recent.append(.init(trackId: id, lastPlayedAt: op.created, positionSeconds: op.position ?? 0)) }
            }
        }
        try save(current)
    }
    func clear(scope: AccountScope) throws { try save(LibraryFile(scope: scope)) }
}

// Accumulate actual advancing playback samples, not slider positions or wall time alone.
nonisolated struct AudibleListenMeter {
    private var last: (wall: Double, media: Double)?
    private(set) var seconds: Double = 0
    private(set) var sent = false
    mutating func resetProgress() { last = nil }
    mutating func sample(wall: Double, media: Double, playing: Bool) -> Bool {
        defer { last = playing ? (wall, media) : nil }
        guard playing, wall.isFinite, media.isFinite, let last else { return false }
        let elapsed = wall - last.wall, advanced = media - last.media
        guard elapsed > 0, elapsed <= 1, advanced > 0, advanced <= elapsed + 0.15 else { return false }
        seconds += min(elapsed, advanced)
        if seconds >= 5 && !sent { sent = true; return true }; return false
    }
}
