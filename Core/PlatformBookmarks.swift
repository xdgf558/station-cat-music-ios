import Foundation
import CryptoKit

/// Only the explicit /bookmark response may create this disk representation.
/// Deliberately no Track, cover URL, platform URLs or playback/availability state.
nonisolated struct PlatformBookmark: Codable, Equatable, Sendable {
    let id, slug, title, artist: String
    let revision: Int
    let locale: String
    let savedAt, expires: Date
    var valid: Bool {
        UUID(uuidString: id) != nil && (1...100).contains(slug.utf8.count) &&
        slug.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil &&
        Self.text(title, limit: 200) && Self.text(artist, limit: 120) && revision > 0 &&
        revision <= 9_007_199_254_740_991 && PlatformMusicAPI.locales.contains(locale) &&
        savedAt.timeIntervalSince1970.isFinite && expires.timeIntervalSince1970.isFinite &&
        expires > savedAt && expires.timeIntervalSince(savedAt) <= 86_400
    }
    func usable(at now: Date) -> Bool { valid && now >= savedAt.addingTimeInterval(-2) && now < expires }
    private static func text(_ value: String, limit: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= limit &&
        !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}

/// A disposable cache, separate from the authoritative favorite IDs/journal.
/// Failed or expired snapshots never remove a favorite or authorize an external link.
actor PlatformBookmarkStore {
    private struct File: Codable { let schema: Int; let scope: AccountScope; var items: [String: PlatformBookmark] }
    private let directory: URL?
    private var memory: [AccountScope: File] = [:]
    private var deleted = Set<AccountScope>()
    private let now: @Sendable () -> Date
    init(directory: URL? = nil, now: @escaping @Sendable () -> Date = { Date() }) { self.directory = directory; self.now = now }
    func snapshots(scope: AccountScope) throws -> [String: PlatformBookmark] {
        try read(scope).items.filter { $0.value.usable(at: now()) }
    }
    func save(_ item: PlatformBookmark, scope: AccountScope) throws {
        guard !deleted.contains(scope), item.usable(at: now()) else { throw APIError.invalidPayload }
        var file = try read(scope)
        // Expired presentation may be reclaimed; account relationships live elsewhere.
        file.items = file.items.filter { $0.value.expires > now() }
        file.items[item.id] = item
        guard file.items.count <= 5000 else { throw APIError.storageUnavailable }
        try write(file)
    }
    func retain(_ ids: Set<String>, scope: AccountScope) throws {
        var file = try read(scope)
        let keep = file.items.filter { ids.contains($0.key) }
        guard keep.count != file.items.count else { return }
        file.items = keep; try write(file)
    }
    func removeDeletedAccount(scope: AccountScope) throws {
        guard scope.accountID != nil else { throw APIError.invalidRequest }
        deleted.insert(scope); memory.removeValue(forKey: scope)
        guard let url = try fileURL(scope), FileManager.default.fileExists(atPath: url.path) else { return }
        try checkFile(url); try FileManager.default.removeItem(at: url)
    }
    private func read(_ scope: AccountScope) throws -> File {
        guard !deleted.contains(scope) else { throw APIError.storageUnavailable }
        if let file = memory[scope] { return file }
        let empty = File(schema: 1, scope: scope, items: [:])
        guard let url = try fileURL(scope), FileManager.default.fileExists(atPath: url.path) else { return empty }
        try checkFile(url)
        let data = try Data(contentsOf: url)
        guard let file = try? JSONDecoder().decode(File.self, from: data),
              file.schema == 1, file.scope == scope, file.items.count <= 5000,
              file.items.allSatisfy({ $0.key == $0.value.id && $0.value.valid }) else { return empty }
        // Corrupt presentation is a miss. A later authorized response may repair
        // this regular, bounded file atomically; favorites/journals are untouched.
        return file
    }
    private func write(_ file: File) throws {
        let data = try JSONEncoder().encode(file)
        guard data.count <= 2 * 1024 * 1024 else { throw APIError.storageUnavailable }
        if let url = try fileURL(file.scope), let directory {
            if FileManager.default.fileExists(atPath: url.path) { try checkFile(url) }
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard files.count < 64 || files.contains(url) else { throw APIError.storageUnavailable }
            var total = data.count
            for other in files where other != url {
                let info = try other.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                guard info.isSymbolicLink != true, info.isRegularFile == true else { throw APIError.storageUnavailable }
                total += info.fileSize ?? 0
            }
            guard total <= 16 * 1024 * 1024 else { throw APIError.storageUnavailable }
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } else { memory[file.scope] = file }
    }
    private func checkFile(_ url: URL) throws {
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true, (info.fileSize ?? Int.max) <= 2 * 1024 * 1024 else { throw APIError.storageUnavailable }
    }
    private func fileURL(_ scope: AccountScope) throws -> URL? {
        guard var directory else { return nil }
        // Resolve neither a supplied symlink directory nor symlink ancestors.
        guard directory.standardizedFileURL.path == directory.resolvingSymlinksInPath().standardizedFileURL.path else { throw APIError.storageUnavailable }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let info = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard info.isDirectory == true, info.isSymbolicLink != true else { throw APIError.storageUnavailable }
        var values = URLResourceValues(); values.isExcludedFromBackup = true; try directory.setResourceValues(values)
        let identity = scope.environment.rawValue + ":" + (scope.accountID ?? "guest")
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: key + ".json")
    }
}

nonisolated struct PlatformFavoriteRow: Identifiable, Sendable {
    let id: String
    let track: Track?
    let bookmark: PlatformBookmark?
}
