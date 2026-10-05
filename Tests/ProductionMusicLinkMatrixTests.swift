import XCTest
@testable import StationCatMusic

private struct SharedMusicLinkMatrix: Decodable {
    struct Expected: Decodable { let kind: String?; let value: String? }
    struct Case: Decodable { let id: String; let environment: String; let url: String; let client: Expected; let aasaExpected: Bool }
    let schemaVersion: Int; let origins: [String: String]; let musicPaths: [String: [String]]; let cases: [Case]
}
private actor LinkMatrixTransport: HTTPTransport {
    private(set) var paths: [String] = []
    private let origin: URL
    static let track = Track(id: "4a6f6310-6cde-4be7-a2f9-94bb80b34ad0", title: "Shared URL fixture", artist: "Synthetic", durationSeconds: 180, audioVersion: 1, access: .free)
    init(origin: URL) { self.origin = origin }
    private func envelope<T: Codable & Sendable>(_ value: T) throws -> HTTPResult {
        HTTPResult(status: 200, data: try JSONEncoder().encode(APIEnvelope(data: value, requestId: "local-link-matrix", serverNow: ISO8601DateFormatter().string(from: Date()))))
    }
    func send(_ request: URLRequest) throws -> HTTPResult {
        guard request.url?.scheme == "https", request.url?.host == origin.host, request.httpMethod == "GET",
              let path = request.url?.path else { throw APIError.invalidRequest }
        paths.append(path)
        switch path {
        case "/api/mobile/v1/music/catalog": return try envelope(Catalog(items: [Self.track], nextCursor: nil))
        case "/api/mobile/v1/music/featured": return try envelope(FeaturedMusic(tracks: [Self.track], collections: []))
        case "/api/mobile/v1/music/tracks/" + Self.track.id:
            return try envelope(TrackDetail(track: Self.track, summary: "Local parser test", coverUrl: nil,
                lyrics: MusicLyrics(kind: "plain", text: "Synthetic", lines: [], audioVersion: 1), genres: [], moods: [],
                previewAvailable: false, previewSourceStartSeconds: nil, previewDurationSeconds: nil))
        case "/api/mobile/v1/music/collections/test-album":
            return try envelope(MusicCollection(id: "20000000-0000-4000-8000-000000000001", slug: "test-album", title: "Synthetic",
                description: "Local parser test", version: 1, tracks: [Self.track], nextCursor: nil))
        default: throw APIError.invalidRequest
        }
    }
}
private actor LinkMatrixMediaTransport: MediaHTTPTransport {
    private(set) var requests = 0
    func send(_ request: URLRequest) throws -> MediaHTTPResult { requests += 1; throw APIError.networkDisabled }
}

@MainActor final class ProductionMusicLinkMatrixTests: XCTestCase {
    private func matrix() throws -> SharedMusicLinkMatrix {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "canonical-link-cases", withExtension: "json"))
        let fixture = try JSONDecoder().decode(SharedMusicLinkMatrix.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixture.schemaVersion, 1)
        XCTAssertEqual(fixture.origins["production"], ProductionActivationProfile.origin)
        XCTAssertEqual(fixture.musicPaths["production"]?.count, 10)
        XCTAssertEqual(fixture.musicPaths["r2"]?.count, 2)
        XCTAssertEqual(fixture.cases.count, 74)
        XCTAssertEqual(Set(fixture.cases.map(\.id)).count, fixture.cases.count)
        return fixture
    }
    func testSharedWebsiteAASAMatrixMatchesNativeParser() throws {
        let fixture = try matrix()
        for entry in fixture.cases {
            let origin = try XCTUnwrap(URL(string: try XCTUnwrap(fixture.origins[entry.environment])))
            let url = try XCTUnwrap(URL(string: entry.url)), host = try XCTUnwrap(origin.host)
            let expected: MusicLink?
            switch entry.client.kind {
            case "track": expected = .track(try XCTUnwrap(entry.client.value))
            case "collection": expected = .collection(try XCTUnwrap(entry.client.value))
            default: expected = nil
            }
            XCTAssertEqual(MusicLink(url, allowedHost: host), expected, entry.id)
            if expected != nil { XCTAssertTrue(entry.aasaExpected, entry.id) }
        }
    }
    func testSharedMatrixColdInitializationResolvesWithoutStartingAudio() async throws { try await exercise(cold: true) }
    func testSharedMatrixWarmInitializationResolvesWithoutStartingAudio() async throws { try await exercise(cold: false) }
    private func exercise(cold: Bool) async throws {
        let fixture = try matrix()
        for entry in fixture.cases {
            let origin = try XCTUnwrap(URL(string: try XCTUnwrap(fixture.origins[entry.environment])))
            let configuration = entry.environment == "production" ? try ProductionLocalFixture.configuration() :
                try NativeAuthConfiguration(environment: .staging, origin: origin, explicitlyEnabled: true)
            let transport = LinkMatrixTransport(origin: origin), media = LinkMatrixMediaTransport()
            let native = try NativeMusicAPI(configuration: configuration, explicitlyEnabled: true, transport: transport)
            let directory = FileManager.default.temporaryDirectory.appending(path: "local-link-matrix-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let model = AppModel(client: native, playback: PlaybackService(transport: media),
                account: NativeAccountModel(environment: configuration.environment), musicWebOrigin: origin,
                environment: configuration.environment, offlineStorage: OfflineMusicCache(origin: origin, baseDirectory: directory, transport: media))
            defer { model.playback.shutdown() }
            let url = try XCTUnwrap(URL(string: entry.url))
            if cold {
                await model.receiveMusicLink(url)
                let before = await transport.paths
                XCTAssertTrue(before.isEmpty, entry.id)
                XCTAssertNil(model.playback.selectedTrack, entry.id)
                XCTAssertNil(model.activeCollection, entry.id)
                await model.initialize()
            } else {
                await model.initialize()
                await model.receiveMusicLink(url)
            }
            XCTAssertEqual(model.startupPhase, .ready, entry.id)
            XCTAssertFalse(model.linkUnavailable, entry.id)
            switch entry.client.kind {
            case "track":
                XCTAssertEqual(model.playback.selectedTrack?.id, entry.client.value, entry.id)
                XCTAssertTrue(model.showPlayer, entry.id)
                XCTAssertNil(model.activeCollection, entry.id)
            case "collection":
                XCTAssertEqual(model.activeCollection?.slug, entry.client.value, entry.id)
                XCTAssertNil(model.playback.selectedTrack, entry.id)
                XCTAssertEqual(model.selectedTab, 1, entry.id)
            default:
                XCTAssertNil(model.playback.selectedTrack, entry.id)
                XCTAssertNil(model.activeCollection, entry.id)
                XCTAssertFalse(model.showPlayer, entry.id)
            }
            let paths = await transport.paths, mediaRequests = await media.requests
            XCTAssertEqual(paths.contains { $0.contains("/music/tracks/") }, entry.client.kind == "track", entry.id)
            XCTAssertEqual(paths.contains { $0.contains("/music/collections/") }, entry.client.kind == "collection", entry.id)
            XCTAssertFalse(paths.contains { $0.contains("playback-grants") || $0.contains("/music/media/") }, entry.id)
            XCTAssertEqual(mediaRequests, 0, entry.id)
            XCTAssertFalse(model.playback.isPlaying, entry.id)
            XCTAssertFalse(model.playback.hasAudioSource, entry.id)
            XCTAssertEqual(model.playback.position, 0, entry.id)
        }
        print("PRODUCTION_LINK_MATRIX_\(cold ? "COLD" : "WARM")_PASSED: cases=\(fixture.cases.count) audio_requests=0 os_association=false")
    }
}
