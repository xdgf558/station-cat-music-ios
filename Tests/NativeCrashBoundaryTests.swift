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
    func testDiagnosticCategoriesNeverSerializeSensitiveErrorData() throws {
        let secret = "synthetic-private-value-must-not-be-logged"
        let errors: [(Error, String)] = [
            (URLError(.timedOut, userInfo: [NSURLErrorFailingURLErrorKey: URL(string: "https://example.invalid/" + secret)!]), "url_error:code=-1001"),
            (SecureStoreError.osStatus(-34018), "keychain_status:code=-34018"),
            (SecureStoreError.protectedDataUnavailable, "keychain_locked"),
            (NativeFailure(code: secret, status: 503), "native_rejected:code=503"),
            (APIError.rejected(500), "http_rejected:code=500"),
            (ProbeFailure.failed(secret), "assertion_failed"),
            (DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: secret)), "decode_failed"),
            (NSError(domain: secret, code: 123, userInfo: [NSLocalizedDescriptionKey: secret]), "unknown")
        ]
        for (error, expected) in errors {
            let diagnostic = ProbeDiagnostic.capture(error, phase: .seedRequest)
            XCTAssertEqual(diagnostic.fields, "step=seedRequest:category=" + expected)
            XCTAssertFalse(diagnostic.fields.contains(secret))
        }
    }
    func testNestedDiagnosticsKeepExactFailingSubstage() throws {
        let original = ProbeDiagnostic.capture(URLError(.timedOut), phase: .evidenceRequest)
        let outer = ProbeDiagnostic.capture(original, phase: .authRestore)
        XCTAssertEqual(outer.fields, "step=evidenceRequest:category=url_error:code=-1001")
    }

}
