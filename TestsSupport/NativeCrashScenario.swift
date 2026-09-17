import Foundation
import Darwin
#if canImport(StationCatMusic)
@testable import StationCatMusic
#endif

enum ProbeFailure: Error { case failed(String) }
func probeUnwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw ProbeFailure.failed("Missing probe value") }; return value
}
func probeEqual<T: Equatable>(_ lhs: T, _ rhs: T) throws {
    guard lhs == rhs else { throw ProbeFailure.failed("Values differ") }
}
func probeNotEqual<T: Equatable>(_ lhs: T, _ rhs: T) throws {
    guard lhs != rhs else { throw ProbeFailure.failed("Values unexpectedly equal") }
}
func probeNotNil<T>(_ value: T?) throws { guard value != nil else { throw ProbeFailure.failed("Unexpected nil") } }
func probeNil<T>(_ value: T?) throws { guard value == nil else { throw ProbeFailure.failed("Expected nil") } }
func probeTrue(_ value: Bool) throws { guard value else { throw ProbeFailure.failed("Condition false") } }
func probeLess<T: Comparable>(_ lhs: T, _ rhs: T) throws {
    guard lhs < rhs else { throw ProbeFailure.failed("Replay deadline exceeded") }
}

// Test-target only: HTTP loopback is a bridge to a real local Worker/D1, never an App setting.
struct CrashProbeConfiguration: Sendable {
    let stage: String
    let mode: String
    let port: Int
    let key: String
    var service: String { "org.stationcat.music.dev.m2.boundary.\(stage)" }
    static func load() throws -> Self {
        let e = ProcessInfo.processInfo.environment
        guard e["M2_BOUNDARY_MODE"] != nil else { throw APIError.invalidRequest }
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
    print("M2_BOUNDARY_REACHED:\(config.stage):durable-state-verified:pid=\(getpid())")
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

@MainActor final class NativeCrashScenario {
    private func service(_ config: CrashProbeConfiguration, store: any SecureStore, base: KeychainStore) throws -> NativeAuthenticationService {
        let settings = try NativeAuthConfiguration(environment: .development, origin: URL(string: "https://native.local.test")!, explicitlyEnabled: true)
        let api = NativeAuthAPI(configuration: settings, transport: BoundaryTransport(probe: LoopbackProbe(configuration: config), store: base))
        return NativeAuthenticationService(configuration: settings, api: api, journal: AuthJournal(store: store, environment: .development), browser: UnusedProbeBrowser())
    }
    func testCrashAtRefreshBoundary() async throws {
        let config = try CrashProbeConfiguration.load()
        guard config.mode == "CRASH" else { throw APIError.invalidRequest }
        let base = KeychainStore(service: config.service)
        for key in ["auth.development", "deletion.development", "expected-request", "expected-receipt"] { try await base.remove(key) }
        let result = try await LoopbackProbe(configuration: config).request("/fixture/seed", method: "POST", body: JSONSerialization.data(withJSONObject: ["stage": config.stage]))
        try probeEqual(result.status, 200)
        let seed = try NativeJSON.decoder().decode(NativeResponse<NativeTokens>.self, from: result.data)
        let journal = AuthJournal(store: base, environment: .development)
        try await journal.install(seed.data.credential(environment: .development, serverNow: seed.serverNow))
        let receipt = try await DeletionJournal(store: base, environment: .development).prepare(accountID: seed.data.accountId)
        try await base.write(receipt.receipt, key: "expected-receipt")
        let auth = try service(config, store: BoundaryStore(base: base, config: config), base: base)
        try await auth.restore()
        throw ProbeFailure.failed("Expected process termination before publishing refresh success")
    }
    func testRecoverOriginalOperation() async throws {
        let config = try CrashProbeConfiguration.load()
        guard config.mode == "RECOVER" else { throw APIError.invalidRequest }
        let base = KeychainStore(service: config.service), journal = AuthJournal(store: base, environment: .development)
        let beforeRecord = try await journal.read()
        let before = try probeUnwrap(beforeRecord)
        let requestData = try await base.read("expected-request")
        let requestID = try probeUnwrap(requestData.flatMap { String(data: $0, encoding: .utf8) })
        try probeEqual(before.generation, config.stage == "A13" ? 1 : 0)
        if config.stage == "A13" { try probeNil(before.pending) } else { try probeEqual(before.pending?.requestID, requestID) }
        let probe = LoopbackProbe(configuration: config), committed = try await probe.evidence()
        try probeEqual(committed.session.generation, 1); try probeEqual(committed.operations.count, 1)
        try probeEqual(committed.operations.first?.request_id, requestID)
        let auth = try service(config, store: base, base: base)
        try await auth.restore()
        let afterRecord = try await journal.read()
        let after = try probeUnwrap(afterRecord), evidence = try await probe.evidence()
        try probeEqual(after.scope, before.scope); try probeEqual(after.familyID, before.familyID)
        try probeEqual(after.absoluteExpiresAt, before.absoluteExpiresAt); try probeNil(after.pending)
        try probeEqual(evidence.requests.count, 2); try probeEqual(evidence.session.revoked, 0)
        try probeTrue(evidence.requests.allSatisfy { $0.status == 200 })
        if config.stage == "A13" {
            try probeEqual(after.generation, 2); try probeEqual(evidence.operations.count, 2)
            try probeEqual(evidence.requests.last?.generation, 1)
            try probeNotEqual(evidence.requests.last?.requestId, requestID)
        } else {
            try probeEqual(after.generation, 1); try probeEqual(evidence.operations.count, 1)
            try probeEqual(evidence.requests.last?.requestId, requestID)
            try probeEqual(evidence.requests.first?.resultFingerprint, evidence.requests.last?.resultFingerprint)
            try probeLess(evidence.requests[1].committedAt - evidence.requests[0].committedAt, 120_000)
        }
        let deletion = DeletionJournal(store: base, environment: .development)
        let receipt = try await deletion.read(), expectedReceipt = try await base.read("expected-receipt")
        try probeEqual(receipt?.receipt, expectedReceipt); try probeNotNil(expectedReceipt)
        let action = try await deletion.recoveryAction()
        try probeEqual(action, .queryStatus(try probeUnwrap(receipt).deletionRequestID))
        print("M2_BOUNDARY_RECOVERED:\(config.stage):generation=\(after.generation):operations=\(evidence.operations.count):same-family:receipt-preserved:pid=\(getpid())")
        for key in ["auth.development", "deletion.development", "expected-request", "expected-receipt"] { try await base.remove(key) }
    }
}
