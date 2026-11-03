import XCTest
@testable import StationCatMusic

private actor AlbumTestTransport: HTTPTransport {
    let fixture: PlatformFixtureTransport
    private var failure = false
    init(data: Data) { fixture = PlatformFixtureTransport(data: data) }
    func setFailure(_ value: Bool) { failure = value }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        if failure { throw URLError(.notConnectedToInternet) }
        return try await fixture.send(request)
    }
}

@MainActor final class PlatformAlbumTests: XCTestCase {
    func testShelfSearchMatchesAlbumNamesWithoutChangingUnknownClassification() {
        var song = Track(id: "11111111-1111-4111-8111-111111111111", title: "A song", artist: "Station Cat",
                         durationSeconds: 0, audioVersion: 1, access: .unavailable)
        song.release = PlatformTrackRelease(slug: "a-song", summary: "", webURL: PlatformMusicAPI.productionOrigin,
            platforms: [], availability: "available", previewAvailable: false, albums: [
                .init(id: "album", slug: "after-the-rain", title: "After the Rain", summary: "", version: 1, position: 0)])
        XCTAssertTrue(PlatformShelfSearch.matches(song, query: "  after the rain  "))
        XCTAssertTrue(PlatformShelfSearch.matches(song, query: "station cat"))
        XCTAssertTrue(PlatformShelfSearch.matches(song, query: "a song"))
        XCTAssertFalse(PlatformShelfSearch.matches(song, query: "another album"))
        song.release?.albums = nil
        XCTAssertFalse(PlatformShelfSearch.matches(song, query: "After the Rain"))
        XCTAssertNil(song.release?.albums, "A search must not turn unknown membership into a single")
        XCTAssertTrue(PlatformShelfSearch.matches(song, query: "\n  "))
    }

    func testCategorySearchOrderRefreshAndDetailKeepThePlatformBoundary() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "platform-albums", withExtension: "json"))
        let transport = AlbumTestTransport(data: try Data(contentsOf: url))
        let api = try PlatformMusicAPI(explicitlyEnabled: true, transport: transport)
        let directory = FileManager.default.temporaryDirectory.appending(path: "albums-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(client: api, library: ScopedLibrary(directory: directory), platformMode: true)
        model.locale = "zh-Hans"
        await model.initialize()
        XCTAssertEqual(model.tracks.count, 10)
        XCTAssertEqual(model.platformAlbums.count, 4)
        XCTAssertEqual(model.platformSingles.count, 2)
        XCTAssertFalse(model.platformClassificationUnavailable)
        let before = model.tracks
        model.catalogCategory = .singles
        XCTAssertEqual(model.platformCatalogTracks.map(\.id), model.platformSingles.map(\.id))
        model.query = "Night"
        XCTAssertEqual(model.platformCatalogTracks.count, 1)
        model.catalogCategory = .albums; model.query = "原来已经这么远"
        XCTAssertEqual(model.platformCatalogAlbums.map(\.title), ["夜窗来信"])
        let album = try XCTUnwrap(model.platformCatalogAlbums.first)
        XCTAssertEqual(album.tracks.map { $0.release?.albums?.first?.position }, [0, 1])
        XCTAssertEqual(album.tracks.first?.title, "原来已经这么远")
        XCTAssertEqual(model.tracks, before, "Category/search must not mutate the catalog or favorites")
        await transport.setFailure(true); await model.load()
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertEqual(model.tracks, before)
        XCTAssertNotNil(model.catalogFailure)
        await transport.setFailure(false); await model.load()
        XCTAssertNil(model.catalogFailure)
        model.selectPlatformTrack(album.tracks[0])
        for _ in 0..<100 { if model.platformDetail != nil { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.platformDetail?.track.id, album.tracks[0].id)
        XCTAssertFalse(model.playback.hasAudioSource)
        XCTAssertNil(model.nativeMusic)
        XCTAssertNil(model.libraryRemote)
    }
    func testOneSongCanBelongToMultipleAlbumsWithoutDuplicatingTheAllList() throws {
        var song = Track(id: "11111111-1111-4111-8111-111111111111", title: "Shared song", artist: "Station Cat", durationSeconds: 0, audioVersion: 1, access: .unavailable)
        song.release = PlatformTrackRelease(slug: "shared-song", summary: "", webURL: PlatformMusicAPI.productionOrigin,
            platforms: [], availability: "unreleased", previewAvailable: false, albums: [
                .init(id: "a", slug: "first", title: "First", summary: "", version: 1, position: 4),
                .init(id: "b", slug: "second", title: "Second", summary: "", version: 1, position: 0)])
        let albums = try PlatformAlbum.catalog([song])
        XCTAssertEqual(albums.map(\.id), ["a", "b"])
        XCTAssertEqual(albums.map { $0.tracks.count }, [1, 1])
    }

    func testShareCardsUsePublishedIntroductionsAndBoundedIdentities() throws {
        let first = PlatformAlbumMembership(id: "album-id", slug: "real-album", title: "Real album",
            summary: "The real album introduction.", version: 7, position: 0)
        var song = Track(id: "11111111-1111-4111-8111-111111111111", title: "Real song", artist: "Station Cat",
            durationSeconds: 0, audioVersion: 1, access: .unavailable)
        song.release = PlatformTrackRelease(slug: "real-song", summary: "The real song introduction.",
            webURL: PlatformMusicAPI.productionOrigin, platforms: [], availability: "available", previewAvailable: false,
            albums: [first])
        let detail = PlatformTrackDetail(track: song, story: "A separate story.", lyricsURL: nil)
        let songCard = try XCTUnwrap(PlatformShareCard.track(detail, locale: "zh-Hans"))
        XCTAssertEqual(songCard.summary, "The real song introduction.")
        XCTAssertEqual(songCard.url.absoluteString, "https://wwwstationcat.org/music/share/tracks/real-song/?locale=zh-Hans")
        XCTAssertNil(songCard.albumArtworkURL)

        let album = try XCTUnwrap(PlatformAlbum.catalog([song]).first)
        let albumCard = try XCTUnwrap(PlatformShareCard.album(album, locale: "ja"))
        XCTAssertEqual(albumCard.summary, "The real album introduction.")
        XCTAssertEqual(albumCard.url.absoluteString, "https://wwwstationcat.org/music/share/albums/real-album/?locale=ja")
        XCTAssertEqual(albumCard.albumArtworkURL?.absoluteString, "https://wwwstationcat.org/api/music/collections/real-album/cover?v=7&size=display")
        XCTAssertNil(albumCard.artwork, "An album card must not use a song cover as the album cover")
        let cover = PlatformAlbumArtwork.coverURL(album: album, locale: "ja", host: "wwwstationcat.org", mock: false)
        XCTAssertEqual(cover?.absoluteString, "https://wwwstationcat.org/api/music/collections/real-album/cover?v=7&size=display")
        XCTAssertEqual(cover, albumCard.albumArtworkURL, "Catalog and share preview must use the same album image")
        XCTAssertNil(PlatformAlbumArtwork.coverURL(album: album, locale: "ja", host: "other.example", mock: false))
        XCTAssertNil(PlatformAlbumArtwork.coverURL(album: album, locale: "ja", host: "wwwstationcat.org", mock: true))

        // A new album revision changes the requested URL, so a long-lived
        // artwork view will not keep displaying the previous cover.
        var updatedSong = song
        updatedSong.release?.albums = [.init(id: first.id, slug: first.slug, title: first.title,
                                            summary: first.summary, version: 8, position: first.position)]
        let updatedAlbum = try XCTUnwrap(PlatformAlbum.catalog([updatedSong]).first)
        XCTAssertEqual(PlatformAlbumArtwork.coverURL(album: updatedAlbum, locale: "ja", host: "wwwstationcat.org", mock: false)?.query,
                       "v=8&size=display")
        XCTAssertNotEqual(cover, PlatformAlbumArtwork.coverURL(album: updatedAlbum, locale: "ja", host: "wwwstationcat.org", mock: false))

        var invalid = song
        invalid.release = PlatformTrackRelease(slug: "../bad", summary: "", webURL: PlatformMusicAPI.productionOrigin,
            platforms: [], availability: "available", previewAvailable: false, albums: [first])
        XCTAssertNil(PlatformShareCard.track(PlatformTrackDetail(track: invalid, story: "", lyricsURL: nil), locale: "en"))
        XCTAssertNil(PlatformShareCard.track(detail, locale: "untrusted"))
        let mismatch = PlatformAlbum(id: album.id, title: album.title, summary: "Wrong summary", tracks: album.tracks)
        XCTAssertNil(PlatformShareCard.album(mismatch, locale: "en"))
        XCTAssertNil(PlatformAlbumArtwork.coverURL(album: mismatch, locale: "en", host: "wwwstationcat.org", mock: false))
        let missing = PlatformAlbum(id: "missing", title: album.title, summary: album.summary, tracks: album.tracks)
        XCTAssertNil(PlatformShareCard.album(missing, locale: "en"))
        XCTAssertNil(PlatformAlbumArtwork.coverURL(album: missing, locale: "en", host: "wwwstationcat.org", mock: false))
    }

    func testSongShareUsesPublishedStoryWhenIntroductionIsBlank() throws {
        var song = Track(id: "11111111-1111-4111-8111-111111111111", title: "Real song", artist: "Station Cat",
                         durationSeconds: 0, audioVersion: 1, access: .unavailable)
        song.release = PlatformTrackRelease(slug: "real-song", summary: "  \n ", webURL: PlatformMusicAPI.productionOrigin,
            platforms: [], availability: "available", previewAvailable: false, albums: [])
        let story = "真实故事第一段。\n\n真实故事第二段。"
        let detail = PlatformTrackDetail(track: song, story: story, lyricsURL: nil)
        XCTAssertEqual(try XCTUnwrap(PlatformShareCard.track(detail, locale: "zh-Hans")).summary, story)

        // Missing text stays empty, never a generic or fabricated introduction.
        let absent = PlatformTrackDetail(track: song, story: " \n", lyricsURL: nil)
        XCTAssertEqual(try XCTUnwrap(PlatformShareCard.track(absent, locale: "zh-Hans")).summary, "")

        // An introduction takes precedence and retains its original wording.
        song.release = PlatformTrackRelease(slug: "real-song", summary: "  已发布的歌曲介绍。  ",
            webURL: PlatformMusicAPI.productionOrigin, platforms: [], availability: "available", previewAvailable: false, albums: [])
        let both = PlatformTrackDetail(track: song, story: story, lyricsURL: nil)
        XCTAssertEqual(try XCTUnwrap(PlatformShareCard.track(both, locale: "zh-Hans")).summary, "  已发布的歌曲介绍。  ")
    }
}
