import XCTest
@testable import StationCatMusic

final class ExperimentalListeningConfigurationTests: XCTestCase {
    func testShippingAndUnknownEnvironmentsCannotRestoreHistoricalEmbedModes() {
        let values: [Any] = ["NO", "YES", "TESTFLIGHT", "APPSTORE", "yes", true, 1, ""]
        for environment in ["production", "staging", "development", "unknown", ""] {
            for value in values {
                let info: [String: Any] = ["StationEnvironment": environment,
                    "StationNetEaseBrowserExperimentEnabled": value,
                    "StationPublicReleasesEnabled": "YES",
                    "StationPublicReleaseOrigin": "https://wwwstationcat.org",
                    "CFBundleIdentifier": "org.stationcat.music",
                    "StationNativeAuthEnabled": "NO", "StationNativeMusicEnabled": "NO",
                    "StationPersonalSyncEnabled": "NO", "StationProductionActivationEnabled": "NO"]
                XCTAssertFalse(ExperimentalListeningConfiguration(info: info).enabled)
            }
        }
        XCTAssertFalse(ExperimentalListeningConfiguration(info: [:]).enabled)
    }
}
