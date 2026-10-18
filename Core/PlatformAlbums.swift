import Foundation

nonisolated enum PlatformCatalogCategory: String, CaseIterable, Identifiable, Sendable {
    case all, singles, albums
    var id: String { rawValue }
    var titleKey: String { "catalogCategory." + rawValue }
    var symbol: String {
        switch self { case .all: "square.grid.2x2"; case .singles: "music.note"; case .albums: "square.stack" }
    }
}

/// Published album metadata, with this song's operator-defined position.
/// No media or external destination is derived from an album identity.
nonisolated struct PlatformAlbumMembership: Codable, Equatable, Sendable {
    let id: String
    let slug: String
    let title: String
    let summary: String
    let version: Int
    let position: Int
}

nonisolated struct PlatformAlbum: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let summary: String
    let tracks: [Track]
    var artist: String { Array(Set(tracks.map(\.artist))).sorted().joined(separator: " · ") }
    func matches(_ query: String) -> Bool {
        query.isEmpty || ([title, artist] + tracks.map(\.title)).joined(separator: " ").localizedCaseInsensitiveContains(query)
    }

    static func catalog(_ tracks: [Track]) throws -> [Self] {
        var order: [String] = []
        var metadata: [String: PlatformAlbumMembership] = [:]
        var members: [String: [(Int, Track)]] = [:]
        for track in tracks {
            for album in track.release?.albums ?? [] {
                if let previous = metadata[album.id] {
                    // A publication changed between source pages. Never mix
                    // different album versions or contradictory track order.
                    guard previous.slug == album.slug, previous.title == album.title,
                          previous.summary == album.summary, previous.version == album.version,
                          members[album.id]?.contains(where: { $0.0 == album.position || $0.1.id == track.id }) == false else {
                        throw APIError.invalidPayload
                    }
                } else { order.append(album.id); metadata[album.id] = album }
                members[album.id, default: []].append((album.position, track))
            }
        }
        return order.compactMap { id in
            guard let album = metadata[id], let songs = members[id] else { return nil }
            return Self(id: id, title: album.title, summary: album.summary, tracks: songs.sorted { $0.0 < $1.0 }.map(\.1))
        }
    }
}
