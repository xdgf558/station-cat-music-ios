import Foundation

/// Explicit candidate opt-in. APPSTORE and TESTFLIGHT are distinct build markers,
/// not runtime proof of Apple's distribution route. Release validation requires
/// the separately approved candidate mode; ordinary packages remain disabled.
nonisolated struct ExperimentalListeningConfiguration {
    let enabled: Bool

    init(info: [String: Any]) {
        let environment = info["StationEnvironment"] as? String
        let flag = info["StationNetEaseBrowserExperimentEnabled"] as? String
        if ["development", "staging"].contains(environment ?? "") {
            enabled = flag == "YES"
            return
        }
        enabled = environment == "production" && ["TESTFLIGHT", "APPSTORE"].contains(flag ?? "") &&
            info["CFBundleIdentifier"] as? String == "org.stationcat.music" &&
            info["StationPublicReleasesEnabled"] as? String == "YES" &&
            info["StationPublicReleaseOrigin"] as? String == ProductionActivationProfile.origin &&
            ["StationNativeAuthEnabled", "StationNativeMusicEnabled", "StationPersonalSyncEnabled",
             "StationProductionActivationEnabled"].allSatisfy { info[$0] as? String == "NO" }
    }

    static func enabledForCurrentEnvironment() -> Bool {
        #if DEBUG && targetEnvironment(simulator)
        if Bundle.main.object(forInfoDictionaryKey: "StationEnvironment") as? String == "mock",
           ProcessInfo.processInfo.arguments.contains("--platform-music-fixture"),
           ["ready", "blocked", "mobile", "initial-blocked"].contains(ProcessInfo.processInfo.environment["STATION_NETEASE_BROWSER_FIXTURE"] ?? "") {
            return true
        }
        #endif
        return Self(info: Bundle.main.infoDictionary ?? [:]).enabled
    }
}
