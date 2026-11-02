import XCTest
@testable import StationCatMusic

final class ExperimentalListeningConfigurationTests: XCTestCase {
    private let flag = "StationNetEaseBrowserExperimentEnabled"

    func testOnlyExplicitDevelopmentAndStagingOptInCanEnableExperiment() {
        let invalidValues: [Any] = ["NO", "TESTFLIGHT", "APPSTORE", "yes", "true", "1", true, 1, " YES ", ""]
        for environment in ["development", "staging"] {
            XCTAssertTrue(ExperimentalListeningConfiguration(info: [
                "StationEnvironment": environment, flag: "YES"
            ]).enabled, environment)
            for value in invalidValues {
                XCTAssertFalse(ExperimentalListeningConfiguration(info: [
                    "StationEnvironment": environment, flag: value
                ]).enabled, "\(environment): \(value)")
            }
            XCTAssertFalse(ExperimentalListeningConfiguration(info: ["StationEnvironment": environment]).enabled)
        }
    }

    private var testflightInfo: [String: Any] {
        ["StationEnvironment": "production", flag: "TESTFLIGHT",
         "CFBundleIdentifier": "org.stationcat.music",
         "StationPublicReleasesEnabled": "YES", "StationPublicReleaseOrigin": ProductionActivationProfile.origin,
         "StationNativeAuthEnabled": "NO", "StationNativeMusicEnabled": "NO",
         "StationPersonalSyncEnabled": "NO", "StationProductionActivationEnabled": "NO"]
    }

    func testExplicitTestFlightCandidateRequiresPublicOnlyProductionIdentity() {
        XCTAssertTrue(ExperimentalListeningConfiguration(info: testflightInfo).enabled)
        let invalid: [(String, Any)] = [
            ("StationEnvironment", "mock"), ("StationEnvironment", "staging"),
            ("StationEnvironment", "development"), ("StationEnvironment", "Production"),
            (flag, "YES"), (flag, "NO"), (flag, "testflight"), (flag, "TESTFLIGHT "), (flag, true),
            ("CFBundleIdentifier", "org.stationcat.music.staging"), ("CFBundleIdentifier", "org.stationcat.music "),
            ("StationPublicReleasesEnabled", "NO"), ("StationPublicReleasesEnabled", true),
            ("StationPublicReleaseOrigin", ProductionActivationProfile.origin + "/"),
            ("StationPublicReleaseOrigin", "https://unrelated.invalid"),
        ]
        for (key, value) in invalid {
            var info = testflightInfo; info[key] = value
            XCTAssertFalse(ExperimentalListeningConfiguration(info: info).enabled, "\(key): \(value)")
        }
        for key in testflightInfo.keys {
            var info = testflightInfo; info.removeValue(forKey: key)
            XCTAssertFalse(ExperimentalListeningConfiguration(info: info).enabled, "missing \(key)")
        }
    }

    func testExplicitAppStoreCandidateRequiresPublicOnlyProductionIdentity() {
        var base = testflightInfo; base[flag] = "APPSTORE"
        XCTAssertTrue(ExperimentalListeningConfiguration(info: base).enabled)
        let invalid: [(String, Any)] = [
            ("StationEnvironment", "mock"), ("StationEnvironment", "staging"),
            ("StationEnvironment", "development"), ("StationEnvironment", "Production"),
            (flag, "YES"), (flag, "NO"), (flag, "appstore"), (flag, "APPSTORE "),
            (flag, "APP_STORE"), (flag, true), (flag, 1),
            ("CFBundleIdentifier", "org.stationcat.music.staging"), ("CFBundleIdentifier", "org.stationcat.music "),
            ("StationPublicReleasesEnabled", "NO"), ("StationPublicReleasesEnabled", true),
            ("StationPublicReleaseOrigin", ProductionActivationProfile.origin + "/"),
            ("StationPublicReleaseOrigin", "https://unrelated.invalid"),
        ]
        for (key, value) in invalid {
            var info = base; info[key] = value
            XCTAssertFalse(ExperimentalListeningConfiguration(info: info).enabled, "\(key): \(value)")
        }
        for key in base.keys {
            var info = base; info.removeValue(forKey: key)
            XCTAssertFalse(ExperimentalListeningConfiguration(info: info).enabled, "missing \(key)")
        }
    }

    func testDistributionCandidatesCannotEnableAlongsideNativeServices() {
        for marker in ["TESTFLIGHT", "APPSTORE"] {
            for key in ["StationNativeAuthEnabled", "StationNativeMusicEnabled", "StationPersonalSyncEnabled",
                        "StationProductionActivationEnabled"] {
                for value: Any in ["YES", "no", "NO ", false, 0] {
                    var info = testflightInfo; info[flag] = marker; info[key] = value
                    XCTAssertFalse(ExperimentalListeningConfiguration(info: info).enabled, "\(marker): \(key): \(value)")
                }
            }
        }
    }

    func testProductionAndMockRemainClosedEvenWithExperimentAndOtherActivationFlags() {
        for environment in ["production", "mock"] {
            for fixture in ["ready", "blocked"] {
                let info: [String: Any] = [
                    "StationEnvironment": environment,
                    flag: "YES",
                    "StationPublicReleasesEnabled": "YES",
                    "StationPublicReleaseOrigin": "https://wwwstationcat.org",
                    "StationPublicAppLinksEnabled": "YES",
                    "StationNativeMusicEnabled": "YES",
                    "StationProductionActivationEnabled": "YES",
                    // Fixture-like bundle values are not an opt-in channel.
                    "STATION_NETEASE_BROWSER_FIXTURE": fixture,
                    "--platform-music-fixture": true
                ]
                XCTAssertFalse(ExperimentalListeningConfiguration(info: info).enabled, "\(environment): \(fixture)")
            }
        }
    }

    func testMissingUnknownOrMalformedEnvironmentCannotEnableExperiment() {
        XCTAssertFalse(ExperimentalListeningConfiguration(info: [:]).enabled)
        XCTAssertFalse(ExperimentalListeningConfiguration(info: [flag: "YES"]).enabled)
        let invalidEnvironments: [Any] = ["Development", "STAGING", "production ", "test", "", true, 1]
        for environment in invalidEnvironments {
            XCTAssertFalse(ExperimentalListeningConfiguration(info: [
                "StationEnvironment": environment, flag: "YES"
            ]).enabled, "\(environment)")
        }
    }
}
