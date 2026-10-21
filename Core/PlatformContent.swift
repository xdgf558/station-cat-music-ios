import Foundation
import Observation

nonisolated enum PlatformContentURL {
    static func valid(_ url: URL) -> Bool {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return c.scheme == "https" && c.host == PlatformMusicAPI.productionOrigin.host &&
            c.user == nil && c.password == nil && c.port == nil && c.query == nil && c.fragment == nil &&
            c.percentEncodedPath.range(of: "^/api/station/content/assets/[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$", options: .regularExpression) != nil
    }
}

nonisolated struct PlatformLyrics: Equatable, Sendable {
    let stanzas: [String]
    init(data: Data, kind: String?) throws {
        guard data.count <= 262_144, let decoded = String(data: data, encoding: .utf8),
              decoded.utf16.count <= 65_536,
              !decoded.unicodeScalars.contains(where: { ($0.value < 32 && ![9, 10, 13].contains($0.value)) || $0.value == 127 }) else { throw APIError.invalidPayload }
        var text = decoded.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        // LRC is displayed as a reading document, never synchronized to an
        // external player's progress. Keep original lyric order and stanza breaks.
        if kind?.lowercased() == "lrc" {
            text = text.components(separatedBy: "\n").compactMap { line -> String? in
                if line.range(of: "^\\s*\\[(?:ar|al|ti|by|offset|re|ve|length):[^\\]]*\\]\\s*$", options: [.regularExpression, .caseInsensitive]) != nil { return nil }
                return line.replacingOccurrences(of: "^(?:\\s*\\[\\d{1,3}:\\d{2}(?:[.:]\\d{1,3})?\\])+\\s*", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "<\\d{1,3}:\\d{2}(?:[.:]\\d{1,3})?>", with: "", options: .regularExpression)
            }.joined(separator: "\n")
        }
        var paragraphs: [String] = [], lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            let line = line.trimmingCharacters(in: .whitespaces)
            guard line.utf16.count <= 2000 else { throw APIError.invalidPayload }
            if line.isEmpty {
                if !lines.isEmpty { paragraphs.append(lines.joined(separator: "\n")); lines = [] }
            } else { lines.append(line) }
        }
        if !lines.isEmpty { paragraphs.append(lines.joined(separator: "\n")) }
        guard paragraphs.count <= 1000 else { throw APIError.invalidPayload }
        stanzas = paragraphs
    }
}

nonisolated struct PlatformClip: Identifiable, Equatable, Sendable {
    let id, trackID: String
    let revision: Int
    let title, summary: String
    enum Source: Equatable, Sendable {
        case file(poster: URL, media: URL, duration: Double)
        case youtube(YouTubeClip)
    }
    let source: Source
    var posterURL: URL? { if case let .file(poster, _, _) = source { return poster }; return nil }
    var mediaURL: URL? { if case let .file(_, media, _) = source { return media }; return nil }
    var youtube: YouTubeClip? { if case let .youtube(value) = source { return value }; return nil }
    init(id: String, trackID: String, revision: Int, title: String, summary: String, duration: Double, posterURL: URL, mediaURL: URL) {
        self.id = id; self.trackID = trackID; self.revision = revision; self.title = title; self.summary = summary
        source = .file(poster: posterURL, media: mediaURL, duration: duration)
    }
    init(id: String, trackID: String, revision: Int, title: String, summary: String, youtube: YouTubeClip) {
        self.id = id; self.trackID = trackID; self.revision = revision; self.title = title; self.summary = summary
        source = .youtube(youtube)
    }
}

/// Ephemeral view state, independent of the old audio player and personal data.
/// No lyrics, story, clip URL or media is persisted across detail presentations.
@MainActor @Observable final class PlatformContentModel {
    enum Phase: Equatable { case loading, empty, loaded, failed }
    private(set) var lyrics: PlatformLyrics?
    private(set) var clips: [PlatformClip] = []
    private(set) var lyricsPhase: Phase = .empty
    private(set) var clipsPhase: Phase = .empty
    private(set) var lyricsFailureKey = "contentLoadFailure"
    private(set) var clipsFailureKey = "contentLoadFailure"
    @ObservationIgnored private var lyricsTask: Task<Void, Never>?
    @ObservationIgnored private var clipsTask: Task<Void, Never>?
    private var generation = 0
    private var detail: PlatformTrackDetail?
    private var locale = "en"
    private var provider: (any PlatformMusicProviding)?

    func configure(_ detail: PlatformTrackDetail?, locale: String, provider: (any PlatformMusicProviding)?) {
        clear(); self.detail = detail; self.locale = locale; self.provider = provider
        guard detail != nil, provider != nil else { return }
        retryLyrics(); retryClips()
    }
    func clear() {
        generation += 1; lyricsTask?.cancel(); clipsTask?.cancel()
        lyricsTask = nil; clipsTask = nil; detail = nil; provider = nil
        lyrics = nil; clips = []; lyricsPhase = .empty; clipsPhase = .empty
    }
    func retryLyrics() {
        guard let detail, let provider else { return }
        lyricsTask?.cancel(); lyrics = nil
        guard detail.lyricsURL != nil else { lyricsPhase = .empty; return }
        lyricsPhase = .loading
        let ticket = generation
        lyricsTask = Task { [weak self] in
            do {
                let result = try await provider.lyrics(detail)
                guard let self, !Task.isCancelled, self.generation == ticket else { return }
                self.lyrics = result; self.lyricsPhase = result?.stanzas.isEmpty == false ? .loaded : .empty
            } catch {
                guard let self, !Task.isCancelled, self.generation == ticket else { return }
                self.lyricsFailureKey = Self.message(error); self.lyricsPhase = .failed
            }
        }
    }
    func retryClips() {
        guard let detail, let provider else { return }
        clipsTask?.cancel(); clips = []; clipsPhase = .loading
        let ticket = generation, locale = locale
        clipsTask = Task { [weak self] in
            do {
                let result = try await provider.clips(detail.track, locale: locale)
                guard let self, !Task.isCancelled, self.generation == ticket else { return }
                self.clips = result; self.clipsPhase = result.isEmpty ? .empty : .loaded
            } catch {
                guard let self, !Task.isCancelled, self.generation == ticket else { return }
                self.clipsFailureKey = Self.message(error); self.clipsPhase = .failed
            }
        }
    }
    private static func message(_ error: Error) -> String {
        if case APIError.rejected(let code) = error, code == 404 || code == 410 { return "contentWithdrawn" }
        return "contentLoadFailure"
    }
}
