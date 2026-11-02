import XCTest
import WebKit
@testable import StationCatMusic

private actor NetEaseListeningProvider: PlatformMusicProviding {
    nonisolated let webOrigin = PlatformMusicAPI.productionOrigin
    private var detail: PlatformTrackDetail
    private var waiting: CheckedContinuation<Void, Never>?
    private(set) var calls = 0
    let hold: Bool
    let throwsError: Bool
    init(_ track: Track, hold: Bool = false, throwsError: Bool = false) {
        detail = PlatformTrackDetail(track: track, story: "", lyricsURL: nil)
        self.hold = hold; self.throwsError = throwsError
    }
    func setLocale(_ locale: String) {}
    func catalog() async throws -> Catalog { Catalog(items: [], nextCursor: nil) }
    func featuredTracks() async throws -> [Track] { [] }
    func platformDetail(_ track: Track, locale: String) async throws -> PlatformTrackDetail {
        calls += 1
        if hold { await withCheckedContinuation { waiting = $0 } }
        if throwsError { throw APIError.unavailable }
        return detail // Deliberately does not honor task cancellation.
    }
    func setTrack(_ track: Track) { detail = PlatformTrackDetail(track: track, story: "", lyricsURL: nil) }
    func release() { waiting?.resume(); waiting = nil }
}

@MainActor final class NetEaseListeningTests: XCTestCase {
    private let songURL = URL(string: "https://music.163.com/song?id=3446748064")!
    private func fixture(url: URL? = nil, provider: PlatformProvider = .netease) -> (Track, PlatformLink) {
        let link = PlatformLink(id: "b30dd884-84ef-432b-8ac5-7820db67aa0e", provider: provider, url: url ?? songURL)
        let release = PlatformTrackRelease(slug: "track-883d3be1-2f28-4d81-b590-c3be6d80e8cd", summary: "", webURL: URL(string: "https://wwwstationcat.org/music/tracks/track-883d3be1-2f28-4d81-b590-c3be6d80e8cd/")!, platforms: [link], availability: "live", previewAvailable: false)
        return (Track(id: "883d3be1-2f28-4d81-b590-c3be6d80e8cd", title: "Local fixture", artist: "Station Cat", durationSeconds: 0, audioVersion: 0, access: .unavailable, release: release), link)
    }
    private func request(_ pair: (Track, PlatformLink)) throws -> NetEaseListeningRequest {
        try XCTUnwrap(NetEaseListeningRequest(link: pair.1, track: pair.0))
    }
    private func withoutLinks(_ track: Track) -> Track {
        var changed = track
        if let release = track.release {
            changed.release = PlatformTrackRelease(slug: release.slug, summary: release.summary, webURL: release.webURL,
                platforms: [], availability: release.availability, previewAvailable: release.previewAvailable, albums: release.albums)
        }
        return changed
    }
    private func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<240 { if predicate() { return }; try await Task.sleep(for: .milliseconds(25)) }
        XCTFail("State did not settle")
    }
    private func waitForCall(_ provider: NetEaseListeningProvider) async throws {
        for _ in 0..<100 { if await provider.calls > 0 { return }; try await Task.sleep(for: .milliseconds(10)) }
        XCTFail("Provider not called")
    }
    private func localDocument(_ view: WKWebView, _ url: URL) {
        // No third-party subresources and no audio. This fixture proves browser
        // behavior only, never NetEase availability or real playback.
        view.loadHTMLString("<html><head><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; style-src 'unsafe-inline'; frame-src about:;\"></head><body>Local browser fixture</body></html>", baseURL: url)
    }
    private func attach(_ view: WKWebView) throws {
        let window = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow))
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 400)
        window.addSubview(view)
    }

    func testRequestRequiresPublishedSameProviderSongAndKeepsOriginalFallback() throws {
        let pair = fixture(), current = try request(pair)
        XCTAssertEqual(current.originalURL, songURL); XCTAssertEqual(current.pageURL, songURL)
        let alias = fixture(url: URL(string: "https://music.163.com/#/song?id=3446748064")!)
        let aliased = try request(alias)
        XCTAssertEqual(aliased.pageURL, songURL)
        XCTAssertEqual(aliased.originalURL, alias.1.url)
        for value in ["https://music.163.com/song?id=1&id=2", "https://music.163.com/song?id=1&autoplay=1", "https://music.163.com/song?id=0", "https://music.163.com/song?id=01", "https://music.163.com/song?id=１", "https://music.163.com/song?id=123456789012345678901", "https://music.163.com/album?id=1", "https://y.music.163.com/m/song?id=1", "https://music.163.com/song?id=1#anything", "https://user:password@music.163.com/song?id=1", "http://music.163.com/song?id=1", "https://evil.invalid/song?id=1", "https://music.163.com/song?id=1&token=secret"] {
            let other = fixture(url: try XCTUnwrap(URL(string: value)))
            XCTAssertNil(NetEaseListeningRequest(link: other.1, track: other.0), value)
        }
        let different = fixture(provider: .spotify)
        XCTAssertNil(NetEaseListeningRequest(link: different.1, track: different.0))
        let removed = withoutLinks(pair.0)
        XCTAssertNil(NetEaseListeningRequest(link: pair.1, track: removed))
    }

    func testAllDocumentFramesUseExactHTTPSHostAndNeverOpenWindows() throws {
        for value in ["https://music.163.com/song?id=3446748064", "https://music.163.com/m/song?id=3446748064", "https://music.163.com/login", "https://y.music.163.com/m/song?id=3446748064"] {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertTrue(NetEaseListeningNavigationPolicy.allows(url, target: .mainFrame))
            XCTAssertTrue(NetEaseListeningNavigationPolicy.allows(url, target: .subframe))
            XCTAssertFalse(NetEaseListeningNavigationPolicy.allows(url, target: .newWindow))
        }
        for value in ["https://outside.invalid/ad", "https://music.163.com.evil.invalid", "https://child.music.163.com/", "https://y.music.163.com.evil.invalid/", "https://child.y.music.163.com/", "https://music.163.com./", "https://y.music.163.com./", "https://%6Dusic.163.com/", "https://%79.music.163.com/", "https://user@music.163.com/", "https://user:password@y.music.163.com/", "https://music.163.com:443/", "https://y.music.163.com:443/", "http://music.163.com/", "http://y.music.163.com/", "orpheus://song/1", "javascript:alert(1)", "data:text/html,unexpected", "file:///private/file", "blob:https://music.163.com/other", "about:blank#unexpected"] {
            let url = try XCTUnwrap(URL(string: value))
            for target: NetEaseListeningNavigationPolicy.Target in [.mainFrame, .subframe, .newWindow] {
                XCTAssertFalse(NetEaseListeningNavigationPolicy.allows(url, target: target), value)
            }
        }
        let blank = URL(string: "about:blank")!
        XCTAssertTrue(NetEaseListeningNavigationPolicy.allows(blank, target: .subframe))
        XCTAssertFalse(NetEaseListeningNavigationPolicy.allows(blank, target: .mainFrame))
    }

    func testNavigationDiagnosticContainsOnlyFixedReasonAndCleanBoundedHost() throws {
        let host = URL(string: "https://outside.invalid/private/path?token=DO_NOT_DISPLAY#fragment")!
        XCTAssertEqual(NetEaseListeningNavigationPolicy.diagnostic(host, target: .mainFrame, response: false), "action/main/host · outside.invalid")
        XCTAssertEqual(NetEaseListeningNavigationPolicy.diagnostic(host, target: .subframe, response: true), "response/child/host · outside.invalid")
        XCTAssertEqual(NetEaseListeningNavigationPolicy.diagnostic(host, target: .newWindow, response: false), "action/popup/host · outside.invalid")
        XCTAssertEqual(NetEaseListeningNavigationPolicy.diagnostic(host, target: .mainFrame, response: false, download: true), "action/main/download · outside.invalid")
        for value in ["https://USER:SECRET@outside.invalid/private?token=SECRET", "https://%6Dusic.163.com/private?token=SECRET",
                      "https://" + String(repeating: "a", count: 254) + "/private?token=SECRET"] {
            let diagnostic = NetEaseListeningNavigationPolicy.diagnostic(try XCTUnwrap(URL(string: value)), target: .mainFrame, response: false)
            XCTAssertEqual(diagnostic, "action/main/host")
            XCTAssertFalse(diagnostic.contains("SECRET"))
        }
        XCTAssertEqual(NetEaseListeningNavigationPolicy.diagnostic(URL(string: "orpheus://song/1?token=SECRET"), target: .mainFrame, response: false), "action/main/scheme")
    }

    func testApprovedMobileRedirectAllowsDocumentButSpoofedResponseDoesNot() async throws {
        let pair = fixture(), current = try request(pair)
        let session = NetEaseListeningSession(loadDocument: { _, _ in })
        session.start(current, track: pair.0, locale: "en", provider: NetEaseListeningProvider(pair.0))
        try await wait { session.webView != nil }
        let mobile = URL(string: "https://y.music.163.com/m/song?id=3446748064")!
        var action: WKNavigationActionPolicy?, response: WKNavigationResponsePolicy?
        session.decideDocumentAction(url: mobile, target: .mainFrame, download: false) { action = $0 }
        session.decideDocumentResponse(url: mobile, mainFrame: true, displayable: true, status: 200, mimeType: "text/html") { response = $0 }
        XCTAssertEqual(action, .allow); XCTAssertEqual(response, .allow)
        XCTAssertNotNil(session.webView); XCTAssertEqual(session.request?.originalURL, songURL)
        session.decideDocumentResponse(url: URL(string: "https://y.music.163.com.evil.invalid/m/song?id=3446748064"), mainFrame: true, displayable: true, status: 200, mimeType: "text/html") { response = $0 }
        XCTAssertEqual(response, .cancel); XCTAssertNil(session.webView)
        XCTAssertEqual(session.phase, .failed)
        XCTAssertEqual(session.navigationDiagnostic, "response/main/host · y.music.163.com.evil.invalid")
    }

    func testInitialUncommittedBlockedNavigationNeverPreservesBlankBrowser() async throws {
        let pair = fixture(), current = try request(pair), provider = NetEaseListeningProvider(pair.0)
        for url in [URL(string: "https://outside.invalid/")!, URL(string: "http://music.163.com/song?id=3446748064")!] {
            let session = NetEaseListeningSession(loadDocument: { _, _ in })
            session.start(current, track: pair.0, locale: "en", provider: provider)
            try await wait { session.webView != nil }
            var action: WKNavigationActionPolicy?
            session.decideDocumentAction(url: url, target: .mainFrame, download: false) { action = $0 }
            XCTAssertEqual(action, .cancel); XCTAssertEqual(session.phase, .failed)
            XCTAssertEqual(session.failureKey, "neteaseBrowserNavigationBlocked"); XCTAssertNil(session.webView)
            session.stop(); XCTAssertNil(session.navigationDiagnostic)
        }
    }

    func testNoBrowserOrFallbackBeforeFreshVerificationAndCancelledResultCannotReopen() async throws {
        let pair = fixture(), provider = NetEaseListeningProvider(pair.0, hold: true)
        var loads = 0
        let session = NetEaseListeningSession(loadDocument: { _, _ in loads += 1 })
        session.start(try request(pair), track: pair.0, locale: "en", provider: provider)
        try await waitForCall(provider)
        XCTAssertEqual(session.phase, .checking); XCTAssertNil(session.webView); XCTAssertEqual(loads, 0)
        session.pause(); await provider.release()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(session.phase, .paused); XCTAssertNil(session.webView); XCTAssertEqual(loads, 0)
        session.stop(); XCTAssertNil(session.request)
        let externalProvider = NetEaseListeningProvider(pair.0, hold: true)
        var opened = false
        session.openExternal(try request(pair), track: pair.0, locale: "en", provider: externalProvider) { _ in opened = true }
        try await waitForCall(externalProvider)
        session.stop(); await externalProvider.release(); try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(opened); XCTAssertEqual(session.phase, .idle)
    }

    func testWithdrawnLinkAndNetworkFailureNeverCreateThirdPartyBrowser() async throws {
        let pair = fixture(), current = try request(pair)
        let removed = withoutLinks(pair.0)
        for provider in [NetEaseListeningProvider(removed), NetEaseListeningProvider(pair.0, throwsError: true)] {
            let session = NetEaseListeningSession(loadDocument: { _, _ in XCTFail("No third-party load") })
            session.start(current, track: pair.0, locale: "en", provider: provider)
            try await wait { session.phase == .failed }
            XCTAssertNil(session.webView)
            session.openExternal(current, track: pair.0, locale: "en", provider: provider) { _ in XCTFail("No withdrawn fallback") }
            try await wait { session.phase == .failed }; XCTAssertNil(session.webView)
        }
    }

    func testRetryAndExplicitFallbackRevalidatePublicationWithoutFollowingRedirect() async throws {
        let pair = fixture(), current = try request(pair), provider = NetEaseListeningProvider(pair.0)
        let session = NetEaseListeningSession(loadDocument: { _, _ in })
        session.start(current, track: pair.0, locale: "en", provider: provider)
        try await wait { session.webView != nil }
        session.pause()
        session.start(current, track: pair.0, locale: "en", provider: provider)
        try await wait { session.webView != nil }
        var opened: URL?
        session.openExternal(current, track: pair.0, locale: "en", provider: provider) { opened = $0 }
        try await wait { opened != nil }
        XCTAssertEqual(opened, current.originalURL); XCTAssertNil(session.webView)
        let calls = await provider.calls; XCTAssertEqual(calls, 3)
        let removed = withoutLinks(pair.0); await provider.setTrack(removed)
        session.start(current, track: pair.0, locale: "en", provider: provider)
        try await wait { session.phase == .failed }
        XCTAssertEqual(session.failureKey, "neteaseBrowserUnavailable")
    }

    func testRedirectedResponsesAndDownloadsCannotBecomeDocuments() async throws {
        let pair = fixture(), session = NetEaseListeningSession(loadDocument: { _, _ in })
        session.start(try request(pair), track: pair.0, locale: "en", provider: NetEaseListeningProvider(pair.0))
        try await wait { session.webView != nil }
        var response: WKNavigationResponsePolicy?
        session.decideDocumentResponse(url: songURL, mainFrame: true, displayable: true, status: 200, mimeType: "text/html") { response = $0 }
        XCTAssertEqual(response, .allow)
        session.decideDocumentResponse(url: URL(string: "https://outside.invalid/redirected"), mainFrame: false, displayable: true, status: 200, mimeType: "text/html") { response = $0 }
        XCTAssertEqual(response, .cancel); XCTAssertNotNil(session.webView)
        XCTAssertEqual(session.noticeKey, "neteaseBrowserNavigationBlocked")
        var action: WKNavigationActionPolicy?
        session.decideDocumentAction(url: songURL, target: .newWindow, download: false) { action = $0 }
        XCTAssertEqual(action, .cancel)
        session.decideDocumentAction(url: songURL, target: .mainFrame, download: true) { action = $0 }
        XCTAssertEqual(action, .cancel); XCTAssertNil(session.webView)
        session.decideDocumentResponse(url: songURL, mainFrame: true, displayable: true, status: 200, mimeType: "text/html") { response = $0 }
        XCTAssertEqual(response, .cancel)
    }

    func testHTMLResponseRequiredAndHTTPFailuresAreNotMarkedLoaded() async throws {
        let pair = fixture(), provider = NetEaseListeningProvider(pair.0)
        for failure in [(403, "text/html"), (500, "text/html"), (200, "audio/mpeg"), (200, "application/octet-stream")] {
            let session = NetEaseListeningSession(loadDocument: { _, _ in })
            session.start(try request(pair), track: pair.0, locale: "en", provider: provider)
            try await wait { session.webView != nil }
            let oldView = try XCTUnwrap(session.webView)
            var result: WKNavigationResponsePolicy?
            session.decideDocumentResponse(url: songURL, mainFrame: true, displayable: true, status: failure.0, mimeType: failure.1) { result = $0 }
            XCTAssertEqual(result, .cancel); XCTAssertEqual(session.phase, .failed)
            session.webView(oldView, didFinish: nil)
            XCTAssertEqual(session.phase, .failed); XCTAssertNil(session.webView)
        }
    }

    func testCommittedPageSurvivesBlockedNavigationAndRetryRevalidatesPublication() async throws {
        let pair = fixture(), session = NetEaseListeningSession(loadDocument: localDocument)
        let provider = NetEaseListeningProvider(pair.0), current = try request(pair)
        session.start(current, track: pair.0, locale: "en", provider: provider)
        try await wait { session.webView != nil }
        let view = try XCTUnwrap(session.webView)
        try attach(view)
        defer { session.stop(); view.removeFromSuperview() }
        try await wait { session.phase == .loaded }
        var action: WKNavigationActionPolicy?
        for scheme in ["orpheus://song/3446748064", "file:///private/file", "javascript:alert(1)"] {
            session.decideDocumentAction(url: URL(string: scheme), target: .mainFrame, download: false) { action = $0 }
            XCTAssertEqual(action, .cancel)
            XCTAssertTrue(session.webView === view)
            XCTAssertEqual(session.phase, .loaded)
            XCTAssertEqual(session.noticeKey, "neteaseBrowserNavigationBlocked")
            XCTAssertEqual(session.navigationDiagnostic, "action/main/scheme")
        }
        // The unsupported target is never allowed. The already committed
        // approved document is retained with a retry state instead of erased.
        session.decideDocumentAction(url: URL(string: "https://untrusted.invalid/"), target: .mainFrame, download: false) { action = $0 }
        XCTAssertEqual(action, .cancel); XCTAssertTrue(session.webView === view)
        XCTAssertEqual(session.phase, .failed)
        session.start(current, track: pair.0, locale: "en", provider: provider)
        XCTAssertNil(session.navigationDiagnostic); XCTAssertNil(session.webView)
        try await wait { session.webView != nil }
        XCTAssertFalse(session.webView === view)
        let calls = await provider.calls; XCTAssertEqual(calls, 2)
        session.stop()
    }

    func testCommittedPageSurvivesBlockedResponseButNotHTTPErrorOrDownload() async throws {
        let pair = fixture(), provider = NetEaseListeningProvider(pair.0)
        let session = NetEaseListeningSession(loadDocument: localDocument)
        session.start(try request(pair), track: pair.0, locale: "en", provider: provider)
        try await wait { session.webView != nil }
        let view = try XCTUnwrap(session.webView)
        try attach(view)
        defer { session.stop(); view.removeFromSuperview() }
        try await wait { session.phase == .loaded }
        var response: WKNavigationResponsePolicy?
        session.decideDocumentResponse(url: URL(string: "https://untrusted.invalid/redirect?token=SECRET"), mainFrame: true, displayable: true, status: 200, mimeType: "text/html") { response = $0 }
        XCTAssertEqual(response, .cancel); XCTAssertTrue(session.webView === view)
        XCTAssertEqual(session.phase, .failed)
        XCTAssertEqual(session.navigationDiagnostic, "response/main/host · untrusted.invalid")
        session.decideDocumentResponse(url: songURL, mainFrame: true, displayable: true, status: 403, mimeType: "text/html") { response = $0 }
        XCTAssertEqual(response, .cancel); XCTAssertNil(session.webView)
        XCTAssertEqual(session.failureKey, "neteaseBrowserLoadFailure")

        session.start(try request(pair), track: pair.0, locale: "en", provider: provider)
        try await wait { session.webView != nil }
        let second = try XCTUnwrap(session.webView); try attach(second)
        try await wait { session.phase == .loaded }
        var action: WKNavigationActionPolicy?
        session.decideDocumentAction(url: songURL, target: .mainFrame, download: true) { action = $0 }
        XCTAssertEqual(action, .cancel); XCTAssertNil(session.webView)
        XCTAssertEqual(session.navigationDiagnostic, "action/main/download · music.163.com")
        second.removeFromSuperview()
    }

    func testRetainedPageIgnoresNilAndRetiredCallbacksAndNewNavigationClearsDiagnostic() async throws {
        let pair = fixture()
        var originalNavigation: WKNavigation?
        let html = "<html><head><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'\"></head><body>Local document</body></html>"
        let session = NetEaseListeningSession(loadDocument: { view, url in
            originalNavigation = view.loadHTMLString(html, baseURL: url)
        })
        session.start(try request(pair), track: pair.0, locale: "en", provider: NetEaseListeningProvider(pair.0))
        try await wait { session.webView != nil }
        let view = try XCTUnwrap(session.webView)
        try attach(view)
        defer { session.stop(); view.removeFromSuperview() }
        try await wait { session.phase == .loaded }
        let original = try XCTUnwrap(originalNavigation)
        for target: NetEaseListeningNavigationPolicy.Target in [.subframe, .mainFrame] {
            session.decideDocumentAction(url: URL(string: "https://blocked.invalid/"), target: target, download: false) {
                XCTAssertEqual($0, .cancel)
            }
        }
        XCTAssertEqual(session.phase, .failed)
        XCTAssertNotNil(session.noticeKey)
        let diagnostic = session.navigationDiagnostic

        session.webView(view, didStartProvisionalNavigation: nil)
        for navigation: WKNavigation? in [nil, original] {
            session.webView(view, didCommit: navigation)
            session.webView(view, didFinish: navigation)
            session.webView(view, didFailProvisionalNavigation: navigation, withError: URLError(.timedOut))
            session.webView(view, didFail: navigation, withError: URLError(.cannotConnectToHost))
            XCTAssertTrue(session.webView === view)
            XCTAssertEqual(session.phase, .failed)
            XCTAssertEqual(session.failureKey, "neteaseBrowserNavigationBlocked")
            XCTAssertEqual(session.navigationDiagnostic, diagnostic)
        }

        let next = try XCTUnwrap(view.loadHTMLString(html, baseURL: songURL))
        session.webView(view, didStartProvisionalNavigation: next)
        XCTAssertEqual(session.phase, .loading)
        XCTAssertNil(session.navigationDiagnostic); XCTAssertNil(session.noticeKey)
        session.webView(view, didFinish: original)
        session.webView(view, didFail: original, withError: URLError(.timedOut))
        XCTAssertEqual(session.phase, .loading); XCTAssertTrue(session.webView === view)
        try await wait { session.phase == .loaded }
        XCTAssertNil(session.navigationDiagnostic); XCTAssertNil(session.noticeKey)
    }

    func testRealWebKitLocalDocumentIsEphemeralGestureOnlyAndTeardownIgnoresLateCallbacks() async throws {
        let pair = fixture(), session = NetEaseListeningSession(loadDocument: localDocument)
        session.start(try request(pair), track: pair.0, locale: "en", provider: NetEaseListeningProvider(pair.0))
        try await wait { session.webView != nil }
        let view = try XCTUnwrap(session.webView)
        try attach(view)
        defer { session.stop(); view.removeFromSuperview() }
        try await wait { session.phase == .loaded }
        XCTAssertFalse(view.configuration.websiteDataStore.isPersistent)
        XCTAssertTrue(view.configuration.allowsInlineMediaPlayback)
        XCTAssertFalse(view.configuration.allowsAirPlayForMediaPlayback)
        XCTAssertFalse(view.configuration.allowsPictureInPictureMediaPlayback)
        XCTAssertFalse(view.configuration.preferences.javaScriptCanOpenWindowsAutomatically)
        XCTAssertEqual(view.configuration.mediaTypesRequiringUserActionForPlayback, .all)
        session.pause()
        XCTAssertEqual(session.phase, .paused); XCTAssertNil(session.webView)
        XCTAssertNil(view.navigationDelegate); XCTAssertNil(view.uiDelegate)
        session.webView(view, didFinish: nil)
        session.webViewWebContentProcessDidTerminate(view)
        XCTAssertEqual(session.phase, .paused)
    }

    func testRealWebKitMainNavigationIsBlockedBeforeExternalRequest() async throws {
        let pair = fixture(), session = NetEaseListeningSession(loadDocument: localDocument)
        session.start(try request(pair), track: pair.0, locale: "en", provider: NetEaseListeningProvider(pair.0))
        try await wait { session.webView != nil }
        let view = try XCTUnwrap(session.webView)
        try attach(view)
        defer { session.stop(); view.removeFromSuperview() }
        try await wait { session.phase == .loaded }
        view.evaluateJavaScript("location.href='https://untrusted.invalid/';", completionHandler: nil)
        try await wait { session.phase == .failed }
        XCTAssertEqual(session.failureKey, "neteaseBrowserNavigationBlocked")
        XCTAssertTrue(session.webView === view)
    }

    func testOlderNavigationFinishCannotCompleteANewerDocument() async throws {
        let pair = fixture(), session = NetEaseListeningSession(loadDocument: localDocument)
        session.start(try request(pair), track: pair.0, locale: "en", provider: NetEaseListeningProvider(pair.0))
        try await wait { session.webView != nil }
        let view = try XCTUnwrap(session.webView)
        try attach(view)
        defer { session.stop(); view.removeFromSuperview() }
        try await wait { session.phase == .loaded }
        let first = try XCTUnwrap(view.loadHTMLString("<html>First local document</html>", baseURL: songURL))
        let second = try XCTUnwrap(view.loadHTMLString("<html>Second local document</html>", baseURL: songURL))
        session.webView(view, didStartProvisionalNavigation: second)
        XCTAssertEqual(session.phase, .loading)
        session.webView(view, didFinish: first)
        XCTAssertEqual(session.phase, .loading)
        session.webView(view, didFail: first, withError: URLError(.timedOut))
        session.webView(view, didFailProvisionalNavigation: first, withError: URLError(.cannotConnectToHost))
        XCTAssertEqual(session.phase, .loading)
        session.webView(view, didFinish: second)
        XCTAssertEqual(session.phase, .loaded)
    }

    func testOlderCommitCannotMakeAnUncommittedNewDocumentPreservable() async throws {
        let pair = fixture(), session = NetEaseListeningSession(loadDocument: { _, _ in })
        session.start(try request(pair), track: pair.0, locale: "en", provider: NetEaseListeningProvider(pair.0))
        try await wait { session.webView != nil }
        let view = try XCTUnwrap(session.webView)
        // These local loads supply distinct real WKNavigation identities. No
        // remote request is made and no actor yield lets either one commit.
        let first = try XCTUnwrap(view.loadHTMLString("<html>Old local document</html>", baseURL: songURL))
        let second = try XCTUnwrap(view.loadHTMLString("<html>New local document</html>", baseURL: songURL))
        session.webView(view, didStartProvisionalNavigation: second)
        session.webView(view, didCommit: first)
        var action: WKNavigationActionPolicy?
        session.decideDocumentAction(url: URL(string: "https://untrusted.invalid/"), target: .mainFrame, download: false) { action = $0 }
        XCTAssertEqual(action, .cancel); XCTAssertEqual(session.phase, .failed)
        XCTAssertNil(session.webView)
        session.webView(view, didCommit: second)
        session.webView(view, didFinish: second)
        XCTAssertNil(session.webView); XCTAssertEqual(session.phase, .failed)
        session.stop()
    }

    func testTimeoutRetiresVerificationAndLoadingAndCannotBeRevived() async throws {
        let pair = fixture(), provider = NetEaseListeningProvider(pair.0, hold: true)
        var loads = 0
        let checking = NetEaseListeningSession(loadDocument: { _, _ in loads += 1 }, timeout: .milliseconds(100))
        checking.start(try request(pair), track: pair.0, locale: "en", provider: provider)
        try await waitForCall(provider)
        try await wait { checking.phase == .failed }
        await provider.release(); try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(loads, 0); XCTAssertNil(checking.webView)
        XCTAssertEqual(checking.failureKey, "neteaseBrowserVerifyFailure")
        let loading = NetEaseListeningSession(loadDocument: { _, _ in }, timeout: .milliseconds(100))
        loading.start(try request(pair), track: pair.0, locale: "en", provider: NetEaseListeningProvider(pair.0))
        try await wait { loading.phase == .failed }
        XCTAssertEqual(loading.failureKey, "neteaseBrowserLoadFailure"); XCTAssertNil(loading.webView)
    }
}
