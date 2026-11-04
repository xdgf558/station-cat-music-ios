import XCTest
@testable import StationCatMusic

final class ThirdPartyPlaybackPolicyTests: XCTestCase {
    func testProductionCannotEnableEmbeddingWithAnyHistoricalDistributionMarker() {
        for marker in ["NO", "YES", "TESTFLIGHT", "APPSTORE", "EMBEDDED", "EXTERNAL_ONLY", ""] {
            let info: [String: Any] = ["StationEnvironment": "production",
                                     "StationThirdPartyPlaybackPolicy": marker,
                                     "StationNetEaseBrowserExperimentEnabled": marker,
                                     "CFBundleIdentifier": "org.stationcat.music",
                                     "StationPublicReleasesEnabled": "YES",
                                     "StationPublicReleaseOrigin": "https://wwwstationcat.org"]
            XCTAssertFalse(ThirdPartyPlaybackPolicy.allowsEmbedding(info: info), marker)
            XCTAssertFalse(ExperimentalListeningConfiguration(info: info).enabled, marker)
        }
    }

    func testUnconfiguredAndNonMockEnvironmentsStayExternalOnly() {
        XCTAssertFalse(ThirdPartyPlaybackPolicy.allowsEmbedding(info: [:]))
        for environment in ["development", "staging", "Production", "unknown", ""] {
            XCTAssertFalse(ThirdPartyPlaybackPolicy.allowsEmbedding(info: ["StationEnvironment": environment]))
        }
    }
}
