import Foundation
import Observation
import WebKit

/// One foreground-only embed. No Douyin request occurs until an explicit tap
/// and a fresh Station Cat publication check. Nothing is persisted or downloaded.
@MainActor @Observable final class DouyinClipSession: NSObject {
    enum Phase: Equatable { case idle, checking, loading, loaded, failed }
    private(set) var phase: Phase = .idle
    private(set) var selectedID: String?
    private(set) var failureKey = "douyinLoadFailure"
    private(set) var webView: WKWebView?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var timeout: Task<Void, Never>?
    @ObservationIgnored private var bridge: Bridge?
    @ObservationIgnored private var external: ((URL) -> Void)?
    @ObservationIgnored private let document: (DouyinClip, String) -> String
    @ObservationIgnored private let verifyEmbed: @Sendable (DouyinClip) async throws -> Void
    private var token = UUID().uuidString

    init(document: @escaping (DouyinClip, String) -> String = DouyinEmbedDocument.html,
         verifyEmbed: (@Sendable (DouyinClip) async throws -> Void)? = nil) {
        self.document = document
        self.verifyEmbed = verifyEmbed ?? { try await DouyinEmbedAPI(transport: URLSessionTransport()).verify($0) }
    }

    func start(_ clip: PlatformClip, track: Track, locale: String, provider: any PlatformMusicProviding,
               externalOnly: Bool = false, openExternal: @escaping (URL) -> Void) {
        stop()
        guard let douyin = clip.douyin, clip.trackID == track.id else { return }
        selectedID = clip.id; phase = .checking; external = openExternal
        let ticket = token
        task = Task { [weak self] in
            do {
                let current = try await provider.clips(track, locale: locale)
                try Task.checkCancellation()
                guard let self, self.token == ticket else { return }
                guard current.contains(clip) else { self.fail("douyinUnavailable"); return }
                if externalOnly { self.stop(); openExternal(douyin.watchURL); return }
                try await self.verifyEmbed(douyin)
                try Task.checkCancellation()
                guard self.token == ticket else { return }
                self.load(douyin, ticket: ticket)
            } catch {
                guard let self, self.token == ticket, !Task.isCancelled else { return }
                self.fail(error is DouyinEmbedError ? (error as? DouyinEmbedError == .unavailable ? "douyinUnavailable" : "douyinLoadFailure") : "douyinVerifyFailure")
            }
        }
    }

    private func load(_ clip: DouyinClip, ticket: String) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.allowsInlineMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = false
        config.allowsPictureInPictureMediaPlayback = false
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let bridge = Bridge(self); self.bridge = bridge
        config.userContentController.add(bridge, name: "douyin")
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false; view.backgroundColor = .clear; view.scrollView.isScrollEnabled = false
        view.navigationDelegate = self; view.uiDelegate = self
        view.accessibilityIdentifier = "douyinOfficialPlayer"
        webView = view; phase = .loading
        view.loadHTMLString(document(clip, ticket), baseURL: DouyinEmbedDocument.origin)
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self, self.token == ticket, self.phase == .loading else { return }
            self.fail("douyinLoadFailure")
        }
    }

    func stop() {
        token = UUID().uuidString; task?.cancel(); task = nil; timeout?.cancel(); timeout = nil
        destroyWebView(); selectedID = nil; phase = .idle; external = nil
    }
    private func destroyWebView() {
        guard let view = webView else { return }
        view.configuration.userContentController.removeScriptMessageHandler(forName: "douyin")
        view.evaluateJavaScript("if(typeof stopClip==='function'){stopClip()}", completionHandler: nil)
        view.stopLoading(); view.loadHTMLString("<html></html>", baseURL: nil)
        view.navigationDelegate = nil; view.uiDelegate = nil; view.removeFromSuperview()
        bridge = nil; webView = nil
    }
    private func fail(_ key: String) {
        timeout?.cancel(); timeout = nil; destroyWebView(); failureKey = key; phase = .failed
    }
    fileprivate func message(_ message: WKScriptMessage) {
        guard message.webView === webView, message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any], body["token"] as? String == token else { return }
        if body["event"] as? String == "loaded" {
            timeout?.cancel(); timeout = nil; phase = .loaded
        } else if body["event"] as? String == "error" {
            fail("douyinLoadFailure")
        }
    }

    private func handoff(_ url: URL) {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
              url.host != nil, url.absoluteString.utf8.count <= 4096,
              let external else { return }
        stop(); external(url)
    }
    private final class Bridge: NSObject, WKScriptMessageHandler {
        weak var owner: DouyinClipSession?
        init(_ owner: DouyinClipSession) { self.owner = owner }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { owner?.message(message) }
    }
}

extension DouyinClipSession: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard webView === self.webView, let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if navigationAction.targetFrame == nil || navigationAction.targetFrame?.isMainFrame == true {
            if DouyinEmbedDocument.isWrapperNavigation(url) { decisionHandler(.allow); return }
            decisionHandler(.cancel)
            if navigationAction.navigationType == .linkActivated { handoff(url) }
        } else {
            // The official iframe owns its controls, ads and nested HTTPS frames.
            // Do not filter media/ad subresources or substitute playback URLs.
            decisionHandler(url.scheme == "https" ? .allow : .cancel)
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if webView === self.webView { fail("douyinLoadFailure") }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if webView === self.webView { fail("douyinLoadFailure") }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView === self.webView { fail("douyinLoadFailure") }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Automatic JS windows are disabled. User-initiated official player
        // links (including ads) hand off to the system browser, never this embed.
        if webView === self.webView, navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url { handoff(url) }
        return nil
    }
}
