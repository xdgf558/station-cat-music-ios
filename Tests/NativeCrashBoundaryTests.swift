import XCTest
@testable import StationCatMusic

@MainActor final class NativeCrashBoundaryTests: XCTestCase {
    func testCrashAtRefreshBoundary() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["M2_BOUNDARY_MODE"] == "CRASH", "Dedicated isolated process probe only")
        try await NativeCrashScenario().testCrashAtRefreshBoundary()
    }
    func testRecoverOriginalOperation() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["M2_BOUNDARY_MODE"] == "RECOVER", "Dedicated isolated process probe only")
        try await NativeCrashScenario().testRecoverOriginalOperation()
    }
}
