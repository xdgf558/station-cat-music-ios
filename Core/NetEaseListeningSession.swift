import Foundation
import Observation
import WebKit

/// Experimental foreground browser. `loaded` describes the document, never a
/// claim that the service permits playback or that a song has started playing.
@MainActor @Observable final class NetEaseListeningSession: NSObject {
    enum Phase: Equatable { case idle, checking, loading, loaded, paused, failed }
    private(set) var phase: Phase = .idle
    private(set) var request: NetEaseListeningRequest?
    private(set) var webView: WKWebView?
    private(set) var failureKey = "neteaseBrowserLoadFailure"
    private(set) var noticeKey: String?
    private(set) var navigationDiagnostic: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var activeNavigation: WKNavigation?
    @ObservationIgnored private var hasCommittedMainDocument = false
    @ObservationIgnored private let loadDocument: (WKWebView, URL) -> Void
    @ObservationIgnored private let syntheticDocument: Bool
    @ObservationIgnored private let timeout: Duration
    @ObservationIgnored private let embeddingAllowed: Bool
    private var generation = UUID()

    init(embeddingAllowed: Bool = ThirdPartyPlaybackPolicy.embeddingAllowed,
         loadDocument: ((WKWebView, URL) -> Void)? = nil, timeout: Duration = .seconds(20)) {
        self.embeddingAllowed = embeddingAllowed && ThirdPartyPlaybackPolicy.embeddingAllowed
        self.syntheticDocument = loadDocument != nil
        self.loadDocument = loadDocument ?? { view, url in
            view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
        }
        self.timeout = timeout
    }

    func start(_ request: NetEaseListeningRequest, track: Track, locale: String,
               provider: any PlatformMusicProviding) {
        guard embeddingAllowed else { stop(); fail("thirdPartyExternalOnly"); return }
        verify(request, track: track, locale: locale, provider: provider) { [weak self] in
            self?.load(request)
        }
    }

    /// Only a native, explicit fallback button may call this. Every attempt
    /// rechecks publication; rejected popups never call this automatically.
    func openExternal(_ request: NetEaseListeningRequest, track: Track, locale: String,
                      provider: any PlatformMusicProviding, completion: @escaping (URL) -> Void) {
        verify(request, track: track, locale: locale, provider: provider) { [weak self] in
            guard let self else { return }
            self.pause()
            completion(request.originalURL)
        }
    }

    private func verify(_ request: NetEaseListeningRequest, track: Track, locale: String,
                        provider: any PlatformMusicProviding, completion: @escaping () -> Void) {
        stop()
        self.request = request
        guard request.trackID == track.id else { fail("neteaseBrowserUnavailable"); return }
        phase = .checking
        let ticket = generation
        armTimeout(ticket)
        task = Task { [weak self] in
            do {
                let current = try await provider.platformDetail(track, locale: locale)
                try Task.checkCancellation()
                guard let self, self.generation == ticket else { return }
                guard request.matches(current) else { self.fail("neteaseBrowserUnavailable"); return }
                self.timeoutTask?.cancel(); self.timeoutTask = nil
                completion()
            } catch {
                guard let self, self.generation == ticket, !Task.isCancelled else { return }
                self.fail("neteaseBrowserVerifyFailure")
            }
        }
    }

    private func load(_ request: NetEaseListeningRequest) {
        guard embeddingAllowed else { fail("thirdPartyExternalOnly"); return }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.allowsPictureInPictureMediaPlayback = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.accessibilityIdentifier = "neteaseListeningWebView"
        webView = view
        phase = .loading
        armTimeout(generation)
        loadDocument(view, request.pageURL)
    }

    private func armTimeout(_ ticket: UUID) {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self, timeout] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, self.generation == ticket,
                  self.phase == .checking || self.phase == .loading else { return }
            self.fail(self.phase == .checking ? "neteaseBrowserVerifyFailure" : "neteaseBrowserLoadFailure")
        }
    }

    func pause() {
        guard request != nil else { return }
        cancelWork()
        phase = .paused
    }

    func stop() {
        cancelWork()
        request = nil
        noticeKey = nil
        navigationDiagnostic = nil
        phase = .idle
    }

    private func cancelWork() {
        generation = UUID()
        task?.cancel(); task = nil
        timeoutTask?.cancel(); timeoutTask = nil
        destroyWebView()
    }

    private func destroyWebView() {
        hasCommittedMainDocument = false
        guard let view = webView else { return }
        // Suspend the whole web process's media, including cross-origin child
        // frames. Removing an iframe or pausing only the main DOM is insufficient.
        view.setAllMediaPlaybackSuspended(true, completionHandler: nil)
        view.pauseAllMediaPlayback(completionHandler: nil)
        view.stopLoading()
        view.navigationDelegate = nil
        view.uiDelegate = nil
        view.loadHTMLString("<html></html>", baseURL: nil)
        view.removeFromSuperview()
        webView = nil
        activeNavigation = nil
    }

    private func fail(_ key: String) {
        cancelWork()
        failureKey = key
        phase = .failed
    }

    func decideDocumentAction(url: URL?, target: NetEaseListeningNavigationPolicy.Target,
                              download: Bool, method: String? = "GET", decisionHandler: (WKNavigationActionPolicy) -> Void) {
        guard webView != nil else { decisionHandler(.cancel); return }
        guard !download, method == "GET", let request, let url,
              NetEaseListeningNavigationPolicy.allows(url, target: target, request: request) else {
            decisionHandler(.cancel)
            navigationDiagnostic = NetEaseListeningNavigationPolicy.diagnostic(url, target: target, response: false, download: download)
            // Preserve the existing notice-only handling of attempts to launch
            // another app. No app-scheme URL is opened or used as a fallback.
            if !download, target == .mainFrame, let scheme = url?.scheme?.lowercased(),
               scheme != "https", scheme != "http" {
                noticeKey = "neteaseBrowserNavigationBlocked"
            } else { blocked(target, preserveCommittedPage: !download) }
            return
        }
        decisionHandler(.allow)
    }

    func decideDocumentResponse(url: URL?, mainFrame: Bool, displayable: Bool,
                                status: Int?, mimeType: String?, decisionHandler: (WKNavigationResponsePolicy) -> Void) {
        guard webView != nil else { decisionHandler(.cancel); return }
        let target: NetEaseListeningNavigationPolicy.Target = mainFrame ? .mainFrame : .subframe
        guard let request, let url, NetEaseListeningNavigationPolicy.allows(url, target: target, request: request) else {
            decisionHandler(.cancel)
            navigationDiagnostic = NetEaseListeningNavigationPolicy.diagnostic(url, target: target, response: true)
            blocked(target); return
        }
        // loadHTMLString fixtures have no HTTP status. Only the constructor's
        // explicit local loader can accept that synthetic main document.
        guard displayable, status.map({ (200..<300).contains($0) }) ?? (syntheticDocument || url.absoluteString == "about:blank"),
              ["text/html", "application/xhtml+xml"].contains(mimeType?.lowercased() ?? "") else {
            decisionHandler(.cancel)
            if mainFrame { fail("neteaseBrowserLoadFailure") } else { noticeKey = "neteaseBrowserNavigationBlocked" }
            return
        }
        decisionHandler(.allow)
    }

    private func blocked(_ target: NetEaseListeningNavigationPolicy.Target, preserveCommittedPage: Bool = true) {
        guard target == .mainFrame else { noticeKey = "neteaseBrowserNavigationBlocked"; return }
        if preserveCommittedPage, hasCommittedMainDocument, let webView {
            // Cancel only the unsupported destination. A previously committed,
            // approved document stays visible; retry still starts with fresh
            // publication verification. No rejected URL is opened elsewhere.
            timeoutTask?.cancel(); timeoutTask = nil
            activeNavigation = nil
            webView.stopLoading()
            failureKey = "neteaseBrowserNavigationBlocked"
            phase = .failed
        } else { fail("neteaseBrowserNavigationBlocked") }
    }
}

extension NetEaseListeningSession: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard webView === self.webView else { decisionHandler(.cancel); return }
        let target: NetEaseListeningNavigationPolicy.Target = navigationAction.targetFrame.map { $0.isMainFrame ? .mainFrame : .subframe } ?? .newWindow
        if target == .mainFrame, navigationAction.navigationType == .linkActivated,
           !navigationAction.shouldPerformDownload, navigationAction.request.httpMethod == "GET",
           let request, let url = navigationAction.request.url,
           NetEaseListeningNavigationPolicy.allows(url, target: target, request: request) {
            // Cancel WebKit's user-link path, which can attempt an associated-
            // app handoff, then issue an owned navigation in this same browser.
            // The resulting .other navigation still passes the normal policy.
            decisionHandler(.cancel)
            webView.load(navigationAction.request)
            return
        }
        decideDocumentAction(url: navigationAction.request.url, target: target,
                             download: navigationAction.shouldPerformDownload, method: navigationAction.request.httpMethod,
                             decisionHandler: decisionHandler)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        guard webView === self.webView else { decisionHandler(.cancel); return }
        decideDocumentResponse(url: navigationResponse.response.url, mainFrame: navigationResponse.isForMainFrame,
                               displayable: navigationResponse.canShowMIMEType,
                               status: (navigationResponse.response as? HTTPURLResponse)?.statusCode,
                               mimeType: navigationResponse.response.mimeType, decisionHandler: decisionHandler)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView, let navigation, let activeNavigation,
              navigation === activeNavigation, phase == .loading else { return }
        timeoutTask?.cancel(); timeoutTask = nil
        phase = .loaded
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard webView === self.webView, let navigation else { return }
        activeNavigation = navigation
        navigationDiagnostic = nil
        noticeKey = nil
        phase = .loading
        armTimeout(generation)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard webView === self.webView, let navigation, let activeNavigation,
              navigation === activeNavigation, phase == .loading else { return }
        hasCommittedMainDocument = true
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard webView === self.webView, let navigation, let activeNavigation,
              navigation === activeNavigation, (error as NSError).code != NSURLErrorCancelled else { return }
        fail("neteaseBrowserLoadFailure")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard webView === self.webView, let navigation, let activeNavigation,
              navigation === activeNavigation, (error as NSError).code != NSURLErrorCancelled else { return }
        fail("neteaseBrowserLoadFailure")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView === self.webView { fail("neteaseBrowserLoadFailure") }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if webView === self.webView {
            navigationDiagnostic = NetEaseListeningNavigationPolicy.diagnostic(navigationAction.request.url, target: .newWindow, response: false)
            noticeKey = "neteaseBrowserNavigationBlocked"
        }
        return nil
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }
}
