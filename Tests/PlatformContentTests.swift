import XCTest
import AVFoundation
import CoreVideo
@testable import StationCatMusic

private actor ContentTransport: HTTPTransport {
    var replies: [HTTPResult]
    private(set) var requests: [URLRequest] = []
    init(_ replies: [HTTPResult]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request)
        let reply = replies[min(requests.count - 1, replies.count - 1)]
        return HTTPResult(status: reply.status, data: reply.data, headers: reply.headers, finalURL: reply.finalURL ?? request.url)
    }
}
private actor ContentProvider: PlatformMusicProviding {
    nonisolated let webOrigin = PlatformMusicAPI.productionOrigin
    let track: Track
    private var waiting: CheckedContinuation<Void, Never>?
    private(set) var started = false
    let hold: Bool
    private var attempts = 0
    init(track: Track, hold: Bool = false) { self.track = track; self.hold = hold }
    func setLocale(_ locale: String) {}
    func catalog() async throws -> Catalog { Catalog(items: [track], nextCursor: nil) }
    func featuredTracks() async throws -> [Track] { [track] }
    func platformDetail(_ track: Track, locale: String) async throws -> PlatformTrackDetail { PlatformTrackDetail(track: track, story: "Story", lyricsURL: nil) }
    func lyrics(_ detail: PlatformTrackDetail) async throws -> PlatformLyrics? {
        attempts += 1; started = true
        if hold { await withCheckedContinuation { waiting = $0 } }
        else if attempts == 1 { throw APIError.rejected(404) }
        // Deliberately ignores task cancellation to test the view-state fence.
        return try PlatformLyrics(data: Data("Late lyrics".utf8), kind: "txt")
    }
    func release() { waiting?.resume(); waiting = nil }
    func clips(_ track: Track, locale: String) async throws -> [PlatformClip] { [] }
}
private actor ClipTransport: MediaHTTPTransport {
    private(set) var requests: [URLRequest] = []
    var invalid = false
    init(invalid: Bool = false) { self.invalid = invalid }
    func send(_ request: URLRequest) async throws -> MediaHTTPResult {
        requests.append(request)
        var headers = ["content-type": "video/mp4", "etag": "\"clip-v1\"", "content-length": "16"]
        if request.httpMethod == "HEAD" { return MediaHTTPResult(status: 200, data: Data(), headers: headers) }
        headers["content-range"] = "bytes 0-15/16"
        if invalid { headers["etag"] = "\"changed\"" }
        return MediaHTTPResult(status: 206, data: Data(repeating: 1, count: 16), headers: headers)
    }
}

private actor MovieTransport: MediaHTTPTransport {
    let data: Data
    private(set) var requests: [URLRequest] = []
    init(data: Data) { self.data = data }
    func send(_ request: URLRequest) async throws -> MediaHTTPResult {
        requests.append(request)
        let headers = ["content-type": "video/mp4", "etag": "\"synthetic-clip\"", "content-length": String(data.count)]
        if request.httpMethod == "HEAD" { return MediaHTTPResult(status: 200, data: Data(), headers: headers) }
        let range = try XCTUnwrap(request.value(forHTTPHeaderField: "Range")).replacingOccurrences(of: "bytes=", with: "").split(separator: "-")
        let start = try XCTUnwrap(Int(range[0])), end = try XCTUnwrap(Int(range[1]))
        guard start >= 0, end < data.count, end >= start else { throw APIError.invalidRequest }
        var result = headers
        result["content-length"] = String(end - start + 1)
        result["content-range"] = "bytes \(start)-\(end)/\(data.count)"
        return MediaHTTPResult(status: 206, data: data.subdata(in: start..<(end + 1)), headers: result)
    }
}
private actor MovieProvider: PlatformMusicProviding {
    nonisolated let webOrigin = PlatformMusicAPI.productionOrigin
    let item: PlatformClip
    let hold: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var started = false
    init(_ item: PlatformClip, hold: Bool = false) { self.item = item; self.hold = hold }
    func setLocale(_ locale: String) {}
    func catalog() async throws -> Catalog { Catalog(items: [], nextCursor: nil) }
    func featuredTracks() async throws -> [Track] { [] }
    func platformDetail(_ track: Track, locale: String) async throws -> PlatformTrackDetail { throw APIError.unavailable }
    func clips(_ track: Track, locale: String) async throws -> [PlatformClip] {
        started = true
        if hold { await withCheckedContinuation { continuation = $0 } }
        return [item] // Ignores cancellation deliberately; the player must fence it.
    }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor final class PlatformContentTests: XCTestCase {
    private let asset = URL(string: "https://wwwstationcat.org/api/station/content/assets/cccccccc-cccc-4ccc-8ccc-cccccccccccc")!
    private func fixture() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: XCTUnwrap(Bundle.main.url(forResource: "platform-song-content", withExtension: "json")))) as? [String: Any])
    }
    private func detail() async throws -> PlatformTrackDetail {
        let bytes = try JSONSerialization.data(withJSONObject: fixture())
        let api = try PlatformMusicAPI(explicitlyEnabled: true, transport: PlatformFixtureTransport(data: bytes))
        return try await api.resolvePlatformTrack(slug: "track-883d3be1-2f28-4d81-b590-c3be6d80e8cd", locale: "en")
    }
    private func response(_ object: Any, status: Int = 200) throws -> HTTPResult {
        HTTPResult(status: status, data: try JSONSerialization.data(withJSONObject: object), headers: ["content-type":"application/json"])
    }
    private func clip(_ track: Track) -> [String: Any] {
        ["id":"dddddddd-dddd-4ddd-8ddd-dddddddddddd", "trackId":track.id, "revision":1, "type":"short_video", "originalLocale":"en",
         "title":"Clip", "summary":"", "durationMs":12000, "publishedAt":"2026-01-01T00:00:00Z",
         "posterUrl":"/api/station/content/assets/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
         "mediaUrl":asset.path, "track":["id":track.id, "title":track.title,"href":"/en/music/tracks/" + track.release!.slug + "/"]]
    }
    private func page(_ clips: [[String: Any]], cursor: String? = nil) -> [String: Any] {
        ["schemaVersion":1, "locale":"en", "items":clips, "nextCursor":cursor as Any? ?? NSNull()]
    }
    private func wait(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<100 { if condition() { return }; try await Task.sleep(for: .milliseconds(10)) }
        XCTFail("State did not settle")
    }
    func testPlainLyricsKeepParagraphsAndLRCRendersWithoutPlaybackTimestamps() throws {
        let plain = try PlatformLyrics(data: Data("\u{FEFF}First\r\nSecond\r\n\r\n[chorus]\nThird".utf8), kind: "txt")
        XCTAssertEqual(plain.stanzas, ["First\nSecond", "[chorus]\nThird"])
        let lrc = try PlatformLyrics(data: Data("[ar:Artist]\n[ti:Title]\n[00:01.00][01:01.00]First\n[00:02.00]<00:02.00>Second\n\n[00:03.00]Third".utf8), kind: "lrc")
        XCTAssertEqual(lrc.stanzas, ["First\nSecond", "Third"])
        XCTAssertTrue(try PlatformLyrics(data: Data("\n \n".utf8), kind: nil).stanzas.isEmpty)
    }
    func testInvalidUTF8ControlCharactersAndOversizedLyricsFail() {
        for data in [Data([0xff, 0xfe]), Data([65, 0, 66]), Data(repeating: 65, count: 262_145), Data(String(repeating: "a", count: 2001).utf8)] {
            XCTAssertThrowsError(try PlatformLyrics(data: data, kind: "txt"))
        }
    }
    func testLyricsUsesOnlyControlledPublicAssetWithoutCookiesOrCredentials() async throws {
        let value = try await detail()
        let network = ContentTransport([HTTPResult(status: 200, data: Data("One\nTwo".utf8), headers: ["content-type":"text/plain; charset=utf-8"])])
        let api = try PlatformMusicAPI(explicitlyEnabled: true, transport: network)
        let lyrics = try await api.lyrics(value)
        XCTAssertEqual(lyrics?.stanzas, ["One\nTwo"])
        let requests = await network.requests
        XCTAssertEqual(requests.count, 1); XCTAssertEqual(requests[0].url, asset)
        XCTAssertEqual(requests[0].httpMethod, "GET"); XCTAssertFalse(requests[0].httpShouldHandleCookies)
        XCTAssertEqual(requests[0].cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization")); XCTAssertNil(requests[0].value(forHTTPHeaderField: "Cookie"))
    }
    func testLyricsRejectsWrongMimeRedirectAndMissingResource() async throws {
        let value = try await detail()
        for result in [HTTPResult(status: 200, data: Data("<html>".utf8), headers: ["content-type":"text/html"]),
            HTTPResult(status: 200, data: Data("Lyrics".utf8), headers: ["content-type":"text/plain"], finalURL: URL(string:"https://example.com/lyrics")!),
            HTTPResult(status: 404, data: Data(), headers: [:])] {
            let api = try PlatformMusicAPI(explicitlyEnabled: true, transport: ContentTransport([result]))
            do { _ = try await api.lyrics(value); XCTFail("Invalid lyrics accepted") } catch {}
        }
        XCTAssertFalse(PlatformContentURL.valid(URL(string:"https://wwwstationcat.org/api/station/content/assets/%63ccccccc-cccc-4ccc-8ccc-cccccccccccc")!))
        XCTAssertFalse(PlatformContentURL.valid(URL(string:asset.absoluteString + "?token=secret")!))
    }
    func testClipProjectionChecksParentIdentityAndNeverReturnsMoreThanThree() async throws {
        let value = try await detail(), item = clip(value.track)
        let network = ContentTransport([try response(page([item]))])
        let api = try PlatformMusicAPI(explicitlyEnabled: true, transport: network)
        let clips = try await api.clips(value.track, locale: "en")
        XCTAssertEqual(clips.count, 1); XCTAssertEqual(clips[0].mediaURL, asset)
        let requests = await network.requests
        XCTAssertTrue(requests[0].url!.path.hasSuffix("/clips")); XCTAssertFalse(requests[0].url!.path.contains("playback"))
        for (key, invalid) in [("trackId", "11111111-1111-4111-8111-111111111111"), ("mediaUrl", "https://example.com/a.mp4"), ("posterUrl", "/api/station/content/assets/../../audio"), ("type", "audio")] {
            var bad = item; bad[key] = invalid
            let api = try PlatformMusicAPI(explicitlyEnabled: true, transport: ContentTransport([try response(page([bad]))]))
            do { _ = try await api.clips(value.track, locale: "en"); XCTFail("Invalid clip accepted") } catch {}
        }
        let duplicate = try PlatformMusicAPI(explicitlyEnabled: true, transport: ContentTransport([try response(page([item, item]))]))
        do { _ = try await duplicate.clips(value.track, locale: "en"); XCTFail("Duplicate accepted") } catch {}
        var three = [item, item, item]
        for i in 0..<3 { three[i]["id"] = UUID().uuidString }
        let bounded = ContentTransport([try response(page(three, cursor: "next"))])
        let client = try PlatformMusicAPI(explicitlyEnabled: true, transport: bounded)
        let result = try await client.clips(value.track, locale: "en")
        XCTAssertEqual(result.count, 3)
        let count = await bounded.requests.count; XCTAssertEqual(count, 1)
    }
    func testFilteredClipPagesAdvanceButRepeatedCursorFails() async throws {
        let value = try await detail()
        let transport = ContentTransport([try response(page([], cursor: "next")), try response(page([clip(value.track)]))])
        let api = try PlatformMusicAPI(explicitlyEnabled: true, transport: transport)
        let result = try await api.clips(value.track, locale: "en"); XCTAssertEqual(result.count, 1)
        let bad = try PlatformMusicAPI(explicitlyEnabled: true, transport: ContentTransport([try response(page([], cursor: "same"))]))
        do { _ = try await bad.clips(value.track, locale: "en"); XCTFail("Loop accepted") } catch {}
    }
    func testSectionFailuresAreIndependentAndRetryDoesNotReloadOtherContent() async throws {
        let value = try await detail(), provider = ContentProvider(track: value.track), state = PlatformContentModel()
        state.configure(value, locale: "en", provider: provider)
        try await wait { state.lyricsPhase == .failed && state.clipsPhase == .empty }
        XCTAssertEqual(state.lyricsFailureKey, "contentWithdrawn")
        state.retryLyrics()
        try await wait { state.lyricsPhase == .loaded }
        XCTAssertEqual(state.clipsPhase, .empty); XCTAssertEqual(state.lyrics?.stanzas, ["Late lyrics"])
        state.clear(); XCTAssertNil(state.lyrics)
    }
    func testLateLyricsCannotCrossSongLanguageOrDismissalBoundary() async throws {
        let value = try await detail(), provider = ContentProvider(track: value.track, hold: true), state = PlatformContentModel()
        state.configure(value, locale: "en", provider: provider)
        for _ in 0..<100 { if await provider.started { break }; try await Task.sleep(for: .milliseconds(10)) }
        state.configure(PlatformTrackDetail(track: value.track, story: "", lyricsURL: nil), locale: "ja", provider: provider)
        await provider.release(); try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(state.lyricsPhase, .empty); XCTAssertNil(state.lyrics)
        state.clear(); XCTAssertEqual(state.clipsPhase, .empty)
    }
    func testVideoChannelIsBoundedAndRejectsChangedResource() async throws {
        let transport = ClipTransport(), channel = try PlatformClipChannel(url: asset, transport: transport)
        let data = try await channel.read(start: 0, length: 100)
        XCTAssertEqual(data.count, 16)
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.httpMethod), ["HEAD", "GET"])
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Range"), "bytes=0-15")
        for request in requests { XCTAssertFalse(request.httpShouldHandleCookies); XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(request.value(forHTTPHeaderField: "Cookie")) }
        let bad = try PlatformClipChannel(url: asset, transport: ClipTransport(invalid: true))
        do { _ = try await bad.read(start: 0, length: 100); XCTFail("Changed object accepted") } catch {}
        do { _ = try await channel.read(start: 0, length: NativeMediaLimits.rangeBytes + 1); XCTFail("Unbounded range accepted") } catch {}
    }
    func testNoVideoIsCreatedWithoutAnExplicitValidatedClipAndStopClearsState() async throws {
        let value = try await detail(), player = PlatformClipPlayer()
        XCTAssertNil(player.player); XCTAssertNil(player.selectedID); XCTAssertTrue(player.muted)
        let clip = PlatformClip(id: UUID().uuidString, trackID: value.track.id, revision: 1, title: "Unknown", summary: "", duration: 10, posterURL: asset, mediaURL: asset)
        player.play(clip, track: value.track, locale: "en", provider: ContentProvider(track: value.track))
        try await wait { player.failed }
        XCTAssertNil(player.player)
        player.stop(); XCTAssertFalse(player.failed); XCTAssertNil(player.selectedID)
    }

    func testCancelledClipRevalidationCannotStartOrRequestMedia() async throws {
        let value = try await detail()
        let clip = PlatformClip(id: UUID().uuidString, trackID: value.track.id, revision: 1, title: "Synthetic", summary: "", duration: 2, posterURL: asset, mediaURL: asset)
        let provider = MovieProvider(clip, hold: true), transport = MovieTransport(data: Data())
        let player = PlatformClipPlayer(transport: transport)
        player.play(clip, track: value.track, locale: "en", provider: provider)
        for _ in 0..<100 { if await provider.started { break }; try await Task.sleep(for: .milliseconds(10)) }
        player.stop(); await provider.release()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(player.player); XCTAssertNil(player.selectedID); XCTAssertFalse(player.loading)
        let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
    }

    func testRealAVPlayerReadsSyntheticVideoMutedAndStopReleasesItem() async throws {
        // A test-only, silent 64px movie generated on the simulator. It is never
        // bundled into the product, published, or presented as an actual MV.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: file) }
        let writer = try AVAssetWriter(outputURL: file, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
        writer.add(input); XCTAssertTrue(writer.startWriting()); writer.startSession(atSourceTime: .zero)
        var optional: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB, nil, &optional), kCVReturnSuccess)
        let buffer = try XCTUnwrap(optional)
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 0x40, CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        for frame in 0..<20 {
            for _ in 0..<100 { if input.isReadyForMoreMediaData { break }; try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 10)))
        }
        input.markAsFinished(); await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        let value = try await detail(), transport = MovieTransport(data: try Data(contentsOf: file))
        let clip = PlatformClip(id: UUID().uuidString, trackID: value.track.id, revision: 1, title: "Synthetic", summary: "", duration: 2, posterURL: asset, mediaURL: asset)
        let player = PlatformClipPlayer(transport: transport)
        player.play(clip, track: value.track, locale: "en", provider: MovieProvider(clip))
        for _ in 0..<500 {
            if (player.player?.currentTime().seconds ?? 0) > 0.2 || player.failed { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(player.failed); XCTAssertGreaterThan(player.player?.currentTime().seconds ?? 0, 0.2)
        XCTAssertTrue(player.muted); XCTAssertEqual(player.player?.isMuted, true)
        let avPlayer = try XCTUnwrap(player.player)
        player.stop(); XCTAssertNil(player.player); XCTAssertNil(avPlayer.currentItem); XCTAssertEqual(avPlayer.rate, 0)
        let requests = await transport.requests
        XCTAssertTrue(requests.contains { $0.httpMethod == "GET" })
        for request in requests {
            XCTAssertEqual(request.url, asset)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        }
    }
}
