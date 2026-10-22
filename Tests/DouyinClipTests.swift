import XCTest
import WebKit
@testable import StationCatMusic

private actor DouyinProvider: PlatformMusicProviding {
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
private actor DouyinTransport: HTTPTransport {
    let bytes: Data
    private(set) var requests: [URLRequest] = []
    init(_ bytes: Data) { self.bytes = bytes }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request)
        return HTTPResult(status: 200, data: bytes, headers: ["content-type":"application/json"], finalURL: request.url)
    }
}
private actor DouyinVerificationGate {
    private(set) var started = false
    private var continuation: CheckedContinuation<Void, Never>?
    func verify() async {
        started = true
        await withCheckedContinuation { continuation = $0 } // Ignore cancellation deliberately.
    }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor final class DouyinClipTests: XCTestCase {
    private func object() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: XCTUnwrap(Bundle.main.url(forResource: "platform-douyin-clips", withExtension: "json")))) as? [String: Any])
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
    private func document(_ clip: DouyinClip, _ token: String) -> String {
        "<html><body>Local fixture<script>window.webkit.messageHandlers.douyin.postMessage({token:'\(token)',event:'loaded'});</script></body></html>"
    }
    func testIDAndDocumentCannotAcceptURLsOrScriptAndNeverAutoplay() throws {
        for value in ["0000000000000000001", "７０００００００００００００００００１", "7000000000000000001\n", "700000000000000000100", "", "short", "7000000000000000001?x=1", "abcdefghij'", "https://youtu.be/7000000000000000001", "7000000000000000001\n"] { XCTAssertNil(DouyinClip(videoID: value)) }
        let clip = try XCTUnwrap(DouyinClip(videoID: "7000000000000000002")), token = UUID().uuidString
        let html = DouyinEmbedDocument.html(clip, token: token)
        XCTAssertTrue(html.contains("open.douyin.com")); XCTAssertTrue(html.contains("autoplay=0"))
        XCTAssertTrue(html.contains("allowfullscreen")); XCTAssertTrue(html.contains("strict-origin"))
        XCTAssertTrue(html.contains("frame-src https://open.douyin.com"))
        XCTAssertFalse(html.contains("playVideo()")); XCTAssertFalse(html.contains("loadVideoById"))
        XCTAssertEqual(DouyinEmbedDocument.html(clip, token: "<script>"), "")
    }
    func testWrapperRootCanonicalizationDoesNotAllowOtherPages() throws {
        for value in ["about:blank", "https://org.stationcat.music", "https://org.stationcat.music/"] {
            XCTAssertTrue(DouyinEmbedDocument.isWrapperNavigation(try XCTUnwrap(URL(string:value))),value)
        }
        for value in ["http://org.stationcat.music/", "https://org.stationcat.music:443/", "https://other.invalid/", "https://org.stationcat.music/?x=1", "https://org.stationcat.music/#x", "https://org.stationcat.music/login", "https://org.stationcat.music/%2f", "https://user@org.stationcat.music/", "about:blank#x"] {
            XCTAssertFalse(DouyinEmbedDocument.isWrapperNavigation(try XCTUnwrap(URL(string:value))),value)
        }
    }
    func testProjectionOptsInAndRejectsMixedSourcesMismatchOrUnknownProvider() async throws {
        let (track, clip) = try await fixture()
        XCTAssertEqual(clip.douyin?.videoID, "7000000000000000001"); XCTAssertNil(clip.mediaURL); XCTAssertNil(clip.posterURL)
        let object = try object(), pages = try XCTUnwrap(object["clips"] as? [String: [String: Any]])
        var page = try XCTUnwrap(pages.values.first); page["locale"] = "en"
        var item = try XCTUnwrap((page["items"] as? [[String: Any]])?.first)
        item["track"] = ["id":track.id,"title":track.title,"href":"/en/music/tracks/" + track.release!.slug + "/"]
        page["items"] = [item]
        let transport = DouyinTransport(try JSONSerialization.data(withJSONObject: page)), api = try PlatformMusicAPI(explicitlyEnabled: true, transport: transport)
        let clips = try await api.clips(track, locale: "en")
        XCTAssertEqual(clips.count, 1)
        let requests = await transport.requests
        XCTAssertEqual(URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "include" })?.value, "youtube,douyin")
        for patch in [["douyinVideoId":"bad"], ["watchUrl":"https://evil.test/watch?v=7000000000000000001"], ["mediaUrl":"/api/station/content/assets/cccccccc-cccc-4ccc-8ccc-cccccccccccc"], ["provider":"unknown"], ["youtubeVideoId":"abcdefghijk"]] {
            page["items"] = [item.merging(patch) { _, new in new }]
            let other = try PlatformMusicAPI(explicitlyEnabled: true, transport: DouyinTransport(try JSONSerialization.data(withJSONObject: page)))
            do { _ = try await other.clips(track, locale: "en"); XCTFail("Invalid source accepted") } catch {}
        }
    }
    func testRevokedClipNeverCreatesWebViewOrOpensExternalURL() async throws {
        let (track, clip) = try await fixture(), provider = DouyinProvider([])
        var opens = 0
        let session = DouyinClipSession(document: document, verifyEmbed: { _ in })
        session.start(clip, track: track, locale: "en", provider: provider) { _ in opens += 1 }
        try await wait { session.phase == .failed }
        XCTAssertNil(session.webView); XCTAssertEqual(session.failureKey, "douyinUnavailable")
        session.start(clip, track: track, locale: "en", provider: provider, externalOnly: true) { _ in opens += 1 }
        try await wait { session.phase == .failed }; XCTAssertEqual(opens, 0)
    }
    func testStoppedLateVerificationCannotCreateWebView() async throws {
        let (track, clip) = try await fixture(), provider = DouyinProvider([clip], hold: true)
        let session = DouyinClipSession(document: document, verifyEmbed: { _ in })
        session.start(clip, track: track, locale: "en", provider: provider) { _ in XCTFail("Unexpected handoff") }
        for _ in 0..<100 { if await provider.started { break }; try await Task.sleep(for: .milliseconds(10)) }
        session.stop(); await provider.release(); try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(session.phase, .idle); XCTAssertNil(session.webView); XCTAssertNil(session.selectedID)
    }
    func testLocalWebViewReadinessEphemeralStorageAndTeardown() async throws {
        let (track, clip) = try await fixture(), provider = DouyinProvider([clip])
        let session = DouyinClipSession(document: document, verifyEmbed: { _ in })
        XCTAssertNil(session.webView)
        session.start(clip, track: track, locale: "en", provider: provider) { _ in XCTFail("Unexpected handoff") }
        try await wait { session.webView != nil }
        let view = try XCTUnwrap(session.webView)
        // Match the real foreground presentation. An unattached WKWebView can
        // be suspended during a cold WebKit start and is not a player UI test.
        let window = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow))
        view.frame = CGRect(x: 0, y: 0, width: 200, height: 300)
        window.addSubview(view)
        defer { session.stop(); view.removeFromSuperview() }
        try await wait { session.phase == .loaded }
        XCTAssertEqual(session.phase, .loaded, "Local document failed: \(session.failureKey)")
        XCTAssertFalse(view.configuration.websiteDataStore.isPersistent)
        XCTAssertFalse(view.configuration.allowsAirPlayForMediaPlayback)
        XCTAssertFalse(view.configuration.allowsPictureInPictureMediaPlayback)
        XCTAssertEqual(view.configuration.mediaTypesRequiringUserActionForPlayback, .all)
        session.stop(); XCTAssertNil(session.webView); XCTAssertNil(view.navigationDelegate); XCTAssertEqual(session.phase, .idle)
        try await Task.sleep(for: .milliseconds(100)); XCTAssertEqual(session.phase, .idle)
    }
    func testStoppedLateOfficialAPIResultCannotCreateWebView() async throws {
        let (track, clip) = try await fixture(), provider = DouyinProvider([clip]), gate = DouyinVerificationGate()
        let session = DouyinClipSession(document: document, verifyEmbed: { _ in await gate.verify() })
        session.start(clip, track: track, locale: "en", provider: provider) { _ in XCTFail("Unexpected handoff") }
        for _ in 0..<100 { if await gate.started { break }; try await Task.sleep(for: .milliseconds(10)) }
        let started = await gate.started
        XCTAssertTrue(started)
        session.stop(); await gate.release(); try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(session.phase, .idle); XCTAssertNil(session.webView); XCTAssertNil(session.selectedID)
    }
    func testRevocationPreventsCallingDouyinAPI() async throws {
        let (track, clip) = try await fixture(), provider = DouyinProvider([])
        let session = DouyinClipSession(document: document, verifyEmbed: { _ in XCTFail("No third-party request before publication check") })
        session.start(clip, track: track, locale: "en", provider: provider) { _ in XCTFail("No handoff") }
        try await wait { session.phase == .failed }
        XCTAssertNil(session.webView)
    }
    func testOfficialAPIFailureLeavesFallbackAvailableAndDoesNotBuildHTML() async throws {
        let (track, clip) = try await fixture(), provider = DouyinProvider([clip])
        let session = DouyinClipSession(document: { _,_ in XCTFail("Cannot create embed"); return "" }, verifyEmbed: { _ in throw DouyinEmbedError.unavailable })
        session.start(clip, track: track, locale: "en", provider: provider) { _ in XCTFail("No automatic handoff") }
        try await wait { session.phase == .failed }
        XCTAssertEqual(session.failureKey, "douyinUnavailable"); XCTAssertNil(session.webView)
        var opened: URL?
        session.start(clip, track: track, locale: "en", provider: provider, externalOnly: true) { opened = $0 }
        try await wait { opened != nil }
        XCTAssertEqual(opened, clip.douyin?.watchURL)
    }
    func testExternalFallbackRevalidatesAndDoesNotCreateAnEmbed() async throws {
        let (track, clip) = try await fixture(), provider = DouyinProvider([clip])
        var opened: URL?
        let session = DouyinClipSession(document: document, verifyEmbed: { _ in })
        session.start(clip, track: track, locale: "en", provider: provider, externalOnly: true) { opened = $0 }
        try await wait { opened != nil }
        XCTAssertEqual(opened, clip.douyin?.watchURL); XCTAssertNil(session.webView); XCTAssertEqual(session.phase, .idle)
    }
}

private actor DouyinAPITransport: HTTPTransport {
    let object: [String: String]
    let code: Int
    let redirect: Bool
    private(set) var requests: [URLRequest] = []
    init(source: String, code: Int = 0, redirect: Bool = false) { object = ["iframe_code":source]; self.code = code; self.redirect = redirect }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request)
        return HTTPResult(status: 200, data: try JSONSerialization.data(withJSONObject: ["err_no":code, "data":object]),
                          headers: ["content-type":"application/json"], finalURL: redirect ? URL(string:"https://evil.invalid/") : request.url)
    }
}
@MainActor final class DouyinAPITests: XCTestCase {
    func testOfficialAPICodeRequiresAnIntegerAndValidEnvelope() async throws {
        let clip = try XCTUnwrap(DouyinClip(videoID:"7000000000000000001"))
        for code: Any in [false, "0", 0.5, NSNull()] {
            let bytes = try JSONSerialization.data(withJSONObject: ["err_no":code,"data":["iframe_code":"<iframe src=\"\(clip.playerURL.absoluteString)\"></iframe>"]])
            do { try await DouyinEmbedAPI(transport:DouyinTransport(bytes)).verify(clip); XCTFail("Malformed status accepted") }
            catch { XCTAssertEqual(error as? DouyinEmbedError, .invalidResponse) }
        }
    }
    func testOfficialAPIUsesExactIDNoCredentialsAndDoesNotRunReturnedHTML() async throws {
        let clip = try XCTUnwrap(DouyinClip(videoID:"7000000000000000001"))
        let transport = DouyinAPITransport(source:"<iframe src=\"\(clip.playerURL.absoluteString)\" onload=\"untrusted()\"></iframe>")
        try await DouyinEmbedAPI(transport: transport).verify(clip)
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.host,"open.douyin.com"); XCTAssertEqual(request.url?.query,"video_id="+clip.videoID)
        XCTAssertNil(request.value(forHTTPHeaderField:"Cookie")); XCTAssertNil(request.value(forHTTPHeaderField:"Authorization"))
        XCTAssertEqual(request.cachePolicy,.reloadIgnoringLocalCacheData); XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertFalse(DouyinEmbedDocument.html(clip,token:UUID().uuidString).contains("untrusted()"))
    }
    func testOfficialAPIRejectsPrivateVideoMismatchedIdentityUnexpectedHostsAndRedirect() async throws {
        let clip = try XCTUnwrap(DouyinClip(videoID:"7000000000000000001"))
        for source in ["<iframe src=\"https://evil.invalid/player\"></iframe>",
                       "<iframe src=\"https://open.douyin.com/player/video?vid=7000000000000000002&autoplay=0\"></iframe>",
                       "<iframe src=\"\(clip.playerURL.absoluteString)&autoplay=1\"></iframe>",
                       "<iframe src=\"\(clip.playerURL.absoluteString)\"></iframe><script src=\"https://evil.invalid\"></script>", ""] {
            do { try await DouyinEmbedAPI(transport: DouyinAPITransport(source: source)).verify(clip); XCTFail("Invalid response accepted") } catch {}
        }
        for transport in [DouyinAPITransport(source:"",code:28003004), DouyinAPITransport(source:"",code:28001005),
                          DouyinAPITransport(source:"<iframe src=\"\(clip.playerURL.absoluteString)\"></iframe>",redirect:true)] {
            do { try await DouyinEmbedAPI(transport:transport).verify(clip); XCTFail("Failed response accepted") } catch {}
        }
    }
}
