import XCTest
import WebKit
@testable import StationCatMusic

private actor YouTubeProvider: PlatformMusicProviding {
    nonisolated let webOrigin = PlatformMusicAPI.productionOrigin
    let items: [PlatformClip]
    let hold: Bool
    private(set) var started = false
    private var continuation: CheckedContinuation<Void, Never>?
    init(_ items: [PlatformClip], hold: Bool = false) { self.items = items; self.hold = hold }
    func setLocale(_ locale: String) {}
    func catalog() async throws -> Catalog { Catalog(items: [], nextCursor: nil) }
    func featuredTracks() async throws -> [Track] { [] }
    func platformDetail(_ track: Track, locale: String) async throws -> PlatformTrackDetail { throw APIError.unavailable }
    func clips(_ track: Track, locale: String) async throws -> [PlatformClip] {
        started = true
        if hold { await withCheckedContinuation { continuation = $0 } }
        return items // Deliberately ignores cancellation.
    }
    func release() { continuation?.resume(); continuation = nil }
}
private actor YouTubeTransport: HTTPTransport {
    let bytes: Data
    private(set) var requests: [URLRequest] = []
    init(_ bytes: Data) { self.bytes = bytes }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request)
        return HTTPResult(status: 200, data: bytes, headers: ["content-type":"application/json"], finalURL: request.url)
    }
}

@MainActor final class YouTubeClipTests: XCTestCase {
    private func object() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: XCTUnwrap(Bundle.main.url(forResource: "platform-youtube-clips", withExtension: "json")))) as? [String: Any])
    }
    private func fixture() async throws -> (Track, PlatformClip) {
        let bytes = try JSONSerialization.data(withJSONObject: object())
        let api = try PlatformMusicAPI(explicitlyEnabled: true, transport: PlatformFixtureTransport(data: bytes))
        let track = try await api.resolvePlatformTrack(slug: "track-883d3be1-2f28-4d81-b590-c3be6d80e8cd", locale: "en").track
        let clips = try await api.clips(track, locale: "en")
        return (track, try XCTUnwrap(clips.first))
    }
    private func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<200 { if predicate() { return }; try await Task.sleep(for: .milliseconds(25)) }
        XCTFail("State did not settle")
    }
    private func document(_ clip: YouTubeClip, _ token: String) -> String {
        "<html><body>Local fixture<script>window.webkit.messageHandlers.youtube.postMessage({token:'\(token)',event:'ready'});</script></body></html>"
    }
    func testIDAndDocumentCannotAcceptURLsOrScriptAndNeverAutoplay() throws {
        for value in ["", "short", "abcdefghijk?x=1", "abcdefghij'", "https://youtu.be/abcdefghijk", "abcdefghijk\n"] { XCTAssertNil(YouTubeClip(videoID: value)) }
        let clip = try XCTUnwrap(YouTubeClip(videoID: "ab_CDe-1234")), token = UUID().uuidString
        let html = YouTubeEmbedDocument.html(clip, token: token)
        XCTAssertTrue(html.contains("youtube-nocookie.com")); XCTAssertTrue(html.contains("autoplay:0"))
        XCTAssertTrue(html.contains("controls:1")); XCTAssertTrue(html.contains("playsinline:1"))
        XCTAssertTrue(html.contains("origin:'https://org.stationcat.music'"))
        XCTAssertFalse(html.contains("playVideo()")); XCTAssertFalse(html.contains("loadVideoById"))
        XCTAssertEqual(YouTubeEmbedDocument.html(clip, token: "<script>"), "")
    }
    func testProjectionOptsInAndRejectsMixedSourcesMismatchOrUnknownProvider() async throws {
        let (track, clip) = try await fixture()
        XCTAssertEqual(clip.youtube?.videoID, "abcdefghijk"); XCTAssertNil(clip.mediaURL); XCTAssertNil(clip.posterURL)
        let object = try object(), pages = try XCTUnwrap(object["clips"] as? [String: [String: Any]])
        var page = try XCTUnwrap(pages.values.first); page["locale"] = "en"
        var item = try XCTUnwrap((page["items"] as? [[String: Any]])?.first)
        item["track"] = ["id":track.id,"title":track.title,"href":"/en/music/tracks/" + track.release!.slug + "/"]
        page["items"] = [item]
        let transport = YouTubeTransport(try JSONSerialization.data(withJSONObject: page)), api = try PlatformMusicAPI(explicitlyEnabled: true, transport: transport)
        let clips = try await api.clips(track, locale: "en")
        XCTAssertEqual(clips.count, 1)
        let requests = await transport.requests
        XCTAssertEqual(URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "include" })?.value, "youtube")
        for patch in [["youtubeVideoId":"bad"], ["watchUrl":"https://evil.test/watch?v=abcdefghijk"], ["mediaUrl":"/api/station/content/assets/cccccccc-cccc-4ccc-8ccc-cccccccccccc"], ["provider":"unknown"]] {
            page["items"] = [item.merging(patch) { _, new in new }]
            let other = try PlatformMusicAPI(explicitlyEnabled: true, transport: YouTubeTransport(try JSONSerialization.data(withJSONObject: page)))
            do { _ = try await other.clips(track, locale: "en"); XCTFail("Invalid source accepted") } catch {}
        }
    }
    func testRevokedClipNeverCreatesWebViewOrOpensExternalURL() async throws {
        let (track, clip) = try await fixture(), provider = YouTubeProvider([])
        var opens = 0
        let session = YouTubeClipSession(document: document)
        session.start(clip, track: track, locale: "en", provider: provider) { _ in opens += 1 }
        try await wait { session.phase == .failed }
        XCTAssertNil(session.webView); XCTAssertEqual(session.failureKey, "youtubeUnavailable")
        session.start(clip, track: track, locale: "en", provider: provider, externalOnly: true) { _ in opens += 1 }
        try await wait { session.phase == .failed }; XCTAssertEqual(opens, 0)
    }
    func testStoppedLateVerificationCannotCreateWebView() async throws {
        let (track, clip) = try await fixture(), provider = YouTubeProvider([clip], hold: true)
        let session = YouTubeClipSession(document: document)
        session.start(clip, track: track, locale: "en", provider: provider) { _ in XCTFail("Unexpected handoff") }
        for _ in 0..<100 { if await provider.started { break }; try await Task.sleep(for: .milliseconds(10)) }
        session.stop(); await provider.release(); try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(session.phase, .idle); XCTAssertNil(session.webView); XCTAssertNil(session.selectedID)
    }
    func testLocalWebViewReadinessEphemeralStorageAndTeardown() async throws {
        let (track, clip) = try await fixture(), provider = YouTubeProvider([clip])
        let session = YouTubeClipSession(document: document)
        XCTAssertNil(session.webView)
        session.start(clip, track: track, locale: "en", provider: provider) { _ in XCTFail("Unexpected handoff") }
        try await wait { session.phase == .ready }
        let view = try XCTUnwrap(session.webView)
        XCTAssertFalse(view.configuration.websiteDataStore.isPersistent)
        XCTAssertFalse(view.configuration.allowsAirPlayForMediaPlayback)
        XCTAssertFalse(view.configuration.allowsPictureInPictureMediaPlayback)
        XCTAssertEqual(view.configuration.mediaTypesRequiringUserActionForPlayback, .all)
        session.stop(); XCTAssertNil(session.webView); XCTAssertNil(view.navigationDelegate); XCTAssertEqual(session.phase, .idle)
        try await Task.sleep(for: .milliseconds(100)); XCTAssertEqual(session.phase, .idle)
    }
    func testExternalFallbackRevalidatesAndDoesNotCreateAnEmbed() async throws {
        let (track, clip) = try await fixture(), provider = YouTubeProvider([clip])
        var opened: URL?
        let session = YouTubeClipSession(document: document)
        session.start(clip, track: track, locale: "en", provider: provider, externalOnly: true) { opened = $0 }
        try await wait { opened != nil }
        XCTAssertEqual(opened, clip.youtube?.watchURL); XCTAssertNil(session.webView); XCTAssertEqual(session.phase, .idle)
    }
}
