import Foundation

/// Public release metadata has its own opt-in. It cannot activate native
/// authentication, playback, sync, deletion or Apple associated domains.
nonisolated struct PlatformConfiguration: Sendable {
    let origin: URL?
    let legacyOfflineOrigin: URL?
    // A storage namespace only, never a network destination in platform mode.
    static let previousStagingOrigin = URL(string: "https://station-cat-music-r2.yehao1105.workers.dev")!
    init(info: [String: Any]) {
        let environment = (info["StationEnvironment"] as? String).flatMap(AppEnvironment.init(rawValue:))
        legacyOfflineOrigin = environment != nil && environment != .mock &&
            info["StationLegacyOfflineOrigin"] as? String == Self.previousStagingOrigin.absoluteString ? Self.previousStagingOrigin : nil
        guard let rawEnvironment = info["StationEnvironment"] as? String,
              let environment = AppEnvironment(rawValue: rawEnvironment), environment != .mock,
              info["StationPublicReleasesEnabled"] as? String == "YES",
              let raw = info["StationPublicReleaseOrigin"] as? String,
              raw == ProductionActivationProfile.origin,
              let url = URL(string: raw) else { origin = nil; return }
        origin = url
    }
}

/// The old cache is available for local inspection/removal only.
nonisolated struct LegacyOfflineManagementTransport: MediaHTTPTransport {
    func send(_ request: URLRequest) async throws -> MediaHTTPResult { throw APIError.networkDisabled }
}

/// Small list rows use the website's existing 192px derivative. Large cards
/// and details keep the display derivative; native media URLs are untouched.
nonisolated enum PlatformArtwork {
    static func url(_ url: URL, thumbnail: Bool) -> URL {
        guard thumbnail, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host == PlatformMusicAPI.productionOrigin.host,
              parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil,
              let query = parts.queryItems,
              query.count == 1 || query.count == 2,
              query.filter({ $0.name == "size" }).count == 1,
              query.first(where: { $0.name == "size" })?.value == "display",
              query.allSatisfy({ $0.name == "size" || ($0.name == "v" &&
                $0.value?.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil) }),
              parts.percentEncodedPath.range(of: "^/api/station/content/assets/[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$", options: .regularExpression) != nil else { return url }
        parts.queryItems = [.init(name: "size", value: "card")] + query.filter { $0.name == "v" }
        return parts.url ?? url
    }
}
