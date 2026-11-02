import Foundation

/// A link to a public work. The accompanying image is a preview; the URL is
/// the shared item so the receiving app can present a clickable link card.
nonisolated struct PlatformShareCard: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case track, album }
    let kind: Kind
    let id: String
    let title: String
    let artist: String
    let summary: String
    let artwork: Track?
    let albumArtworkURL: URL?
    let url: URL

    private static func link(kind: Kind, slug: String, locale: String) -> URL? {
        guard PlatformMusicAPI.locales.contains(locale), slug.count <= 100,
              slug.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil else { return nil }
        var parts = URLComponents(url: PlatformMusicAPI.productionOrigin, resolvingAgainstBaseURL: false)
        parts?.path = "/music/share/\(kind == .track ? "tracks" : "albums")/\(slug)/"
        parts?.queryItems = [.init(name: "locale", value: locale)]
        return parts?.url
    }

    static func track(_ detail: PlatformTrackDetail, locale: String) -> Self? {
        let track = detail.track
        guard let release = track.release, let url = link(kind: .track, slug: release.slug, locale: locale) else { return nil }
        return Self(kind: .track, id: track.id, title: track.title, artist: track.artist,
                    summary: release.summary, artwork: track, albumArtworkURL: nil, url: url)
    }

    static func album(_ album: PlatformAlbum, locale: String) -> Self? {
        // Never guess a slug from a title or from the first song. Every member
        // must agree on the same published album identity and revision.
        let memberships = album.tracks.compactMap { track in
            track.release?.albums?.first(where: { $0.id == album.id })
        }
        guard !album.tracks.isEmpty, memberships.count == album.tracks.count,
              let first = memberships.first,
              first.version > 0, first.version <= 9_007_199_254_740_991,
              memberships.allSatisfy({ $0.slug == first.slug && $0.version == first.version &&
                  $0.title == album.title && $0.summary == album.summary }),
              let url = link(kind: .album, slug: first.slug, locale: locale) else { return nil }
        var image = URLComponents(url: PlatformMusicAPI.productionOrigin, resolvingAgainstBaseURL: false)!
        image.path = "/music/share/albums/\(first.slug)/cover.png"
        return Self(kind: .album, id: album.id, title: album.title, artist: "",
                    summary: album.summary, artwork: nil, albumArtworkURL: image.url, url: url)
    }
}
