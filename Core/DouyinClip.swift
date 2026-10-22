import Foundation

nonisolated struct DouyinClip: Equatable, Sendable {
    let videoID: String
    init?(videoID: String) {
        guard (16...20).contains(videoID.utf8.count), videoID.utf8.first != 48, videoID.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        self.videoID = videoID
    }
    var watchURL: URL { URL(string: "https://www.douyin.com/video/" + videoID)! }
    var playerURL: URL { URL(string: "https://open.douyin.com/player/video?vid=" + videoID + "&autoplay=0")! }
}

nonisolated enum DouyinEmbedError: Error, Equatable { case unavailable, invalidResponse }

private nonisolated struct DouyinEmbedResponse: Decodable {
    let err_no: Int
    let data: Payload?
    struct Payload: Decodable { let iframe_code: String? }
}

/// Called only after a user gesture and fresh Station Cat publication validation.
/// The official API returns HTML, but none of that HTML is executed or persisted.
actor DouyinEmbedAPI {
    private let transport: any HTTPTransport
    init(transport: any HTTPTransport) { self.transport = transport }
    func verify(_ clip: DouyinClip) async throws {
        let url = URL(string: "https://open.douyin.com/api/douyin/v1/video/get_iframe_by_video?video_id=" + clip.videoID)!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = "GET"; request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response = try await transport.send(request)
        try Task.checkCancellation()
        guard response.status == 200, response.finalURL == url, response.data.count <= 65_536,
              response.headers.first(where: { $0.key.lowercased() == "content-type" })?.value.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() == "application/json",
              let object = try? JSONDecoder().decode(DouyinEmbedResponse.self, from: response.data) else { throw DouyinEmbedError.invalidResponse }
        if object.err_no == 28003004 { throw DouyinEmbedError.unavailable }
        guard object.err_no == 0, let html = object.data?.iframe_code,
              html.utf8.count <= 8192 else { throw DouyinEmbedError.invalidResponse }
        let expression = try NSRegularExpression(pattern: #"\bsrc\s*=\s*(["'])(.*?)\1"#, options: [.caseInsensitive])
        let matches = expression.matches(in: html, range: NSRange(html.startIndex..., in: html))
        guard matches.count == 1, let range = Range(matches[0].range(at: 2), in: html) else { throw DouyinEmbedError.invalidResponse }
        let source = String(html[range]).replacingOccurrences(of: "&amp;", with: "&")
        guard source == clip.playerURL.absoluteString else { throw DouyinEmbedError.invalidResponse }
    }
}

nonisolated enum DouyinEmbedDocument {
    static let origin = URL(string: "https://org.stationcat.music")!
    static func isWrapperNavigation(_ url: URL) -> Bool {
        if url.absoluteString == "about:blank" { return true }
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        // WebKit normalizes loadHTMLString's base URL to a slash-terminated
        // root. Accept only that equivalent root, never general same-host pages.
        return parts.scheme == origin.scheme && parts.host == origin.host &&
            parts.user == nil && parts.password == nil && parts.port == nil &&
            ["", "/"].contains(parts.percentEncodedPath) && parts.query == nil && parts.fragment == nil
    }
    static func html(_ clip: DouyinClip, token: String) -> String {
        guard UUID(uuidString: token) != nil else { return "" }
        // Only a validated numeric ID and an internal UUID enter HTML. The
        // iframe load event means document loaded, NOT verified video playback.
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta name="referrer" content="strict-origin">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'nonce-\(token)'; frame-src https://open.douyin.com; style-src 'unsafe-inline'; base-uri 'none'">
        <style>html,body{margin:0;width:100%;height:100%;background:#060a16;overflow:hidden}iframe{width:100%;height:100%;border:0}</style>
        </head><body><iframe id="player" title="Douyin" allow="fullscreen" allowfullscreen></iframe>
        <script nonce="\(token)">
        const player=document.getElementById('player');
        player.addEventListener('load',()=>window.webkit.messageHandlers.douyin.postMessage({token:'\(token)',event:'loaded'}));
        player.src='\(clip.playerURL.absoluteString)';
        function stopClip(){player.remove();}
        window.addEventListener('pagehide',stopClip);
        </script></body></html>
        """
    }
}
