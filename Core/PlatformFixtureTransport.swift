import Foundation

/// Bundled Mock metadata. There is no network fallback or audio source.
actor PlatformFixtureTransport: HTTPTransport {
    private let data: Data
    private let delay: Duration
    private let status: Int
    private let detailFailure: Bool
    private var detailCounts: [String: Int] = [:]
    init(data: Data, delay: Duration = .zero, status: Int = 200, detailFailure: Bool = false) {
        self.data = data; self.delay = delay; self.status = status; self.detailFailure = detailFailure
    }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        guard request.httpMethod == "GET", let url = request.url,
              url.host == PlatformMusicAPI.productionOrigin.host,
              request.value(forHTTPHeaderField: "Authorization") == nil,
              request.value(forHTTPHeaderField: "Cookie") == nil,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw APIError.invalidRequest }
        try await Task.sleep(for: delay); try Task.checkCancellation()
        let prefix = PlatformMusicAPI.contentPath
        let isDetail = url.path.hasPrefix(prefix + "/tracks/")
        if isDetail { detailCounts[url.path, default: 0] += 1 }
        let body: Any?
        if url.path == prefix + "/tracks" { body = object["catalog"] }
        else if url.path == prefix + "/home" { body = object["home"] }
        else if isDetail { body = (object["details"] as? [String: Any])?[url.lastPathComponent] }
        else { throw APIError.invalidRequest }
        guard let body else { throw APIError.invalidRequest }
        let locale = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "locale" })?.value ?? "en"
        let content = patch(body, locale: locale)
        // The homepage's initial detail projection succeeds. The first user
        // opening fails once, so the UI exercises a real retry without networking.
        return HTTPResult(status: detailFailure && isDetail && detailCounts[url.path] == 2 ? 503 : status,
            data: try JSONSerialization.data(withJSONObject: content), headers: ["content-type": "application/json"], finalURL: url)
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
