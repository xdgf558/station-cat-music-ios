import Foundation

/// Historical embed fixtures never activate a shipping listening browser.
nonisolated struct ExperimentalListeningConfiguration {
    let enabled: Bool

    init(info: [String: Any]) {
        enabled = ThirdPartyPlaybackPolicy.allowsEmbedding(info: info) &&
            info["StationNetEaseBrowserExperimentEnabled"] as? String == "YES"
    }

    static func enabledForCurrentEnvironment() -> Bool {
        #if DEBUG && targetEnvironment(simulator)
        if ThirdPartyPlaybackPolicy.embeddingAllowed,
           ProcessInfo.processInfo.arguments.contains("--platform-music-fixture"),
           ["ready", "blocked", "mobile", "initial-blocked"].contains(ProcessInfo.processInfo.environment["STATION_NETEASE_BROWSER_FIXTURE"] ?? "") {
            return true
        }
        #endif
        return Self(info: Bundle.main.infoDictionary ?? [:]).enabled
    }
}
