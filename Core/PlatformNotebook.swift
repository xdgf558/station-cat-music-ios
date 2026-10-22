import Foundation
import CryptoKit

/// A reference, never a cached copy of a work. Opening it still requires online verification.
nonisolated struct NotebookWork: Codable, Equatable, Sendable {
    let id: String
    let slug: String
}

/// Title and body are authored by the user. Server lyrics, stories, artwork,
/// platform URLs and attribution are never copied into this representation.
nonisolated struct NotebookNote: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let work: NotebookWork?
    let title: String
    let body: String
    let topicID: UUID?
    let createdAt: Date
    let updatedAt: Date
    let version: Int
}

nonisolated struct NotebookTopic: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
}

nonisolated struct NotebookState: Codable, Equatable, Sendable {
    var revision: Int
    var epoch: UUID
    var notes: [NotebookNote]
    var topics: [NotebookTopic]
}

nonisolated struct NotebookDraft: Equatable, Sendable {
    var id: UUID
    var work: NotebookWork?
    var title: String
    var body: String
    var topicID: UUID?

    init(id: UUID = UUID(), work: NotebookWork? = nil, title: String = "", body: String = "", topicID: UUID? = nil) {
        self.id = id; self.work = work; self.title = title; self.body = body; self.topicID = topicID
    }
}

/// Editing policy only. The store still rejects invalid input rather than silently
/// changing a caller's draft. Treat CRLF as one break and retain every text segment.
nonisolated enum NotebookTitleInput {
    static func singleLine(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines).joined(separator: " ")
    }
}

nonisolated enum NotebookError: Error, Equatable, Sendable {
    case invalidInput, limitReached, staleEdit, storageUnavailable
}

/// Authoritative local writing, separate from disposable caches and listening history.
/// No automatic expiry or eviction: a failed save leaves the previous file untouched.
actor PlatformNotebookStore {
    nonisolated static let maximumNotes = 500
    nonisolated static let maximumTopics = 30
    nonisolated static let maximumTitleLength = 120
    nonisolated static let maximumBodyLength = 8_000
    nonisolated static let maximumTopicLength = 40
    nonisolated static let maximumFileBytes = 4 * 1024 * 1024
    nonisolated static let maximumTotalBytes = 16 * 1024 * 1024
    nonisolated static let maximumScopes = 64

    private struct File: Codable {
        let schema: Int
        let scope: AccountScope
        var state: NotebookState
    }
    private let directory: URL?
    private let now: @Sendable () -> Date
    private let writeAtomically: @Sendable (Data, URL) throws -> Void
    private var memory: [AccountScope: File] = [:]
    private var deleted = Set<AccountScope>()

    init(directory: URL? = nil, now: @escaping @Sendable () -> Date = { Date() },
         writeAtomically: @escaping @Sendable (Data, URL) throws -> Void = {
             try $0.write(to: $1, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
         }) {
        self.directory = directory; self.now = now; self.writeAtomically = writeAtomically
    }

    func snapshot(scope: AccountScope) throws -> NotebookState {
        try mapped { try read(scope).state }
    }

    func save(_ draft: NotebookDraft, expectedEpoch: UUID, expectedVersion: Int?, scope: AccountScope) throws -> NotebookState {
        try mapped {
            var file = try read(scope)
            try checkEpoch(expectedEpoch, file.state)
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard validText(title, maximum: Self.maximumTitleLength, multiline: false),
                  validText(draft.body, maximum: Self.maximumBodyLength, multiline: true),
                  !title.isEmpty || !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  draft.work.map(validWork) ?? true else { throw NotebookError.invalidInput }
            if let topic = draft.topicID, !file.state.topics.contains(where: { $0.id == topic }) {
                throw NotebookError.staleEdit
            }
            let previous = file.state.notes.first { $0.id == draft.id }
            if let expectedVersion {
                guard let previous, previous.version == expectedVersion else { throw NotebookError.staleEdit }
            } else {
                guard previous == nil else { throw NotebookError.staleEdit }
                guard file.state.notes.count < Self.maximumNotes else { throw NotebookError.limitReached }
            }
            let date = now()
            guard validDate(date) else { throw NotebookError.storageUnavailable }
            let version = try increment(previous?.version ?? 0)
            // A clock correction must not erase a note or make its chronology invalid.
            let updatedAt = max(date, previous?.updatedAt ?? date)
            let note = NotebookNote(id: draft.id, work: draft.work, title: title, body: draft.body,
                                    topicID: draft.topicID, createdAt: previous?.createdAt ?? date,
                                    updatedAt: updatedAt, version: version)
            file.state.notes.removeAll { $0.id == draft.id }
            file.state.notes.append(note)
            file.state.notes.sort { $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt }
            file.state.revision = try increment(file.state.revision)
            try write(file)
            return file.state
        }
    }

    func remove(id: UUID, expectedEpoch: UUID, scope: AccountScope) throws -> NotebookState {
        try mapped {
            var file = try read(scope)
            try checkEpoch(expectedEpoch, file.state)
            guard file.state.notes.contains(where: { $0.id == id }) else { return file.state }
            file.state.notes.removeAll { $0.id == id }
            // Also invalidates a delayed "new note" save with the deleted UUID.
            file.state.epoch = UUID()
            file.state.revision = try increment(file.state.revision)
            try write(file)
            return file.state
        }
    }

    func saveTopic(id: UUID?, name: String, expectedEpoch: UUID, scope: AccountScope) throws -> NotebookState {
        try mapped {
            var file = try read(scope)
            try checkEpoch(expectedEpoch, file.state)
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, validText(name, maximum: Self.maximumTopicLength, multiline: false),
                  !file.state.topics.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw NotebookError.invalidInput
            }
            if let id {
                guard file.state.topics.contains(where: { $0.id == id }) else { throw NotebookError.staleEdit }
                file.state.topics.removeAll { $0.id == id }
                file.state.topics.append(NotebookTopic(id: id, name: name))
            } else {
                guard file.state.topics.count < Self.maximumTopics else { throw NotebookError.limitReached }
                file.state.topics.append(NotebookTopic(id: UUID(), name: name))
            }
            file.state.revision = try increment(file.state.revision)
            try write(file)
            return file.state
        }
    }

    func removeTopic(id: UUID, expectedEpoch: UUID, scope: AccountScope) throws -> NotebookState {
        try mapped {
            var file = try read(scope)
            try checkEpoch(expectedEpoch, file.state)
            guard file.state.topics.contains(where: { $0.id == id }) else { return file.state }
            file.state.topics.removeAll { $0.id == id }
            file.state.notes = try file.state.notes.map { note in
                guard note.topicID == id else { return note }
                return NotebookNote(id: note.id, work: note.work, title: note.title, body: note.body,
                                    topicID: nil, createdAt: note.createdAt, updatedAt: note.updatedAt,
                                    version: try increment(note.version))
            }
            file.state.revision = try increment(file.state.revision)
            try write(file)
            return file.state
        }
    }

    func clear(expectedEpoch: UUID, scope: AccountScope) throws -> NotebookState {
        try mapped {
            var file = try read(scope)
            try checkEpoch(expectedEpoch, file.state)
            file.state = NotebookState(revision: try increment(file.state.revision), epoch: UUID(), notes: [], topics: [])
            try write(file)
            return file.state
        }
    }

    func removeDeletedAccount(scope: AccountScope) throws {
        try mapped {
            guard scope.accountID != nil else { throw NotebookError.invalidInput }
            deleted.insert(scope)
            memory.removeValue(forKey: scope)
            guard let url = try fileURL(scope), try fileExists(url) else { return }
            _ = try regularFileSize(url)
            try FileManager.default.removeItem(at: url)
        }
    }

    private func mapped<T>(_ body: () throws -> T) throws -> T {
        do { return try body() }
        catch let error as NotebookError { throw error }
        catch { throw NotebookError.storageUnavailable }
    }
    private func increment(_ value: Int) throws -> Int {
        guard value >= 0, value < Int.max - 1 else { throw NotebookError.limitReached }
        return value + 1
    }
    private func checkEpoch(_ expected: UUID, _ state: NotebookState) throws {
        guard expected == state.epoch else { throw NotebookError.staleEdit }
    }
    private func validDate(_ value: Date) -> Bool {
        value.timeIntervalSince1970.isFinite && value.timeIntervalSince1970 >= 0
    }
    private func validText(_ value: String, maximum: Int, multiline: Bool) -> Bool {
        value.count <= maximum && !value.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0) && !(multiline && ($0 == "\n" || $0 == "\t" || $0 == "\r"))
        }
    }
    private func validWork(_ work: NotebookWork) -> Bool {
        UUID(uuidString: work.id) != nil && (1...100).contains(work.slug.utf8.count) &&
        work.slug.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil
    }
    private func valid(_ file: File) -> Bool {
        let state = file.state, topicIDs = Set(file.state.topics.map(\.id))
        return file.schema == 1 && (0..<Int.max).contains(state.revision) &&
        state.notes.count <= Self.maximumNotes && state.topics.count <= Self.maximumTopics &&
        Set(state.notes.map(\.id)).count == state.notes.count && topicIDs.count == state.topics.count &&
        Set(state.topics.map { $0.name.lowercased() }).count == state.topics.count &&
        state.topics.allSatisfy { !$0.name.isEmpty && $0.name == $0.name.trimmingCharacters(in: .whitespacesAndNewlines) && validText($0.name, maximum: Self.maximumTopicLength, multiline: false) } &&
        state.notes.allSatisfy {
            (1..<Int.max).contains($0.version) && validDate($0.createdAt) && validDate($0.updatedAt) && $0.updatedAt >= $0.createdAt &&
            $0.title == $0.title.trimmingCharacters(in: .whitespacesAndNewlines) &&
            validText($0.title, maximum: Self.maximumTitleLength, multiline: false) && validText($0.body, maximum: Self.maximumBodyLength, multiline: true) &&
            (!$0.title.isEmpty || !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
            ($0.work.map(validWork) ?? true) && ($0.topicID.map { topicIDs.contains($0) } ?? true)
        }
    }

    private func read(_ scope: AccountScope) throws -> File {
        guard !deleted.contains(scope) else { throw NotebookError.storageUnavailable }
        if directory == nil, let file = memory[scope] { return file }
        if let url = try fileURL(scope), try fileExists(url) {
            let size = try regularFileSize(url)
            guard size <= Self.maximumFileBytes else { throw NotebookError.storageUnavailable }
            let data = try Data(contentsOf: url)
            guard data.count <= Self.maximumFileBytes,
                  let file = try? JSONDecoder().decode(File.self, from: data), file.scope == scope, valid(file) else {
                // Writing belongs to the user. Never repair corrupt files by discarding it.
                throw NotebookError.storageUnavailable
            }
            return file
        }
        let empty = File(schema: 1, scope: scope, state: NotebookState(revision: 0, epoch: UUID(), notes: [], topics: []))
        // Persist even an empty epoch so a stale editor cannot survive a reset/reopen.
        try write(empty)
        return empty
    }

    private func write(_ file: File) throws {
        guard valid(file) else { throw NotebookError.invalidInput }
        let data = try JSONEncoder().encode(file)
        guard data.count <= Self.maximumFileBytes else { throw NotebookError.limitReached }
        if let url = try fileURL(file.scope), let directory {
            let exists = try fileExists(url)
            let previousSize = exists ? try regularFileSize(url) : 0
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            guard exists || files.count < Self.maximumScopes else { throw NotebookError.limitReached }
            var total = data.count
            for other in files where other.standardizedFileURL != url.standardizedFileURL {
                let size = try regularFileSize(other)
                guard total <= Int.max - size else { throw NotebookError.storageUnavailable }
                total += size
            }
            // Reductions remain possible even when another scope has filled the budget.
            guard total <= Self.maximumTotalBytes || (exists && data.count <= previousSize) else { throw NotebookError.limitReached }
            try writeAtomically(data, url)
        } else {
            var total = data.count
            for (scope, other) in memory where scope != file.scope { total += try JSONEncoder().encode(other).count }
            let oldSize = try memory[file.scope].map { try JSONEncoder().encode($0).count } ?? 0
            guard total <= Self.maximumTotalBytes || data.count <= oldSize,
                  memory[file.scope] != nil || memory.count < Self.maximumScopes else { throw NotebookError.limitReached }
            memory[file.scope] = file
        }
    }

    private func fileExists(_ url: URL) throws -> Bool {
        // attributesOfItem sees dangling symlinks, unlike fileExists(atPath:).
        do {
            _ = try FileManager.default.attributesOfItem(atPath: url.path)
            return true
        } catch let error as NSError where error.domain == NSCocoaErrorDomain &&
            (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) {
            return false
        }
    }
    private func regularFileSize(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.intValue, size >= 0 else { throw NotebookError.storageUnavailable }
        return size
    }
    private func fileURL(_ scope: AccountScope) throws -> URL? {
        guard var directory else { return nil }
        guard directory.standardizedFileURL.path == directory.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw NotebookError.storageUnavailable
        }
        // Foundation may leave a symlink ancestor unresolved when the last child
        // does not exist yet. Inspect ancestors before createDirectory can follow it.
        var ancestor = directory.standardizedFileURL
        while ancestor.path != "/" {
            if try fileExists(ancestor) {
                let attributes = try FileManager.default.attributesOfItem(atPath: ancestor.path)
                if attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                    // Foundation intentionally normalizes these OS-owned aliases.
                    let systemTarget = ["/var": "/private/var", "/tmp": "/private/tmp"][ancestor.path]
                    let target = try FileManager.default.destinationOfSymbolicLink(atPath: ancestor.path)
                    guard let systemTarget, target == systemTarget || target == String(systemTarget.dropFirst()) else {
                        throw NotebookError.storageUnavailable
                    }
                } else if attributes[.type] as? FileAttributeType != .typeDirectory {
                    throw NotebookError.storageUnavailable
                }
            }
            ancestor.deleteLastPathComponent()
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw NotebookError.storageUnavailable }
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        // Encode the pair rather than concatenating, avoiding guest/account key collisions.
        let identity = try JSONEncoder().encode([scope.environment.rawValue, scope.accountID])
        let key = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: key + ".json")
    }
}
