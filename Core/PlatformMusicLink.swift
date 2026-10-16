import Foundation

/// Attribution is navigation context only: never credentials, an outbound URL,
/// an analytics event, or permission to play. Canonical URLs omit it entirely.
nonisolated struct PlatformMusicLink: Equatable, Sendable {
    let id: String?
    let slug: String?
    let canonicalURL: URL
    let attribution: [String: String]

    init?(_ url: URL, origin: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host == origin.host,
              parts.port == nil, parts.user == nil, parts.password == nil, parts.fragment == nil,
              parts.percentEncodedPath == parts.path,
              (parts.percentEncodedQuery?.utf8.count ?? 0) <= 640 else { return nil }
        let allowed = Set(["utm_source", "utm_medium", "utm_campaign", "utm_content"])
        var attribution: [String: String] = [:], trackID: String?
        for item in parts.queryItems ?? [] {
            if item.name == "track", trackID == nil, let value = item.value, UUID(uuidString: value) != nil {
                trackID = value.lowercased()
            } else {
                guard allowed.contains(item.name), attribution[item.name] == nil,
                      let value = item.value, (1...128).contains(value.utf8.count),
                      value.range(of: "^[A-Za-z0-9._~-]+$", options: .regularExpression) != nil else { return nil }
                attribution[item.name] = value
            }
        }
        let prefixes = ["", "/zh-hant", "/zh-hans", "/en", "/ja"]
        var canonical = parts
        canonical.query = nil
        if prefixes.contains(where: { parts.path == $0 + "/music" || parts.path == $0 + "/music/" }) {
            guard let trackID else { return nil }
            canonical.queryItems = [.init(name: "track", value: trackID)]
            self.id = trackID; self.slug = nil
        } else {
            guard trackID == nil, let prefix = prefixes.map({ $0 + "/music/tracks/" }).first(where: { parts.path.hasPrefix($0) }) else { return nil }
            let suffix = String(parts.path.dropFirst(prefix.count))
            let slug = suffix.hasSuffix("/") ? String(suffix.dropLast()) : suffix
            guard (1...100).contains(slug.utf8.count), slug.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil else { return nil }
            canonical.path = prefix + slug + "/"
            self.id = nil; self.slug = slug
        }
        guard let canonicalURL = canonical.url else { return nil }
        self.canonicalURL = canonicalURL; self.attribution = attribution
    }
}
