import Foundation

/// A build-time upper bound, never expanded by a server capability response.
nonisolated struct ProductionActivationProfile: Sendable {
    struct Capabilities: Decodable, Sendable {
        let nativeAuthentication: Bool
        let musicCatalog: Bool
        let musicPlayback: Bool
        let personalSync: Bool
        let accountDeletion: Bool
    }
    private struct Document: Decodable {
        let schemaVersion: Int
        let profileId: String
        let enabled: Bool
        let environment: String
        let apiOrigin: String
        let webOrigin: String
        let callback: String
        let applicationIdentifier: String
        let capabilities: Capabilities
    }
    let apiOrigin: String
    let webOrigin: String
    let callback: String
    let applicationIdentifier: String
    let capabilities: Capabilities

    static let identifier = "station-native-production-v1"
    static let origin = "https://wwwstationcat.org"
    static let bundleIdentifier = "org.stationcat.music"
    static let applicationIdentifier = "2AM5S7BM2N.org.stationcat.music"

    init(data: Data, bundleIdentifier: String) throws {
        let fields = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let capabilityFields = fields?["capabilities"] as? [String: Any]
        guard Set(fields?.keys.map { $0 } ?? []) == Set(["schemaVersion", "profileId", "enabled", "environment", "apiOrigin", "webOrigin", "callback", "applicationIdentifier", "capabilities"]),
              Set(capabilityFields?.keys.map { $0 } ?? []) == Set(["nativeAuthentication", "musicCatalog", "musicPlayback", "personalSync", "accountDeletion"]) else { throw APIError.networkDisabled }
        let value = try JSONDecoder().decode(Document.self, from: data)
        guard value.schemaVersion == 1, value.profileId == Self.identifier, value.enabled,
              value.environment == AppEnvironment.production.rawValue,
              bundleIdentifier == Self.bundleIdentifier, value.applicationIdentifier == Self.applicationIdentifier,
              value.apiOrigin == Self.origin, value.webOrigin == Self.origin,
              value.callback == Self.origin + "/auth/mobile/callback",
              value.capabilities.nativeAuthentication,
              value.capabilities.musicCatalog == value.capabilities.musicPlayback,
              !value.capabilities.personalSync || value.capabilities.musicPlayback,
              !value.capabilities.accountDeletion else { throw APIError.networkDisabled }
        apiOrigin = value.apiOrigin; webOrigin = value.webOrigin; callback = value.callback
        applicationIdentifier = value.applicationIdentifier; capabilities = value.capabilities
    }
}

/// Parse the installed app's configuration once, before creating any real transport.
nonisolated struct NativeRuntimeConfiguration: Sendable {
    let environment: AppEnvironment
    let authentication: NativeAuthConfiguration?
    let musicEnabled: Bool
    let personalSyncEnabled: Bool
    let musicWebOrigin: URL?

    init(info: [String: Any]) {
        let recognizedEnvironment = (info["StationEnvironment"] as? String).flatMap(AppEnvironment.init(rawValue:))
        environment = recognizedEnvironment ?? .production
        var configuration: NativeAuthConfiguration?
        var webOrigin: URL?
        var music = false
        var sync = false
        if let recognizedEnvironment, recognizedEnvironment != .mock {
            let authRequested = info["StationNativeAuthEnabled"] as? String == "YES"
            let musicRequested = info["StationNativeMusicEnabled"] as? String == "YES"
            let syncRequested = info["StationPersonalSyncEnabled"] as? String == "YES"
            // An invalid dependency disables the entire native stack.
            if authRequested, !syncRequested || musicRequested,
               let rawOrigin = info["StationNativeAuthOrigin"] as? String,
               let origin = URL(string: rawOrigin) {
                var production: ProductionActivationProfile?
                if recognizedEnvironment == .production,
                   info["StationProductionActivationEnabled"] as? String == "YES",
                   let encoded = info["StationProductionActivationProfile"] as? String,
                   let data = Data(base64Encoded: encoded),
                   let bundle = info["CFBundleIdentifier"] as? String {
                    production = try? ProductionActivationProfile(data: data, bundleIdentifier: bundle)
                }
                let rawWebOrigin = info["StationMusicWebOrigin"] as? String ?? ""
                let productionMatches = recognizedEnvironment != .production ||
                    (production != nil && rawOrigin == production?.apiOrigin && rawWebOrigin == production?.webOrigin &&
                     (!musicRequested || production?.capabilities.musicPlayback == true) &&
                     (!syncRequested || production?.capabilities.personalSync == true))
                if productionMatches {
                    configuration = try? NativeAuthConfiguration(environment: recognizedEnvironment, origin: origin,
                        explicitlyEnabled: true, productionActivation: production)
                    if configuration != nil {
                        music = musicRequested
                        sync = syncRequested
                        webOrigin = MusicLink.webOrigin(URL(string: rawWebOrigin))
                    }
                }
            }
        }
        authentication = configuration
        musicEnabled = music
        personalSyncEnabled = sync
        musicWebOrigin = webOrigin
    }
}
