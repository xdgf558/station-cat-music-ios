import Foundation

/// Bundled Mock metadata. There is no network fallback or audio source.
actor PlatformFixtureTransport: HTTPTransport {
    private let data: Data
    private let delay: Duration
    private let status: Int
    private let detailFailure: Bool
    private let contentFailure: Bool
    private var detailCounts: [String: Int] = [:]
    init(data: Data, delay: Duration = .zero, status: Int = 200, detailFailure: Bool = false, contentFailure: Bool = false) {
        self.data = data; self.delay = delay; self.status = status; self.detailFailure = detailFailure; self.contentFailure = contentFailure
    }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        guard request.httpMethod == "GET", let url = request.url,
              url.host == PlatformMusicAPI.productionOrigin.host,
              request.value(forHTTPHeaderField: "Authorization") == nil,
              request.value(forHTTPHeaderField: "Cookie") == nil,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw APIError.invalidRequest }
        try await Task.sleep(for: delay); try Task.checkCancellation()
        let prefix = PlatformMusicAPI.contentPath
        let isBookmark = url.path.hasSuffix("/bookmark")
        let isClips = url.path.hasSuffix("/clips")
        let isDetail = url.path.hasPrefix(prefix + "/tracks/") && !isBookmark && !isClips
        if url.path.hasPrefix(prefix + "/assets/"), let lyrics = (object["lyrics"] as? [String: String])?[url.lastPathComponent] {
            detailCounts[url.path, default: 0] += 1
            return HTTPResult(status: contentFailure && detailCounts[url.path] == 1 ? 503 : status,
                data: Data(lyrics.utf8), headers: ["content-type":"text/plain; charset=utf-8", "cache-control":"no-store"], finalURL: url)
        }
        if isDetail { detailCounts[url.path, default: 0] += 1 }
        let body: Any?
        if url.path == prefix + "/tracks" { body = object["catalog"] }
        else if url.path == prefix + "/home" { body = object["home"] }
        else if isClips { body = (object["clips"] as? [String: Any])?[url.deletingLastPathComponent().lastPathComponent] ?? ["schemaVersion":1, "locale":"en", "items":[], "nextCursor":NSNull()] }
        else if isBookmark,
            let detail = (object["details"] as? [String: Any])?[url.deletingLastPathComponent().lastPathComponent] as? [String: Any],
            let track = detail["track"] as? [String: Any] {
            body = ["schemaVersion":1, "locale":"en", "bookmark": track.filter { ["id","slug","title","artist","revision"].contains($0.key) }]
        }
        else if isDetail { body = (object["details"] as? [String: Any])?[url.lastPathComponent] }
        else { throw APIError.invalidRequest }
        guard let body else { throw APIError.invalidRequest }
        let locale = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "locale" })?.value ?? "en"
        let content = patch(body, locale: locale)
        var headers = ["content-type":"application/json"]
        if isBookmark {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
            headers["Cache-Control"] = "private, max-age=86400, must-revalidate"
            headers["Date"] = formatter.string(from: Date())
        }
        // The homepage's initial detail projection succeeds. The first user
        // opening fails once, so the UI exercises a real retry without networking.
        return HTTPResult(status: detailFailure && isDetail && detailCounts[url.path] == 2 ? 503 : status,
            data: try JSONSerialization.data(withJSONObject: content), headers: headers, finalURL: url)
    }
    private func patch(_ value: Any, locale: String) -> Any {
        if let values = value as? [Any] { return values.map { patch($0, locale: locale) } }
        guard let dictionary = value as? [String: Any] else { return value }
        var result = dictionary.mapValues { patch($0, locale: locale) }
        if dictionary["locale"] != nil { result["locale"] = locale }
        if let raw = dictionary["href"] as? String, let marker = raw.range(of: "/music/tracks/") {
            let prefix = locale == "zh-Hant" ? "" : "/" + locale.lowercased()
            result["href"] = prefix + String(raw[marker.lowerBound...])
        }
        return result
    }
}
