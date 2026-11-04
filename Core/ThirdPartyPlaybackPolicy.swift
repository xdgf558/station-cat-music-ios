import Foundation

/// Shipping apps only hand off official links. Old embeds are isolated Mock tests.
nonisolated enum ThirdPartyPlaybackPolicy {
    static func allowsEmbedding(info: [String: Any]) -> Bool {
        #if DEBUG && targetEnvironment(simulator)
        return info["StationEnvironment"] as? String == "mock" &&
            ProcessInfo.processInfo.environment["STATION_EXTERNAL_ONLY_FIXTURE"] != "YES"
        #else
        return false
        #endif
    }

    static var embeddingAllowed: Bool { allowsEmbedding(info: Bundle.main.infoDictionary ?? [:]) }
}
