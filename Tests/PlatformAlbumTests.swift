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
}
