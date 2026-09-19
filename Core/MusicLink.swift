import Foundation

/// Resolution only. A link never carries authorization or starts audio.
nonisolated enum MusicLink: Equatable, Sendable {
    case track(String), collection(String)
    static func webOrigin(_ value: URL?) -> URL? {
        guard let value, let c = URLComponents(url: value, resolvingAgainstBaseURL: false), c.scheme == "https",
              let host = c.host, !host.isEmpty, c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              c.port == nil || c.port == 443, c.path.isEmpty || c.path == "/" else { return nil }
        return value
    }
    init?(_ url: URL, allowedHost: String) {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.scheme == "https",
              c.host == allowedHost, c.user == nil, c.password == nil, c.fragment == nil,
              c.port == nil || c.port == 443, ["/music/", "/music"].contains(c.path),
              let items = c.queryItems, items.count == 1, let value = items[0].value else { return nil }
        if items[0].name == "track", UUID(uuidString: value) != nil { self = .track(value) }
        else if items[0].name == "collection", value.range(of: "^[a-z0-9-]{1,100}$", options: .regularExpression) != nil { self = .collection(value) }
        else { return nil }
    }
}
