import Foundation
import CryptoKit

/// Navigation history, not listening history. No URL, attribution, availability,
/// cover or server text is persisted here. Presentation uses the expiring bookmark cache.
nonisolated struct PlatformVisit: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let slug: String
    let viewedAt: Date
    var valid: Bool {
        UUID(uuidString: id) != nil && (1...100).contains(slug.utf8.count) &&
        slug.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil &&
        viewedAt.timeIntervalSince1970.isFinite && viewedAt.timeIntervalSince1970 >= 0
    }
}

nonisolated struct PlatformPersonalState: Codable, Equatable, Sendable {
    var revision = 0
    var preferred: PlatformProvider?
    var historyEnabled = true
    // A clear/off/on starts a new epoch. Late detail results cannot repopulate it.
    var historyEpoch = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    var visits: [PlatformVisit] = []

    func orderedLinks(_ links: [PlatformLink]) -> [PlatformLink] {
        guard let preferred else { return links }
        return links.filter { $0.provider == preferred } + links.filter { $0.provider != preferred }
    }
}

actor PlatformPersonalStore {
    nonisolated static let maximumVisits = 100
    nonisolated static let retention: TimeInterval = 30 * 86_400
    private struct File: Codable { let schema: Int; let scope: AccountScope; var state: PlatformPersonalState }
    private let directory: URL?
    private let now: @Sendable () -> Date
    private var memory: [AccountScope: File] = [:]
    private var deleted = Set<AccountScope>()
    init(directory: URL? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory; self.now = now
    }
    func snapshot(scope: AccountScope) throws -> PlatformPersonalState {
        var file = try read(scope)
        let retained = file.state.visits.filter { $0.viewedAt > now().addingTimeInterval(-Self.retention) }
        if retained.count != file.state.visits.count {
            file.state.visits = retained; file.state.revision += 1
            try write(file)
        }
        return visible(file.state)
    }
    func setPreferred(_ provider: PlatformProvider?, scope: AccountScope) throws -> PlatformPersonalState {
        var file = try read(scope); file.state.preferred = provider
        file.state.revision += 1
        try write(file); return visible(file.state)
    }
    func setHistory(_ enabled: Bool, scope: AccountScope) throws -> PlatformPersonalState {
        var file = try read(scope)
        guard file.state.historyEnabled != enabled else { return visible(file.state) }
        file.state.historyEnabled = enabled; file.state.historyEpoch = UUID()
        file.state.revision += 1
        if !enabled { file.state.visits = [] }
        try write(file); return visible(file.state)
    }
    func clearHistory(scope: AccountScope) throws -> PlatformPersonalState {
        var file = try read(scope); file.state.historyEpoch = UUID(); file.state.visits = []
        file.state.revision += 1
        try write(file); return visible(file.state)
    }
    func record(id: String, slug: String, epoch: UUID, scope: AccountScope) throws -> PlatformPersonalState {
        var file = try read(scope)
        guard file.state.historyEnabled, file.state.historyEpoch == epoch else { return visible(file.state) }
        let item = PlatformVisit(id: id, slug: slug, viewedAt: now())
        guard item.valid else { throw APIError.invalidPayload }
        file.state.visits.removeAll { $0.id == id || $0.viewedAt <= now().addingTimeInterval(-Self.retention) }
        file.state.visits.append(item)
        file.state.visits = Array(sorted(file.state.visits).prefix(Self.maximumVisits))
        file.state.revision += 1
        try write(file); return visible(file.state)
    }
    func removeDeletedAccount(scope: AccountScope) throws {
        guard scope.accountID != nil else { throw APIError.invalidRequest }
        deleted.insert(scope); memory.removeValue(forKey: scope)
        guard let url = try fileURL(scope), FileManager.default.fileExists(atPath: url.path) else { return }
        try checkFile(url); try FileManager.default.removeItem(at: url)
    }
    private func visible(_ source: PlatformPersonalState) -> PlatformPersonalState {
        var state = source
        state.visits = state.historyEnabled ? sorted(state.visits.filter {
            $0.viewedAt > now().addingTimeInterval(-Self.retention) && $0.viewedAt <= now().addingTimeInterval(2)
        }) : []
        return state
    }
    private func sorted(_ visits: [PlatformVisit]) -> [PlatformVisit] {
        visits.sorted { $0.viewedAt == $1.viewedAt ? $0.id < $1.id : $0.viewedAt > $1.viewedAt }
    }
    private func read(_ scope: AccountScope) throws -> File {
        guard !deleted.contains(scope) else { throw APIError.storageUnavailable }
        if let file = memory[scope] { return file }
        guard let url = try fileURL(scope), FileManager.default.fileExists(atPath: url.path) else {
            return File(schema: 1, scope: scope, state: PlatformPersonalState())
        }
        try checkFile(url)
        guard let file = try? JSONDecoder().decode(File.self, from: Data(contentsOf: url)),
              file.schema == 1, file.scope == scope, (0..<Int.max).contains(file.state.revision), file.state.visits.count <= Self.maximumVisits,
              Set(file.state.visits.map(\.id)).count == file.state.visits.count,
              file.state.visits.allSatisfy(\.valid), file.state.historyEnabled || file.state.visits.isEmpty else {
            // Do not reset a corrupt privacy setting to the default "on".
            throw APIError.storageUnavailable
        }
        return file
    }
    private func write(_ source: File) throws {
        var file = source
        file.state.visits.removeAll { $0.viewedAt <= now().addingTimeInterval(-Self.retention) }
        let data = try JSONEncoder().encode(file)
        guard data.count <= 65_536 else { throw APIError.storageUnavailable }
        if let url = try fileURL(file.scope), let directory {
            if FileManager.default.fileExists(atPath: url.path) { try checkFile(url) }
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard files.count < 64 || files.contains(url) else { throw APIError.storageUnavailable }
            var total = data.count
            for other in files where other != url {
                try checkFile(other)
                total += try other.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            }
            guard total <= 4 * 1024 * 1024 else { throw APIError.storageUnavailable }
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } else { memory[file.scope] = file }
    }
    private func checkFile(_ url: URL) throws {
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true, (info.fileSize ?? Int.max) <= 65_536 else { throw APIError.storageUnavailable }
    }
    private func fileURL(_ scope: AccountScope) throws -> URL? {
        guard var directory else { return nil }
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

nonisolated struct PlatformVisitRow: Identifiable, Sendable {
    let visit: PlatformVisit
    let track: Track?
    let bookmark: PlatformBookmark?
    var id: String { visit.id }
}
