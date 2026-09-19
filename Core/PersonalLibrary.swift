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
    var privacyDependency: String?
    var audioVersion: Int?; var variant: String?; var audibleSeconds: Double?; var position: Double?
}
nonisolated struct LibrarySnapshot: Sendable {
    var favorites: [LibraryFavorite]; var recent: [LibraryRecent]; var preferences: LibraryPreferences
}
nonisolated protocol LibraryRemote: Sendable {
    func snapshot(scope: AccountScope) async throws -> LibrarySnapshot
    @discardableResult func apply(_ operation: LibraryOperation, scope: AccountScope) async throws -> LibraryPreferences?
}
nonisolated struct LibraryView: Sendable {
    let favorites: Set<String>; let recent: [LibraryRecent]; let historyEnabled: Bool; let pending: Int; let conflict: Bool; let synced: Bool
}
nonisolated struct LibraryFile: Codable {
    var schema = 2; let scope: AccountScope
    var favorites: [String: LibraryFavorite] = [:]
    var recent: [LibraryRecent] = []
    var preferences = LibraryPreferences() // Local display intent only; counters never predict acknowledgements.
    var confirmedPreferences: LibraryPreferences?
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
            guard [1, 2].contains(value.schema), value.scope == scope else { throw APIError.storageUnavailable }
            if value.schema == 1 {
                // Legacy journals have no trustworthy ancestry. Never replay their listen/enable chain.
                value.schema = 2; value.confirmedPreferences = nil
                if scope.accountID != nil {
                    value.operations.removeAll { $0.kind == .listen || ($0.kind == .preference && $0.value == true) }
                    // Old requests may have an unknown result: do not reuse their IDs with rebased bodies.
                    value.operations = value.operations.map { op in
                        isPrivacy(op) ? LibraryOperation(id: UUID().uuidString, created: op.created, kind: op.kind, value: op.value) : op
                    }
                    resetPrivacyChain(&value)
                    value.recent = []; value.conflict = true
                    value.historyBlockedLocally = true; value.preferences.historyEnabled = false
                }
                try save(value)
            }
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
    private func isPrivacy(_ op: LibraryOperation) -> Bool { op.kind == .preference || op.kind == .clear }
    private func resetPrivacyChain(_ value: inout LibraryFile) {
        var parent: String?
        for i in value.operations.indices where isPrivacy(value.operations[i]) {
            value.operations[i].privacyDependency = parent
            value.operations[i].version = nil; value.operations[i].epoch = nil
            parent = value.operations[i].id
        }
    }
    private func bindRootPrivacy(_ value: inout LibraryFile) {
        guard let confirmed = value.confirmedPreferences else { return }
        for i in value.operations.indices where isPrivacy(value.operations[i]) && value.operations[i].privacyDependency == nil && value.operations[i].version == nil {
            value.operations[i].version = confirmed.version; value.operations[i].epoch = confirmed.historyEpoch
        }
    }
    func setHistory(_ enabled: Bool, scope: AccountScope) throws {
        var stored = try state(scope)
        guard stored.operations.count < 5000 else { throw APIError.storageUnavailable }
        stored.historyBlockedLocally = !enabled; stored.preferences.historyEnabled = enabled
        stored.operations.removeAll { $0.kind == .listen }
        if scope.accountID != nil {
            let parent = stored.operations.last(where: isPrivacy)?.id
            stored.operations.append(.init(id: UUID().uuidString, created: Date(), kind: .preference, value: enabled, privacyDependency: parent))
            bindRootPrivacy(&stored)
        }
        try save(stored)
    }
    func clearHistory(scope: AccountScope) throws {
        var stored = try state(scope)
        guard stored.operations.count < 5000 else { throw APIError.storageUnavailable }
        stored.recent = []; stored.operations.removeAll { $0.kind == .listen }
        if scope.accountID != nil {
            let parent = stored.operations.last(where: isPrivacy)?.id
            stored.operations.append(.init(id: UUID().uuidString, created: Date(), kind: .clear, privacyDependency: parent))
            bindRootPrivacy(&stored)
        }
        try save(stored)
    }
    private func mergedRecent(_ rows: [LibraryRecent], now: Date = Date()) -> [LibraryRecent] {
        let cutoff = now.addingTimeInterval(-90 * 86400)
        var latest: [String: LibraryRecent] = [:]
        for row in rows where row.lastPlayedAt > cutoff {
            if let old = latest[row.trackId], old.lastPlayedAt >= row.lastPlayedAt { continue }
            latest[row.trackId] = row
        }
        return Array(latest.values.sorted {
            $0.lastPlayedAt == $1.lastPlayedAt ? $0.trackId < $1.trackId : $0.lastPlayedAt > $1.lastPlayedAt
        }.prefix(1000))
    }
    func record(_ track: Track, variant: String, audible: Double, position: Double, eventID: String, scope: AccountScope) throws {
        var stored = try state(scope)
        guard !stored.historyBlockedLocally, stored.preferences.historyEnabled, audible.isFinite, audible >= 5, position.isFinite, position >= 0 else { return }
        // Until an account has an actual server baseline, its events cannot acquire an epoch.
        guard scope.accountID == nil || stored.confirmedPreferences != nil else { return }
        guard stored.operations.count < 5000 else { throw APIError.storageUnavailable }
        if stored.operations.contains(where: { $0.id == eventID }) { return }
        let occurred = Date()
        stored.recent = mergedRecent(stored.recent + [.init(trackId: track.id, lastPlayedAt: occurred, positionSeconds: position)])
        if scope.accountID != nil {
            let parent = stored.operations.last(where: isPrivacy)?.id
            stored.operations.append(.init(id: eventID, created: occurred, kind: .listen, trackID: track.id,
                epoch: parent == nil ? stored.confirmedPreferences?.historyEpoch : nil, privacyDependency: parent,
                audioVersion: track.audioVersion, variant: variant, audibleSeconds: audible, position: position))
        }
        try save(stored)
    }
    private func rejectPrivacy(_ operation: LibraryOperation, in value: inout LibraryFile, rebaseRejected: Bool = false) {
        var invalid = Set([operation.id])
        for op in value.operations { if let parent = op.privacyDependency, invalid.contains(parent) { invalid.insert(op.id) } }
        // Preserve later restrictive commands. A dependent enable must be explicitly requested again.
        let lostEnable = value.operations.contains { invalid.contains($0.id) && $0.kind == .preference && $0.value == true }
        value.operations.removeAll { $0.id == operation.id || (invalid.contains($0.id) && ($0.kind == .listen || ($0.kind == .preference && $0.value == true))) }
        // Independent queued listens also belong to the old confirmed epoch, never a rebased one.
        value.operations.removeAll { $0.kind == .listen }
        if rebaseRejected && (operation.kind == .clear || operation.value == false) {
            // The rejected request had no effect. A fresh ID represents the restrictive intent
            // rebased onto the next confirmed snapshot, never a changed body under an old ID.
            value.operations.insert(.init(id: UUID().uuidString, created: operation.created, kind: operation.kind, value: operation.value), at: 0)
        }
        value.confirmedPreferences = nil; value.recent = []; value.conflict = true
        resetPrivacyChain(&value)
        if lostEnable { value.historyBlockedLocally = true; value.preferences.historyEnabled = false }
    }
    private func merge(_ snapshot: LibrarySnapshot, into current: inout LibraryFile) {
        current.confirmedPreferences = snapshot.preferences; current.synced = true
        bindRootPrivacy(&current) // Bind only never-issued roots; never change an ambiguous request body/ID.
        let pendingTracks = Set(current.operations.filter { $0.kind == .favorite }.compactMap(\.trackID))
        let overlays = current.favorites.filter { pendingTracks.contains($0.key) }
        current.favorites = Dictionary(uniqueKeysWithValues: snapshot.favorites.map { ($0.trackId, $0) })
        current.favorites.merge(overlays) { _, pending in pending }
        if !current.operations.contains(where: isPrivacy) {
            current.preferences = snapshot.preferences
            current.operations.removeAll { $0.kind == .listen && ($0.privacyDependency != nil || $0.epoch != snapshot.preferences.historyEpoch || !snapshot.preferences.historyEnabled || current.historyBlockedLocally) }
            let local: [LibraryRecent] = current.operations.compactMap { op in
                guard op.kind == .listen, let id = op.trackID else { return nil }
                return .init(trackId: id, lastPlayedAt: op.created, positionSeconds: op.position ?? 0)
            }
            current.recent = mergedRecent(snapshot.recent + local)
        }
    }
    func synchronize(scope: AccountScope, remote: any LibraryRemote) async throws {
        guard scope.accountID != nil, syncing.insert(scope).inserted else { return }
        defer { syncing.remove(scope) }
        var value = try state(scope)
        let expired = value.operations.filter { $0.created < Date().addingTimeInterval(-30 * 86400) }
        if !expired.isEmpty {
            for op in expired where isPrivacy(op) { rejectPrivacy(op, in: &value) }
            let ids = Set(expired.map(\.id)); value.operations.removeAll { ids.contains($0.id) }
            value.conflict = true; try save(value)
        }
        if value.confirmedPreferences == nil {
            let snapshot = try await remote.snapshot(scope: scope); try Task.checkCancellation()
            var current = try state(scope); merge(snapshot, into: &current); try save(current)
        }
        for _ in 0..<100 {
            try Task.checkCancellation()
            guard let operation = try state(scope).operations.first else { break }
            // A dependency is released only by its parent's acknowledged server response.
            guard operation.privacyDependency == nil else { throw APIError.invalidPayload }
            do {
                let receipt = try await remote.apply(operation, scope: scope)
                try Task.checkCancellation()
                var current = try state(scope)
                if isPrivacy(operation) {
                    guard let receipt, let version = operation.version, let epoch = operation.epoch,
                        receipt.version == version + 1, receipt.historyEpoch == epoch + 1,
                        operation.kind != .preference || receipt.historyEnabled == operation.value else { throw APIError.invalidPayload }
                    current.confirmedPreferences = receipt
                    for i in current.operations.indices where current.operations[i].privacyDependency == operation.id {
                        current.operations[i].privacyDependency = nil
                        current.operations[i].epoch = receipt.historyEpoch
                        if isPrivacy(current.operations[i]) { current.operations[i].version = receipt.version }
                    }
                }
                current.operations.removeAll { $0.id == operation.id }; try save(current)
            } catch APIError.rejected(let code) where [400, 404, 409].contains(code) {
                try Task.checkCancellation()
                var current = try state(scope)
                guard current.operations.contains(where: { $0.id == operation.id }) else { continue }
                if isPrivacy(operation) { rejectPrivacy(operation, in: &current, rebaseRejected: code == 409) }
                else {
                    current.operations.removeAll {
                        $0.id == operation.id || (operation.kind == .favorite && $0.kind == .favorite &&
                            $0.trackID == operation.trackID && ($0.version ?? -1) > (operation.version ?? -1))
                    }
                    current.conflict = true
                }
                try save(current); break
            }
        }
        let snapshot = try await remote.snapshot(scope: scope); try Task.checkCancellation()
        var current = try state(scope); merge(snapshot, into: &current); try save(current)
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
