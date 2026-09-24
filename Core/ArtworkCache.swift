import Foundation
import CryptoKit

/// Disposable public artwork only. Owned exclusively by ArtworkLoader's executor.
/// No URL, account identity, cookies, or authorization data is persisted.
nonisolated struct ArtworkCache {
    struct Entry: Codable { let version: Int; let expires: Date; let data: Data }
    let directory: URL
    let maximumBytes: Int
    let maximumFiles: Int
    init(directory: URL, maximumBytes: Int = 150 * 1024 * 1024, maximumFiles: Int = 4096) {
        self.directory = directory; self.maximumBytes = maximumBytes; self.maximumFiles = maximumFiles
    }
    private func file(_ url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: digest + ".art")
    }
    private func prepare() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: directory.path) {
            let value = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard value.isDirectory == true, value.isSymbolicLink != true else { throw APIError.storageUnavailable }
        } else { try fm.createDirectory(at: directory, withIntermediateDirectories: true) }
        var root = directory, values = URLResourceValues(); values.isExcludedFromBackup = true
        try root.setResourceValues(values)
    }
    private func files() throws -> [(URL, Int, Date)] {
        try prepare()
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]).compactMap { url in
            let info = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard info.isRegularFile == true, info.isSymbolicLink != true, url.pathExtension == "art" else { return nil }
            return (url, info.fileSize ?? 0, info.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 == $1.2 ? $0.0.lastPathComponent < $1.0.lastPathComponent : $0.2 < $1.2 }
    }
    func prune(reserving bytes: Int = 0, slots: Int = 0) throws {
        let entries = try files()
        var total = entries.reduce(0) { $0 + $1.1 }, count = entries.count
        for entry in entries where total + bytes > maximumBytes || count + slots > maximumFiles {
            try FileManager.default.removeItem(at: entry.0); total -= entry.1; count -= 1
        }
    }
    func read(_ url: URL, now: Date) throws -> Data? {
        try readEntry(url, now: now)?.data
    }
    func readEntry(_ url: URL, now: Date) throws -> Entry? {
        try prune()
        let path = file(url)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let info = try path.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true else { return nil }
        guard (info.fileSize ?? Int.max) <= ArtworkLoader.maximumBytes + 4096,
              let entry = try? PropertyListDecoder().decode(Entry.self, from: Data(contentsOf: path)),
              entry.version == 2, entry.expires > now, entry.expires <= now.addingTimeInterval(86400),
              entry.data.count <= ArtworkLoader.maximumBytes else {
            try FileManager.default.removeItem(at: path); return nil
        }
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: path.path)
        return entry
    }
    func store(_ data: Data, url: URL, expires: Date, now: Date) throws {
        guard !data.isEmpty, data.count <= ArtworkLoader.maximumBytes, expires > now, expires <= now.addingTimeInterval(86400) else { return }
        try prepare()
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        let bytes = try encoder.encode(Entry(version: 2, expires: expires, data: data))
        guard bytes.count <= maximumBytes, maximumFiles > 0 else { return }
        let destination = file(url)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try prune(reserving: bytes.count, slots: 1)
        try bytes.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: destination.path)
    }
    func clear() throws {
        // Do not recursively delete a directory that could contain non-cache state.
        for entry in try files() { try FileManager.default.removeItem(at: entry.0) }
    }
}
