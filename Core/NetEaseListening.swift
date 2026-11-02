import Foundation

/// An approved song link, not a generic browser address. The original link is
/// retained for an explicit system handoff; document redirects never replace it.
nonisolated struct NetEaseListeningRequest: Equatable, Identifiable, Sendable {
    let trackID: String
    let link: PlatformLink
    let pageURL: URL
    var id: String { trackID + ":" + link.id }
    var originalURL: URL { link.url }

    init?(link: PlatformLink, track: Track) {
        guard link.provider == .netease, track.release?.platforms.contains(link) == true,
              let canonical = PlatformMusicAPI.platformURL(link.url.absoluteString, provider: .netease),
              let parts = URLComponents(url: canonical, resolvingAgainstBaseURL: false),
              parts.host == "music.163.com", parts.percentEncodedPath == "/song",
              parts.percentEncodedQuery?.range(of: "^id=[1-9][0-9]{0,19}$", options: .regularExpression) != nil,
              parts.fragment == nil else { return nil }
        self.trackID = track.id
        self.link = link
        self.pageURL = canonical
    }

    func matches(_ detail: PlatformTrackDetail) -> Bool {
        detail.track.id == trackID && NetEaseListeningRequest(link: link, track: detail.track) == self
    }
}

/// Restricts documents, including nested frames and redirected responses. Media
/// subresources remain the official page's responsibility; no audio URL is read.
nonisolated enum NetEaseListeningNavigationPolicy {
    enum Target { case mainFrame, subframe, newWindow }
    private static let documentHosts: Set<String> = ["music.163.com", "y.music.163.com"]

    static func allows(_ url: URL, target: Target) -> Bool {
        guard target != .newWindow else { return false }
        if target == .subframe && url.absoluteString == "about:blank" { return true }
        let raw = url.absoluteString
        guard raw.count <= 8192, !raw.contains("\\"),
              !raw.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", let host = parts.host, documentHosts.contains(host),
              parts.percentEncodedHost == host, parts.port == nil,
              parts.user == nil, parts.password == nil else { return false }
        return true
    }

    /// Ephemeral troubleshooting text only. Never includes paths, query values,
    /// fragments, user info, page contents or arbitrary error descriptions.
    static func diagnostic(_ url: URL?, target: Target, response: Bool, download: Bool = false) -> String {
        let stage = response ? "response" : "action"
        let frame = target == .mainFrame ? "main" : target == .subframe ? "child" : "popup"
        let parts = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        let reason = download ? "download" : parts?.scheme == "https" ? "host" : "scheme"
        var result = stage + "/" + frame + "/" + reason
        if let parts, ["http", "https"].contains(parts.scheme ?? ""),
           parts.user == nil, parts.password == nil, let host = parts.host,
           parts.percentEncodedHost == host, host.utf8.count <= 253,
           !host.isEmpty, host.unicodeScalars.allSatisfy({ $0.isASCII }),
           host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ label in
               label.range(of: "^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$", options: .regularExpression) != nil
           }) {
            result += " · " + host.lowercased()
        }
        return result
    }
}
