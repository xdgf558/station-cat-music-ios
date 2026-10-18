import Foundation

nonisolated enum PlatformProvider: String, Codable, CaseIterable, Sendable {
    case netease, qishui, appleMusic = "apple_music", youtube, spotify
}
nonisolated struct PlatformLink: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let provider: PlatformProvider
    let url: URL
}
nonisolated struct PlatformTrackRelease: Codable, Equatable, Sendable {
    let slug: String
    let summary: String
    let webURL: URL
    let platforms: [PlatformLink]
    let availability: String
    let previewAvailable: Bool
    // nil: an older server, or classification unavailable. []: no published
    // album membership. Do not infer membership from a platform's album URL.
    var albums: [PlatformAlbumMembership]? = nil
}
nonisolated struct PlatformTrackDetail: Sendable {
    let track: Track
    let story: String
    let lyricsURL: URL?
}
nonisolated protocol PlatformMusicProviding: CatalogProviding {
    var webOrigin: URL { get }
    func setLocale(_ locale: String) async
    func featuredTracks() async throws -> [Track]
    func platformDetail(_ track: Track, locale: String) async throws -> PlatformTrackDetail
    func resolvePlatformTrack(slug: String, locale: String) async throws -> PlatformTrackDetail
    func bookmark(_ track: Track, locale: String) async throws -> PlatformBookmark
}

extension PlatformMusicProviding {
    func resolvePlatformTrack(slug: String, locale: String) async throws -> PlatformTrackDetail { throw APIError.networkDisabled }
    func bookmark(_ track: Track, locale: String) async throws -> PlatformBookmark { throw APIError.networkDisabled }
}

/// Public website metadata only. This client never requests audio, a native
/// session, playback grants or offline permits, and owns no account credentials.
actor PlatformMusicAPI: PlatformMusicProviding {
    nonisolated let webOrigin: URL
    private let transport: any HTTPTransport
    private var locale = "en"
    private var localeVersion = 0
    private let now: @Sendable () -> Date
    nonisolated static let productionOrigin = URL(string: ProductionActivationProfile.origin)!
    nonisolated static let locales = ["en", "zh-Hans", "zh-Hant", "ja"]
    nonisolated static let contentPath = "/api/station/content"

    init(origin: URL = PlatformMusicAPI.productionOrigin, explicitlyEnabled: Bool,
         transport: any HTTPTransport, now: @escaping @Sendable () -> Date = { Date() }) throws {
        guard explicitlyEnabled else { throw APIError.networkDisabled }
        guard let components = URLComponents(url: origin, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.host == Self.productionOrigin.host,
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil,
              components.percentEncodedPath.isEmpty || components.percentEncodedPath == "/" else { throw APIError.invalidRequest }
        self.webOrigin = Self.productionOrigin
        self.transport = transport
        self.now = now
    }
    func setLocale(_ value: String) {
        let next = Self.locales.contains(value) ? value : "en"
        if next != locale { locale = next; localeVersion += 1 }
    }
    private func request<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem], as: T.Type, cacheExpiry: ((Date) -> Void)? = nil) async throws -> T {
        guard path == "/home" || path == "/tracks" || path.range(of: "^/tracks/[a-z0-9]+(?:-[a-z0-9]+)*(?:/bookmark)?$", options: .regularExpression) != nil else { throw APIError.invalidRequest }
        var components = URLComponents(url: webOrigin, resolvingAgainstBaseURL: false)!
        components.path = Self.contentPath + path
        components.queryItems = query
        guard let url = components.url else { throw APIError.invalidRequest }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let started = ContinuousClock.now
        let result = try await transport.send(request)
        try Task.checkCancellation()
        guard result.status == 200 else { throw APIError.rejected(result.status) }
        guard result.data.count <= 262_144, result.finalURL == url,
              let contentType = result.headers.first(where: { $0.key.lowercased() == "content-type" })?.value,
              contentType.split(separator: ";", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces).lowercased() == "application/json" else { throw APIError.invalidPayload }
        if let cacheExpiry {
            let received = now()
            guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: result.headers),
                  let expiry = ArtworkFreshness.expiration(response, responseTime: received, storedAt: received,
                    responseDelay: ArtworkFreshness.seconds(started.duration(to: .now)), residentTime: 0) else { throw APIError.invalidPayload }
            cacheExpiry(expiry)
        }
        do { return try JSONDecoder().decode(T.self, from: result.data) }
        catch { throw APIError.invalidPayload }
    }
    private func current(_ version: Int) throws {
        guard version == localeVersion else { throw APIError.staleResponse }
        try Task.checkCancellation()
    }
    func catalog() async throws -> Catalog {
        let requestedLocale = locale, version = localeVersion
        var items: [Track] = [], cursor: String?, cursors = Set<String>(), pages = 0
        repeat {
            var query = [URLQueryItem(name: "locale", value: requestedLocale), .init(name: "limit", value: "50"), .init(name: "sort", value: "default")]
            if let cursor {
                guard Self.cursor(cursor), cursors.insert(cursor).inserted else { throw APIError.invalidPayload }
                query.append(.init(name: "cursor", value: cursor))
            }
            let result = try await request("/tracks", query: query, as: PlatformCatalogDTO.self)
            try current(version)
            guard result.schemaVersion == 1, result.locale == requestedLocale, result.items.count <= 50 else { throw APIError.invalidPayload }
            items += try result.items.map { try project($0, locale: requestedLocale) }
            pages += 1
            guard items.count <= 500, pages <= 10 else { throw APIError.invalidPayload }
            cursor = result.nextCursor
            if let cursor { guard Self.cursor(cursor), pages < 10 else { throw APIError.invalidPayload } }
        } while cursor != nil
        guard Set(items.map { $0.id.lowercased() }).count == items.count else { throw APIError.invalidPayload }
        _ = try PlatformAlbum.catalog(items)
        return Catalog(items: items, nextCursor: nil)
    }
    func featuredTracks() async throws -> [Track] {
        let requestedLocale = locale, version = localeVersion
        let result = try await request("/home", query: [.init(name: "locale", value: requestedLocale)], as: PlatformHomeDTO.self)
        try current(version)
        guard result.schemaVersion == 1, result.home.locale == requestedLocale, result.home.fixture == false,
              result.home.selectedTracks.count <= 3 else { throw APIError.invalidPayload }
        let summaries = (result.home.music.map { [$0] } ?? []) + result.home.selectedTracks
        guard Set(summaries.map { $0.id.lowercased() }).count == summaries.count else { throw APIError.invalidPayload }
        let details = try summaries.map { summary -> (id: String, slug: String) in
            guard Self.uuid(summary.id), Self.plain(summary.title, max: 200, required: true),
                  Self.plain(summary.artist, max: 120, required: true), Self.plain(summary.summary, max: 500),
                  let slug = Self.detailSlug(summary.href, locale: requestedLocale) else { throw APIError.invalidPayload }
            if let cover = summary.coverUrl { _ = try assetURL(cover, display: true) }
            return (id: summary.id, slug: slug)
        }
        // The validated home response bounds this group to one primary plus
        // three selected tracks. Network completion order never changes the
        // editor's order, and one invalid/failed detail rejects the whole result.
        return try await withThrowingTaskGroup(of: (Int, Track).self) { group in
            for (index, value) in details.enumerated() {
                group.addTask {
                    try Task.checkCancellation()
                    let result = try await self.detail(slug: value.slug, id: value.id, locale: requestedLocale)
                    try await self.current(version)
                    return (index, result.track)
                }
            }
            var ordered = [Track?](repeating: nil, count: details.count)
            for try await (index, track) in group {
                try current(version)
                ordered[index] = track
            }
            try current(version)
            return try ordered.map { value in
                guard let value else { throw APIError.invalidPayload }
                return value
            }
        }
    }
    func platformDetail(_ track: Track, locale requestedLocale: String) async throws -> PlatformTrackDetail {
        guard Self.locales.contains(requestedLocale), Self.uuid(track.id), let release = track.release,
              Self.slug(release.slug), Self.locales.contains(where: {
                  release.webURL == Self.webURL(origin: webOrigin, path: Self.detailPath(locale: $0, slug: release.slug))
              }) else { throw APIError.invalidRequest }
        let version = localeVersion
        let result = try await detail(slug: release.slug, id: track.id, locale: requestedLocale)
        try current(version)
        return result
    }
    func resolvePlatformTrack(slug: String, locale: String) async throws -> PlatformTrackDetail {
        guard Self.slug(slug), Self.locales.contains(locale) else { throw APIError.invalidRequest }
        return try await detail(slug: slug, id: nil, locale: locale)
    }
    func bookmark(_ track: Track, locale: String) async throws -> PlatformBookmark {
        guard Self.uuid(track.id), let slug = track.release?.slug, Self.slug(slug), Self.locales.contains(locale) else { throw APIError.invalidRequest }
        var expires: Date?
        let value = try await request("/tracks/" + slug + "/bookmark", query: [.init(name: "locale", value: locale)], as: PlatformBookmarkDTO.self, cacheExpiry: { expires = $0 })
        guard value.schemaVersion == 1, value.locale == locale, let expires,
              value.bookmark.id.lowercased() == track.id.lowercased(), value.bookmark.slug == slug else { throw APIError.invalidPayload }
        let item = PlatformBookmark(id: track.id, slug: slug, title: value.bookmark.title, artist: value.bookmark.artist,
            revision: value.bookmark.revision, locale: locale, savedAt: now(), expires: expires)
        guard item.valid else { throw APIError.invalidPayload }
        return item
    }
    private func detail(slug: String, id: String?, locale: String) async throws -> PlatformTrackDetail {
        let result = try await request("/tracks/" + slug, query: [.init(name: "locale", value: locale)], as: PlatformDetailDTO.self)
        guard result.schemaVersion == 1, result.locale == locale, (id == nil || result.track.id.lowercased() == id?.lowercased()), result.track.slug == slug else { throw APIError.invalidPayload }
        let track = try project(result.track, locale: locale)
        let story = result.track.story ?? ""
        guard Self.story(story) else { throw APIError.invalidPayload }
        let lyrics = try result.track.lyricsUrl.map { try assetURL($0, display: false) }
        return PlatformTrackDetail(track: track, story: story, lyricsURL: lyrics)
    }
    private func project(_ value: PlatformTrackDTO, locale: String) throws -> Track {
        guard Self.uuid(value.id), Self.slug(value.slug), value.revision > 0, value.revision <= 9_007_199_254_740_991,
              Self.locales.contains(value.originalLocale), Self.plain(value.title, max: 200, required: true),
              Self.plain(value.artist, max: 120, required: true), Self.plain(value.summary, max: 500),
              value.href == Self.detailPath(locale: locale, slug: value.slug),
              value.coverCacheVersion == nil || (value.coverUrl != nil && value.coverCacheVersion!.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil),
              Self.availability.contains(value.platformAvailability.state), value.platforms.count <= 25,
              value.durationMs == nil || (value.durationMs!.isFinite && value.durationMs! > 0 && value.durationMs! <= 86_400_000 && value.durationMs!.rounded() == value.durationMs!) else { throw APIError.invalidPayload }
        if let preview = value.preview {
            guard preview.revision > 0, preview.durationMs.isFinite, preview.durationMs > 0, preview.durationMs <= 45_000,
                  preview.playbackPath == Self.contentPath + "/tracks/" + value.slug + "/playback?variant=preview" else { throw APIError.invalidPayload }
        }
        let links = Self.validatedLinks(value.platforms, now: now())
        if let albums = value.albums {
            guard albums.count <= 25, Set(albums.map { $0.id.lowercased() }).count == albums.count,
                  albums.allSatisfy({ Self.uuid($0.id) && Self.slug($0.slug) && Self.plain($0.title, max: 200, required: true) &&
                    Self.plain($0.summary, max: 500) && $0.version > 0 && $0.version <= 9_007_199_254_740_991 &&
                    $0.position >= 0 && $0.position <= 9_007_199_254_740_991 }) else { throw APIError.invalidPayload }
        }
        let release = PlatformTrackRelease(slug: value.slug, summary: value.summary,
            webURL: Self.webURL(origin: webOrigin, path: value.href), platforms: links,
            availability: value.platformAvailability.state == "available" && links.isEmpty ? "unconfirmed" : value.platformAvailability.state,
            previewAvailable: value.preview != nil, albums: value.albums?.map {
                PlatformAlbumMembership(id: $0.id.lowercased(), slug: $0.slug, title: $0.title, summary: $0.summary,
                                        version: $0.version, position: $0.position)
            })
        return Track(id: value.id, title: value.title, artist: value.artist,
            durationSeconds: (value.durationMs ?? 0) / 1000, audioVersion: value.revision, access: .unavailable,
            coverUrl: try value.coverUrl.map { try assetURL($0, display: true, cacheVersion: value.coverCacheVersion) }, offlineEligible: false, release: release)
    }
    private func assetURL(_ value: String, display: Bool, cacheVersion: String? = nil) throws -> URL {
        guard let components = URLComponents(string: value), components.scheme == nil, components.host == nil,
              components.user == nil, components.password == nil, components.port == nil, components.fragment == nil,
              components.percentEncodedPath.range(of: "^/api/station/content/assets/[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$", options: .regularExpression) != nil,
              components.query == nil || (display && components.percentEncodedQuery == "size=display") else { throw APIError.invalidPayload }
        var absolute = URLComponents(url: webOrigin, resolvingAgainstBaseURL: false)!
        absolute.percentEncodedPath = components.percentEncodedPath
        if display {
            absolute.queryItems = [.init(name: "size", value: "display")]
            if let cacheVersion { absolute.queryItems?.append(.init(name: "v", value: cacheVersion)) }
        }
        return absolute.url!
    }
    nonisolated private static let availability = ["available", "region_restricted", "unreleased", "removed", "unconfirmed"]
    nonisolated private static func uuid(_ value: String) -> Bool {
        value.range(of: "^[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$", options: .regularExpression) != nil
    }
    nonisolated private static func slug(_ value: String) -> Bool {
        value.count <= 100 && value.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil
    }
    nonisolated private static func cursor(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9_-]{1,512}$", options: .regularExpression) != nil
    }
    nonisolated private static func plain(_ value: String, max: Int, required: Bool = false) -> Bool {
        value.utf16.count <= max && (!required || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
            !value.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
    }
    nonisolated private static func story(_ value: String) -> Bool {
        value.utf16.count <= 8000 && !value.unicodeScalars.contains { $0.value < 32 && ![9, 10, 13].contains($0.value) || $0.value == 127 }
    }
    nonisolated private static func detailPath(locale: String, slug: String) -> String {
        (locale == "zh-Hant" ? "" : locale == "zh-Hans" ? "/zh-hans" : "/" + locale) + "/music/tracks/" + slug + "/"
    }
    nonisolated private static func webURL(origin: URL, path: String) -> URL {
        var components = URLComponents(url: origin, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath = path
        return components.url!
    }
    nonisolated private static func detailSlug(_ href: String, locale: String) -> String? {
        let prefix = detailPath(locale: locale, slug: "")
        let parts = href.split(separator: "/")
        guard let name = parts.last.map(String.init), slug(name), href == prefix.replacingOccurrences(of: "//", with: "/") + name + "/" else { return nil }
        return name
    }
    nonisolated private static func validatedLinks(_ values: [PlatformLinkDTO], now: Date) -> [PlatformLink] {
        var counts: [String: Int] = [:]
        for value in values where uuid(value.id) { counts[value.id.lowercased(), default: 0] += 1 }
        return values.compactMap { value in
            guard uuid(value.id), counts[value.id.lowercased()] == 1, value.status == "live",
                  let provider = PlatformProvider(rawValue: value.provider), let verified = date(value.verifiedAt),
                  verified.timeIntervalSince1970 >= 0, verified <= now, let url = platformURL(value.href, provider: provider) else { return nil }
            return PlatformLink(id: value.id, provider: provider, url: url)
        }
    }
    nonisolated private static func date(_ value: String) -> Date? {
        guard value.range(of: "^\\d{4}-\\d\\d-\\d\\dT", options: .regularExpression) != nil else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    /// Mirrors the website provider allowlist, including the one supported
    /// NetEase fragment alias. It never accepts app schemes or redirect targets.
    nonisolated static func platformURL(_ value: String, provider: PlatformProvider) -> URL? {
        let hosts: [PlatformProvider: Set<String>] = [
            .netease: ["music.163.com", "y.music.163.com"], .qishui: ["music.douyin.com", "qishui.douyin.com"],
            .appleMusic: ["music.apple.com"], .youtube: ["www.youtube.com", "music.youtube.com", "youtu.be"], .spotify: ["open.spotify.com"]]
        guard plain(value, max: 2048), !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || $0 == "\\" }),
              var components = URLComponents(string: value), components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(), hosts[provider]?.contains(host) == true,
              components.user == nil, components.password == nil, components.port == nil || components.port == 443 else { return nil }
        components.scheme = "https"; components.host = host; components.port = nil
        if let fragment = components.percentEncodedFragment, !fragment.isEmpty {
            guard provider == .netease, host == "music.163.com", components.percentEncodedPath == "/", components.query == nil,
                  fragment.range(of: "^/song\\?id=[1-9]\\d{0,19}$", options: .regularExpression) != nil else { return nil }
            components.path = "/song"; components.percentEncodedQuery = "id=" + fragment.dropFirst("/song?id=".count); components.fragment = nil
        } else { components.fragment = nil }
        guard !components.path.isEmpty, components.path != "/",
              components.path.range(of: "^/(?:redirect|login|oauth|auth)(?:/|$)", options: [.regularExpression, .caseInsensitive]) == nil,
              !components.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
              !(components.queryItems ?? []).contains(where: { $0.name.range(of: "token|secret|credential|signature|authorization|x-amz|redirect|target|return|^next$|^url$", options: [.regularExpression, .caseInsensitive]) != nil }) else { return nil }
        return components.url
    }
}

nonisolated private struct PlatformCatalogDTO: Decodable, Sendable {
    let schemaVersion: Int; let locale: String; let items: [PlatformTrackDTO]; let nextCursor: String?
}
nonisolated private struct PlatformDetailDTO: Decodable, Sendable {
    let schemaVersion: Int; let locale: String; let track: PlatformTrackDTO
}
nonisolated private struct PlatformHomeDTO: Decodable, Sendable {
    let schemaVersion: Int; let home: Home
    struct Home: Decodable, Sendable { let locale: String; let fixture: Bool; let music: Summary?; let selectedTracks: [Summary] }
    struct Summary: Decodable, Sendable {
        let id: String; let title: String; let artist: String; let summary: String; let coverUrl: String?; let href: String
    }
}
nonisolated private struct PlatformTrackDTO: Decodable, Sendable {
    let id: String; let slug: String; let revision: Int; let originalLocale: String
    let title: String; let artist: String; let summary: String; let durationMs: Double?; let href: String; let coverUrl: String?
    let coverCacheVersion: String?
    let albums: [PlatformAlbumMembership]?
    let preview: Preview?; let platformAvailability: Availability; let platforms: [PlatformLinkDTO]
    let story: String?; let lyricsUrl: String?
    struct Preview: Decodable, Sendable { let durationMs: Double; let revision: Int; let playbackPath: String }
    struct Availability: Decodable, Sendable { let state: String }
}
nonisolated private struct PlatformLinkDTO: Decodable, Sendable {
    let id: String; let provider: String; let status: String; let href: String; let verifiedAt: String
}

nonisolated private struct PlatformBookmarkDTO: Decodable, Sendable {
    let schemaVersion: Int
    let locale: String
    let bookmark: Item
    struct Item: Decodable, Sendable { let id, slug, title, artist: String; let revision: Int }
}
