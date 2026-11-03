import SwiftUI
import WebKit

/// User-initiated official webpage session. A loaded document is not evidence
/// that a song is playing; the app owns only the surrounding browser controls.
struct NetEaseListeningView: View {
    let request: NetEaseListeningRequest
    let track: Track
    let locale: String
    let provider: any PlatformMusicProviding
    let text: (String) -> String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var session = Self.makeSession()
    @State private var externalFailed = false
    @State private var copied = false
    @State private var active = false
    @State private var externalOperation = UUID()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(track.title).radioSerif(20).fixedSize(horizontal: false, vertical: true)
                    Text(text("neteaseBrowserNotice")).font(.caption).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    status
                    if let webView = session.webView {
                        ListeningWebView(webView: webView).frame(height: typeSize.isAccessibilitySize ? 420 : 500)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if let key = session.noticeKey {
                        Text(text(key)).font(.subheadline).accessibilityIdentifier("neteaseBrowserNotice")
                    }
                    if let diagnostic = session.navigationDiagnostic {
                        Text(text("neteaseBrowserDiagnostic") + ": " + diagnostic)
                            .font(.caption.monospaced()).foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            .accessibilityIdentifier("neteaseBrowserDiagnostic")
                    }
                    Button(action: openExternally) {
                        Label(text("neteaseBrowserExternal"), systemImage: "arrow.up.right.square").frame(minHeight: 44)
                    }.accessibilityIdentifier("neteaseBrowserExternal")
                        .disabled(session.phase == .checking || !active)
                    if externalFailed {
                        Text(text("platformOpenFailure")).font(.subheadline).accessibilityIdentifier("neteaseExternalFailure")
                    }
                    Button {
                        UIPasteboard.general.url = request.originalURL; copied = true
                    } label: {
                        Label(text(copied ? "platformCopied" : "platformCopyLink"), systemImage: copied ? "checkmark" : "link")
                            .frame(minHeight: 44)
                    }.accessibilityIdentifier("neteaseBrowserCopy")
                    Text(text("neteaseBrowserPrivacy")).font(.caption).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }.background(Palette.background)
                .navigationTitle(text("neteaseBrowserTitle")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(text("close")) { active = false; externalOperation = UUID(); session.stop(); dismiss() }
                            .accessibilityIdentifier("neteaseBrowserClose")
                    }
                }
        }.foregroundStyle(Palette.ink).tint(Palette.accent)
            .task { active = true; start() }
            .onChange(of: scenePhase) { _, value in
                if value != .active { externalOperation = UUID(); session.pause() }
            }
            .onDisappear { active = false; externalOperation = UUID(); session.stop() }
    }

    @ViewBuilder private var status: some View {
        switch session.phase {
        case .checking, .loading:
            ProgressView(text("neteaseBrowserLoading")).frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("neteaseBrowserLoading")
        case .loaded:
            Text(text("neteaseBrowserPlayHint")).font(.subheadline).accessibilityIdentifier("neteaseBrowserLoaded")
        case .idle, .paused, .failed:
            Text(text(session.phase == .failed ? session.failureKey : "neteaseBrowserPaused"))
                .font(.subheadline).accessibilityIdentifier("neteaseBrowserFailure")
            Button(text("retry"), action: start).frame(minHeight: 44).accessibilityIdentifier("neteaseBrowserRetry")
        }
    }
    private func start() {
        guard active, scenePhase == .active else { return }
        externalOperation = UUID(); externalFailed = false; copied = false
        session.start(request, track: track, locale: locale, provider: provider)
    }
    private func openExternally() {
        guard active, scenePhase == .active else { return }
        externalOperation = UUID(); let ticket = externalOperation
        externalFailed = false
        session.openExternal(request, track: track, locale: locale, provider: provider) { url in
            guard active, externalOperation == ticket, scenePhase == .active else { return }
            openURL(url) { accepted in
                guard active, externalOperation == ticket else { return }
                externalFailed = !accepted
            }
        }
    }
    private static func makeSession() -> NetEaseListeningSession {
        #if DEBUG && targetEnvironment(simulator)
        if Bundle.main.object(forInfoDictionaryKey: "StationEnvironment") as? String == "mock",
           ProcessInfo.processInfo.arguments.contains("--platform-music-fixture"),
           let mode = ProcessInfo.processInfo.environment["STATION_NETEASE_BROWSER_FIXTURE"], ["ready", "blocked", "mobile", "initial-blocked"].contains(mode) {
            return NetEaseListeningSession(loadDocument: { webView, url in
                // This document cannot load remote resources. Its forbidden
                // navigation is cancelled by the product delegate before I/O.
                let documentURL = mode == "mobile" ? URL(string: "https://y.music.163.com/m/song?id=3446748064")!
                    : mode == "initial-blocked" ? URL(string: "https://blocked.example.test/")! : url
                webView.loadHTMLString("""
                <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
                <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
                <style>body{background:#11172b;color:white;font:18px -apple-system;padding:20px}a{color:#b5aaff}</style>
                </head><body><h2>本机界面测试</h2><p>未连接网易云 · 无真实音频</p>
                \(mode == "mobile" ? "<p>官方分享域名本机夹具</p>" : "")
                \(mode == "blocked" ? "<a href='https://blocked.example.test/'>测试受限导航</a>" : "")
                </body></html>
                """, baseURL: documentURL)
            })
        }
        #endif
        return NetEaseListeningSession()
    }
}

private struct ListeningWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ uiView: WKWebView, coordinator: ()) {
        uiView.pauseAllMediaPlayback(completionHandler: nil)
        uiView.stopLoading()
    }
}
