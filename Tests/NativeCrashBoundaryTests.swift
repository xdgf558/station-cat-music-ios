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

private actor EvidenceSequence {
    var calls = 0
    let failures: [ProbeDiagnostic]
    init(_ failures: [ProbeDiagnostic]) { self.failures = failures }
    func read() throws -> Bool {
        let index = calls; calls += 1
        if index < failures.count { throw failures[index] }
        return true
    }
}

extension NativeCrashBoundaryTests {
    func testHeldPollingRecoversFromEvidence500AndTimeoutWithoutRepeatingMutation() async throws {
        let reader = EvidenceSequence([
            .capture(APIError.rejected(500), phase: .evidenceDecode),
            .capture(URLError(.timedOut), phase: .evidenceRequest)
        ])
        try await ProbeHeldPolling.wait(timeout: .seconds(1), interval: .milliseconds(1), read: {
            try await reader.read()
        }, onRetry: {})
        let calls = await reader.calls
        XCTAssertEqual(calls, 3)
    }
    func testHeldPollingRejectsNonTransientAndNonEvidenceFailuresImmediately() async throws {
        for failure in [
            ProbeDiagnostic.capture(APIError.rejected(403), phase: .evidenceDecode),
            .capture(APIError.rejected(404), phase: .evidenceDecode),
            .capture(APIError.invalidPayload, phase: .evidenceDecode),
            .capture(ProbeFailure.failed("wrong stage or request count"), phase: .boundaryValidation),
            .capture(APIError.rejected(500), phase: .seedRequest),
            .capture(APIError.rejected(500), phase: .refreshRequest)
        ] {
            let reader = EvidenceSequence([failure])
            do {
                try await ProbeHeldPolling.wait(read: { try await reader.read() }, onRetry: {})
                XCTFail("Must fail closed")
            } catch let error as ProbeDiagnostic { XCTAssertEqual(error.fields, failure.fields) }
            let calls = await reader.calls
            XCTAssertEqual(calls, 1)
        }
    }
    func testHeldPollingAbsoluteDeadlineCancelsAnInFlightRead() async throws {
        let started = ContinuousClock.now
        do {
            try await ProbeHeldPolling.wait(timeout: .milliseconds(50), read: {
                try await Task.sleep(for: .seconds(5))
                return true
            }, onRetry: {})
            XCTFail("Late evidence must be rejected")
        } catch let error as ProbeDiagnostic { XCTAssertEqual(error.phase, .heldPolling) }
        XCTAssertLessThan(started.duration(to: .now), .seconds(1))
    }
    func testHeldPollingPersistent500ExhaustsDeadline() async throws {
        do {
            try await ProbeHeldPolling.wait(timeout: .milliseconds(50), interval: .milliseconds(10), read: {
                throw ProbeDiagnostic.capture(APIError.rejected(500), phase: .evidenceDecode)
            }, onRetry: {})
            XCTFail("Persistent failure must not pass")
        } catch let error as ProbeDiagnostic { XCTAssertEqual(error.phase, .heldPolling) }
    }
}
