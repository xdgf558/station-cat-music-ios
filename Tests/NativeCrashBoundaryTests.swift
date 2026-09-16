import XCTest
import Foundation
import Darwin
@testable import StationCatMusic

// Test-target only: HTTP loopback is a bridge to a real local Worker/D1, never an App setting.
private struct CrashProbeConfiguration: Sendable {
    let stage: String
    let mode: String
    let port: Int
    let key: String
    var service: String { "org.stationcat.music.dev.m2.boundary.\(stage)" }
    static func load() throws -> Self {
        let e = ProcessInfo.processInfo.environment
        try XCTSkipUnless(e["M2_BOUNDARY_MODE"] != nil, "Dedicated local Worker process-termination suite only")
        guard let stage = e["M2_BOUNDARY_STAGE"], ["A11", "A12", "A13"].contains(stage),
              let mode = e["M2_BOUNDARY_MODE"], ["CRASH", "RECOVER"].contains(mode),
              let port = e["M2_PROBE_PORT"].flatMap(Int.init), (1024...65535).contains(port),
              let key = e["M2_PROBE_KEY"], key.count == 43 else { throw APIError.invalidRequest }
        return Self(stage: stage, mode: mode, port: port, key: key)
    }
}
private struct ProbeEvidence: Decodable, Sendable {
    struct Request: Decodable, Sendable {
        let requestId: String; let generation: Int; let status: Int
        let resultFingerprint: String; let resultGeneration: Int; let committedAt: Double
    }
    struct Session: Decodable, Sendable { let generation: Int; let revoked: Int }
    struct Operation: Decodable, Sendable { let request_id: String; let old_generation: Int }
    let stage: String; let held: Bool; let requests: [Request]; let session: Session; let operations: [Operation]
}
private struct LoopbackProbe: Sendable {
    let configuration: CrashProbeConfiguration
    func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> HTTPResult {
        let settings = URLSessionConfiguration.ephemeral
        settings.httpCookieStorage = nil; settings.urlCache = nil
        settings.timeoutIntervalForRequest = 35; settings.timeoutIntervalForResource = 40
        let session = URLSession(configuration: settings, delegate: RejectRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var r = URLRequest(url: URL(string: "http://127.0.0.1:\(configuration.port)\(path)")!)
        r.httpMethod = method; r.httpBody = body
        r.setValue(configuration.key, forHTTPHeaderField: "X-Probe-Key")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: r)
        guard let response = response as? HTTPURLResponse, data.count < 262_144 else { throw APIError.invalidPayload }
        return HTTPResult(status: response.statusCode, data: data)
    }
    func evidence() async throws -> ProbeEvidence {
        let r = try await request("/fixture/evidence")
        guard r.status == 200 else { throw APIError.rejected(r.status) }
        return try JSONDecoder().decode(ProbeEvidence.self, from: r.data)
    }
}
private func exitAtBoundary(_ config: CrashProbeConfiguration, store: KeychainStore) async throws -> Never {
    guard let record = try await AuthJournal(store: store, environment: .development).read(),
          (config.stage == "A13" ? record.generation == 1 && record.pending == nil : record.generation == 0 && record.pending != nil),
          try await store.read("expected-request") != nil,
          try await store.read("expected-receipt") != nil else { throw APIError.invalidPayload }
    print("M2_BOUNDARY_REACHED:\(config.stage):durable-state-verified")
    fflush(nil)
    _exit(73)
}
private actor BoundaryStore: SecureStore {
    let base: KeychainStore
    let config: CrashProbeConfiguration
    init(base: KeychainStore, config: CrashProbeConfiguration) { self.base = base; self.config = config }
    func read(_ key: String) async throws -> Data? { try await base.read(key) }
    func remove(_ key: String) async throws { try await base.remove(key) }
    func write(_ data: Data, key: String) async throws {
        let envelope = key == "auth.development" ? try JSONDecoder().decode(CredentialEnvelope.self, from: data) : nil
        let replacing = config.mode == "CRASH" && envelope?.generation == 1 && envelope?.pending == nil
        if replacing && config.stage == "A12" { try await exitAtBoundary(config, store: base) }
        try await base.write(data, key: key)
        if let request = envelope?.pending?.requestID { try await base.write(Data(request.utf8), key: "expected-request") }
        if replacing && config.stage == "A13" { try await exitAtBoundary(config, store: base) }
    }
}
private actor BoundaryTransport: HTTPTransport {
    let probe: LoopbackProbe
    let store: KeychainStore
    init(probe: LoopbackProbe, store: KeychainStore) { self.probe = probe; self.store = store }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        guard request.url?.host == "native.local.test", request.url?.path == "/api/mobile/v1/auth/refresh", request.httpMethod == "POST" else { throw APIError.invalidRequest }
        let probe = self.probe, store = self.store
        return try await withThrowingTaskGroup(of: HTTPResult.self) { group in
            group.addTask { try await probe.request("/api/mobile/v1/auth/refresh", method: "POST", body: request.httpBody) }
            if probe.configuration.stage == "A11" && probe.configuration.mode == "CRASH" {
                group.addTask {
                    for _ in 0..<200 {
                        if try await probe.evidence().held { try await exitAtBoundary(probe.configuration, store: store) }
                        try await Task.sleep(for: .milliseconds(50))
                    }
                    throw APIError.unavailable
                }
            }
            guard let value = try await group.next() else { throw APIError.unavailable }
            group.cancelAll(); return value
        }
    }
}
private struct UnusedProbeBrowser: AuthenticationBrowser {
    @MainActor func authorize(url: URL, callback: URL) async throws -> URL { throw APIError.invalidRequest }
}

@MainActor final class NativeCrashBoundaryTests: XCTestCase {
    private func service(_ config: CrashProbeConfiguration, store: any SecureStore, base: KeychainStore) throws -> NativeAuthenticationService {
        let settings = try NativeAuthConfiguration(environment: .development, origin: URL(string: "https://native.local.test")!, explicitlyEnabled: true)
        let api = NativeAuthAPI(configuration: settings, transport: BoundaryTransport(probe: LoopbackProbe(configuration: config), store: base))
        return NativeAuthenticationService(configuration: settings, api: api, journal: AuthJournal(store: store, environment: .development), browser: UnusedProbeBrowser())
    }
    func testCrashAtRefreshBoundary() async throws {
        let config = try CrashProbeConfiguration.load()
        try XCTSkipUnless(config.mode == "CRASH", "Crash phase only")
        let base = KeychainStore(service: config.service)
        for key in ["auth.development", "deletion.development", "expected-request", "expected-receipt"] { try await base.remove(key) }
        let result = try await LoopbackProbe(configuration: config).request("/fixture/seed", method: "POST", body: JSONSerialization.data(withJSONObject: ["stage": config.stage]))
        XCTAssertEqual(result.status, 200)
        let seed = try NativeJSON.decoder().decode(NativeResponse<NativeTokens>.self, from: result.data)
        let journal = AuthJournal(store: base, environment: .development)
        try await journal.install(seed.data.credential(environment: .development, serverNow: seed.serverNow))
        let receipt = try await DeletionJournal(store: base, environment: .development).prepare(accountID: seed.data.accountId)
        try await base.write(receipt.receipt, key: "expected-receipt")
        let auth = try service(config, store: BoundaryStore(base: base, config: config), base: base)
        try await auth.restore()
        XCTFail("Expected process termination before publishing refresh success")
    }
    func testRecoverOriginalOperation() async throws {
        let config = try CrashProbeConfiguration.load()
        try XCTSkipUnless(config.mode == "RECOVER", "Recovery phase only")
        let base = KeychainStore(service: config.service), journal = AuthJournal(store: base, environment: .development)
        let beforeRecord = try await journal.read()
        let before = try XCTUnwrap(beforeRecord)
        let requestData = try await base.read("expected-request")
        let requestID = try XCTUnwrap(requestData.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertEqual(before.generation, config.stage == "A13" ? 1 : 0)
        if config.stage == "A13" { XCTAssertNil(before.pending) } else { XCTAssertEqual(before.pending?.requestID, requestID) }
        let probe = LoopbackProbe(configuration: config), committed = try await probe.evidence()
        XCTAssertEqual(committed.session.generation, 1); XCTAssertEqual(committed.operations.count, 1)
        XCTAssertEqual(committed.operations.first?.request_id, requestID)
        let auth = try service(config, store: base, base: base)
        try await auth.restore()
        let afterRecord = try await journal.read()
        let after = try XCTUnwrap(afterRecord), evidence = try await probe.evidence()
        XCTAssertEqual(after.scope, before.scope); XCTAssertEqual(after.familyID, before.familyID)
        XCTAssertEqual(after.absoluteExpiresAt, before.absoluteExpiresAt); XCTAssertNil(after.pending)
        XCTAssertEqual(evidence.requests.count, 2); XCTAssertEqual(evidence.session.revoked, 0)
        XCTAssertTrue(evidence.requests.allSatisfy { $0.status == 200 })
        if config.stage == "A13" {
            XCTAssertEqual(after.generation, 2); XCTAssertEqual(evidence.operations.count, 2)
            XCTAssertEqual(evidence.requests.last?.generation, 1)
            XCTAssertNotEqual(evidence.requests.last?.requestId, requestID)
        } else {
            XCTAssertEqual(after.generation, 1); XCTAssertEqual(evidence.operations.count, 1)
            XCTAssertEqual(evidence.requests.last?.requestId, requestID)
            XCTAssertEqual(evidence.requests.first?.resultFingerprint, evidence.requests.last?.resultFingerprint)
            XCTAssertLessThan(evidence.requests[1].committedAt - evidence.requests[0].committedAt, 120_000)
        }
        let deletion = DeletionJournal(store: base, environment: .development)
        let receipt = try await deletion.read(), expectedReceipt = try await base.read("expected-receipt")
        XCTAssertEqual(receipt?.receipt, expectedReceipt); XCTAssertNotNil(expectedReceipt)
        let action = try await deletion.recoveryAction()
        XCTAssertEqual(action, .queryStatus(try XCTUnwrap(receipt).deletionRequestID))
        print("M2_BOUNDARY_RECOVERED:\(config.stage):generation=\(after.generation):operations=\(evidence.operations.count):same-family:receipt-preserved")
        for key in ["auth.development", "deletion.development", "expected-request", "expected-receipt"] { try await base.remove(key) }
    }
}
