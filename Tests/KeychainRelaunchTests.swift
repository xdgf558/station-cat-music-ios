import XCTest
@testable import StationCatMusic

@MainActor final class KeychainRelaunchTests: XCTestCase {
    private let service = "org.stationcat.music.dev.m1.relaunch-fixture"
    func testAWriteDurableFixture() async throws {
        let store = KeychainStore(service: service)
        try await store.remove("relaunch")
        try await store.write(Data("M1_SYNTHETIC_RELAUNCH_FIXTURE".utf8), key: "relaunch")
        let value = try await store.read("relaunch"); XCTAssertNotNil(value)
    }
    // scripts/verify_keychain_relaunch.sh executes this in a separate xcodebuild/test-host process.
    func testBReadAndRemoveFixture() async throws {
        let store = KeychainStore(service: service)
        let value = try await store.read("relaunch"); XCTAssertEqual(value, Data("M1_SYNTHETIC_RELAUNCH_FIXTURE".utf8))
        try await store.remove("relaunch")
    }
}
