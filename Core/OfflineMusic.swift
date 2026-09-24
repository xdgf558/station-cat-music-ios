import Foundation
import CryptoKit

nonisolated struct OfflinePermit: Codable, Sendable {
    let trackId: String
    let audioVersion: Int
    let policyVersion: Int
    let accessMode: String
    let variant: String
    let byteSize: Int
    let sha256: String
    let durationSeconds: Double
    let validUntil: Date
    func validate(track: Track, serverNow: Date) throws {
        guard track.offlineEligible == true, track.access == .free, UUID(uuidString: track.id) != nil,
              trackId == track.id, audioVersion == track.audioVersion, policyVersion > 0,
              accessMode == "free", variant == "full", (1...33_554_432).contains(byteSize),
              sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              durationSeconds.isFinite, durationSeconds > 0, abs(durationSeconds - track.durationSeconds) < 0.001,
              validUntil > serverNow, validUntil.timeIntervalSince(serverNow) <= 7 * 86400 else { throw APIError.invalidPayload }
    }
}
nonisolated struct OfflinePermission: Sendable {
    let permit: OfflinePermit
    let serverNow: Date
    let requestSeconds: Double
}
nonisolated protocol OfflineMusicProviding: PlaybackAuthorizing {
    func offlinePermission(for track: Track) async throws -> OfflinePermission
}
nonisolated struct OfflineSong: Codable, Identifiable, Sendable {
    let track: Track
    let permit: OfflinePermit
    let savedAt: Date
    let expiresAt: Date
    var id: String { track.id }
}
nonisolated struct OfflinePlayable: Sendable { let song: OfflineSong; let url: URL; let remaining: Double }

/// Explicit public, permanent-free saves. No bearer, grant URL, listening position,
/// account data or paid/temporary-free audio is persisted in this store.
actor OfflineMusicCache {
    static let maximumBytes = 500 * 1024 * 1024
    let directory: URL
    private let capacity: Int
    private let transport: any MediaHTTPTransport
    private var generation = 0
    private var downloading = false
    init(origin: URL, baseDirectory: URL? = nil, capacity: Int = OfflineMusicCache.maximumBytes,
         transport: any MediaHTTPTransport = NativeMediaTransport()) {
        let root = baseDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "OfflineMusic")
        self.directory = root.appending(path: Self.digest(Data(origin.absoluteString.utf8)))
        self.capacity = capacity; self.transport = transport
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func path(_ id: String) -> URL { directory.appending(path: Self.digest(Data(id.utf8))) }
    private func safeDirectory(_ url: URL) throws {
        let info = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard info.isDirectory == true, info.isSymbolicLink != true else { throw APIError.storageUnavailable }
    }
    private func prepare() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) { try fm.createDirectory(at: directory, withIntermediateDirectories: true) }
        try safeDirectory(directory)
        var root = directory, values = URLResourceValues(); values.isExcludedFromBackup = true
        try root.setResourceValues(values)
        if !downloading {
            for partial in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                where partial.lastPathComponent.hasPrefix(".download-") && UUID(uuidString: String(partial.lastPathComponent.dropFirst(10))) != nil {
                guard (try? safeDirectory(partial)) != nil else { continue }
                try fm.removeItem(at: partial)
            }
        }
    }
    private func regular(_ url: URL, limit: Int) throws -> Bool {
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        return info.isRegularFile == true && info.isSymbolicLink != true && (info.fileSize ?? Int.max) <= limit
    }
    private func entry(_ url: URL, now: Date) throws -> OfflineSong? {
        try safeDirectory(url)
        let receipt = url.appending(path: "receipt.json"), audio = url.appending(path: "audio.mp3")
        guard try regular(receipt, limit: 32768), try regular(audio, limit: 33_554_432) else { return nil }
        let value = try JSONDecoder().decode(OfflineSong.self, from: Data(contentsOf: receipt))
        guard path(value.id).lastPathComponent == url.lastPathComponent, value.savedAt <= now.addingTimeInterval(2), value.expiresAt > now,
              value.expiresAt.timeIntervalSince(value.savedAt) <= 7 * 86400 else { return nil }
        // Persisted metadata must obey the same policy, identity and finite bounds.
        try value.permit.validate(track: value.track, serverNow: value.permit.validUntil.addingTimeInterval(-7 * 86400))
        guard try audio.resourceValues(forKeys: [.fileSizeKey]).fileSize == value.permit.byteSize else { return nil }
        return value
    }
    private func folders() throws -> [URL] {
        try prepare()
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter {
            $0.lastPathComponent.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
        }
    }
    func songs(now: Date = Date()) throws -> [OfflineSong] {
        try folders().compactMap { try? entry($0, now: now) }.sorted { $0.savedAt > $1.savedAt }
    }
    private func occupiedBytes() throws -> Int {
        // Include expired/corrupt owned files in the budget. Never erase unknown data
        // or unpaid journals to create room for a download.
        var total = 0
        for folder in try folders() {
            guard (try? safeDirectory(folder)) != nil else { continue }
            for name in ["audio.mp3", "receipt.json"] {
                let file = folder.appending(path: name)
                if (try? regular(file, limit: Int.max)) == true { total += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
            }
        }
        return total
    }
    func usage() throws -> Int { try occupiedBytes() }
    func playable(_ track: Track, now: Date = Date()) throws -> OfflinePlayable? {
        guard track.offlineEligible == true, track.access == .free else { return nil }
        try prepare()
        let folder = path(track.id)
        guard let song = try? entry(folder, now: now), song.track.audioVersion == track.audioVersion else { return nil }
        let file = folder.appending(path: "audio.mp3")
        guard Self.digest(try Data(contentsOf: file)) == song.permit.sha256 else { return nil }
        return OfflinePlayable(song: song, url: file, remaining: song.expiresAt.timeIntervalSince(max(now, Date())))
    }
    func download(_ track: Track, source: any OfflineMusicProviding) async throws {
        guard !downloading, track.access == .free, track.offlineEligible == true else { throw APIError.unavailable }
        try prepare()
        downloading = true; let ticket = generation
        defer { downloading = false }
        let permission = try await source.offlinePermission(for: track)
        try permission.permit.validate(track: track, serverNow: permission.serverNow)
        let permit = permission.permit
        let started = Date(), clock = ContinuousClock(), start = ContinuousClock.now
        let lease = permit.validUntil.timeIntervalSince(permission.serverNow) - permission.requestSeconds - 2
        guard lease > 0 else { throw APIError.requiresAuthentication }
        try prepare()
        guard try occupiedBytes() + permit.byteSize + 32768 <= capacity, try folders().count < 200 else { throw APIError.storageUnavailable }
        // Audio requests retain the existing online grant's stricter deadline and
        // per-Range policy checks. A permit alone cannot download any bytes.
        let sent = clock.now
        let authorization = try await source.authorize(track: track, variant: "full")
        guard authorization.grant.authMode == .publicAccess, authorization.grant.variant == "full",
              authorization.grant.trackID == track.id, authorization.grant.audioVersion == track.audioVersion else { throw APIError.invalidPayload }
        let time = sent.duration(to: clock.now).components
        let elapsed = Double(time.seconds) + Double(time.attoseconds) / 1e18
        let lifetime = authorization.grant.playbackValidUntil.timeIntervalSince(authorization.serverNow) - elapsed - 2
        guard lifetime > 0 else { throw APIError.requiresAuthentication }
        let channel = AuthorizedMediaChannel(authorization: authorization, authorizer: source, transport: transport, lifetime: lifetime)
        let size = try await channel.size()
        guard size == Int64(permit.byteSize) else { throw APIError.invalidPayload }
        var data = Data(); data.reserveCapacity(permit.byteSize)
        while data.count < permit.byteSize {
            try Task.checkCancellation(); guard generation == ticket else { throw CancellationError() }
            data.append(try await channel.read(start: Int64(data.count), length: min(NativeMediaLimits.rangeBytes, permit.byteSize - data.count), total: size))
        }
        guard Self.digest(data) == permit.sha256 else { throw APIError.invalidPayload }
        // Confirm the policy again after download; a mid-download edit never seals
        // a stale free file. Do not extend the original seven-day lease.
        let confirmation = try await source.offlinePermission(for: track)
        try confirmation.permit.validate(track: track, serverNow: confirmation.serverNow)
        guard confirmation.permit.sha256 == permit.sha256, confirmation.permit.policyVersion == permit.policyVersion,
              confirmation.permit.byteSize == permit.byteSize else { throw APIError.staleResponse }
        try Task.checkCancellation(); guard generation == ticket else { throw CancellationError() }
        let spent = start.duration(to: clock.now).components
        let remaining = lease - Double(spent.seconds) - Double(spent.attoseconds) / 1e18
        guard remaining > 0, Date() >= started.addingTimeInterval(-2) else { throw APIError.requiresAuthentication }
        let value = OfflineSong(track: track, permit: permit, savedAt: Date(), expiresAt: Date().addingTimeInterval(remaining))
        let temporary = directory.appending(path: ".download-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary.appending(path: "audio.mp3"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try JSONEncoder().encode(value).write(to: temporary.appending(path: "receipt.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let destination = path(track.id)
        if FileManager.default.fileExists(atPath: destination.path) { try safeDirectory(destination); try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
    func remove(_ id: String) throws {
        generation += 1; try prepare()
        let target = path(id)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try safeDirectory(target)
        try FileManager.default.removeItem(at: target)
    }
    func clear() throws {
        generation += 1
        for folder in try folders() {
            guard (try? safeDirectory(folder)) != nil else { continue }
            try FileManager.default.removeItem(at: folder)
        }
    }
    func reconcile(_ catalog: [Track]) throws -> Set<String> {
        let map = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        var removed = Set<String>()
        for song in try songs() {
            guard let track = map[song.id], track.offlineEligible == true, track.access == .free,
                  track.audioVersion == song.track.audioVersion else { try remove(song.id); removed.insert(song.id); continue }
        }
        return removed
    }
}
