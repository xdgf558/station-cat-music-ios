import Foundation
import Darwin
#if canImport(StationCatMusic)
@testable import StationCatMusic
#endif

// Only compile-time phases and error categories enter artifacts; never Error descriptions/userInfo.
enum ProbePhase: String, Sendable {
    case configuration, cleanup, seedRequest, seedDecode, sessionInstall, deletionPrepare, receiptWrite
    case authRestore, refreshRequest, evidenceRequest, evidenceDecode, evidenceRetry, heldPolling, boundaryValidation
    case journalRead, journalWrite, expectedRequestWrite, recoveryRead, recoveryEvidence, recoveryAssertions, recoveryCleanup
}
struct ProbeDiagnostic: Error, Sendable {
    let phase: ProbePhase
    let category: String
    let code: Int?
    static func capture(_ error: Error, phase: ProbePhase) -> Self {
        if let diagnostic = error as? Self { return diagnostic }
        let category: String; var code: Int?
        if let failure = error as? SecureStoreError {
            switch failure {
            case .osStatus(let status): category = "keychain_status"; code = Int(status)
            case .protectedDataUnavailable: category = "keychain_locked"
            case .corrupt: category = "keychain_corrupt"
            }
        } else if let failure = error as? APIError {
            switch failure {
            case .rejected(let status): category = "http_rejected"; code = status
            case .invalidRequest: category = "invalid_request"
            case .invalidPayload: category = "invalid_payload"
            case .staleResponse: category = "stale_response"
            case .storageUnavailable: category = "storage_unavailable"
            case .requiresAuthentication: category = "authentication_required"
            case .networkDisabled: category = "network_disabled"
            case .unavailable: category = "unavailable"
            }
        } else if let failure = error as? NativeFailure {
            // Server code is intentionally not interpolated: even a malformed code may contain secrets.
            category = "native_rejected"; code = failure.status
        } else if error is DecodingError { category = "decode_failed"
        } else if error is ProbeFailure { category = "assertion_failed"
        } else if error is CancellationError { category = "cancelled"
        } else {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain { category = "url_error"; code = ns.code }
            else if ns.domain == NSCocoaErrorDomain { category = "file_error"; code = ns.code }
            else { category = "unknown" }
        }
        return Self(phase: phase, category: category, code: code)
    }
    var fields: String { "step=\(phase.rawValue):category=\(category)" + (code.map { ":code=\($0)" } ?? "") }
}

// Test-only durable evidence. No credential values are written here.
enum ProbeReporter {
    private static let lock = NSLock()
    static func phase(_ phase: ProbePhase) throws { try emit("M2_PROBE_STEP:\(phase.rawValue):pid=\(getpid())") }
    static func failure(_ error: Error) throws {
        let diagnostic = ProbeDiagnostic.capture(error, phase: .configuration)
        try emit("M2_PROBE_FAILED:\(diagnostic.fields):pid=\(getpid())")
    }
    static func emit(_ line: String) throws {
        lock.lock(); defer { lock.unlock() }
        if let runID = ProcessInfo.processInfo.environment["M2_PROBE_RUN_ID"] {
            guard UUID(uuidString: runID) != nil else { throw APIError.invalidRequest }
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let path = directory.appendingPathComponent("M2-" + runID + ".log")
            let prior = FileManager.default.fileExists(atPath: path.path) ? try Data(contentsOf: path) : Data()
            guard prior.count < 8192 else { throw APIError.invalidPayload }
            var bytes = prior; bytes.append(Data((line + "\n").utf8))
            try bytes.write(to: path, options: .atomic)
            let file = try FileHandle(forWritingTo: path)
            defer { try? file.close() }; try file.synchronize()
        }
        print(line); fflush(nil)
    }
}

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
        // Evidence polling must not occupy the refresh replay window with a 40s GET.
        let evidenceRead = path == "/fixture/evidence"
        settings.timeoutIntervalForRequest = evidenceRead ? 2 : 35
        settings.timeoutIntervalForResource = evidenceRead ? 2 : 40
        let session = URLSession(configuration: settings, delegate: RejectRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var r = URLRequest(url: URL(string: "http://127.0.0.1:\(configuration.port)\(path)")!)
        r.httpMethod = method; r.httpBody = body
        r.setValue(configuration.key, forHTTPHeaderField: "X-Probe-Key")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let (data, response) = try await session.data(for: r)
            guard let response = response as? HTTPURLResponse, data.count < 262_144 else { throw APIError.invalidPayload }
            return HTTPResult(status: response.statusCode, data: data)
        } catch {
            let phase: ProbePhase = path == "/fixture/seed" ? .seedRequest : path == "/fixture/evidence" ? .evidenceRequest : .refreshRequest
            throw ProbeDiagnostic.capture(error, phase: phase)
        }
    }
    func evidence() async throws -> ProbeEvidence {
        let r = try await request("/fixture/evidence")
        do {
            guard r.status == 200 else { throw APIError.rejected(r.status) }
            return try JSONDecoder().decode(ProbeEvidence.self, from: r.data)
        } catch { throw ProbeDiagnostic.capture(error, phase: .evidenceDecode) }
    }
}

// Only GET evidence is retried. Mutation requests and boundary assertions never enter this loop.
enum ProbeHeldPolling {
    static func retryable(_ error: Error) -> Bool {
        guard let diagnostic = error as? ProbeDiagnostic,
              [.evidenceRequest, .evidenceDecode].contains(diagnostic.phase) else { return false }
        if diagnostic.category == "http_rejected" {
            return [500, 502, 503, 504].contains(diagnostic.code ?? 0)
        }
        return diagnostic.category == "url_error" &&
            [URLError.timedOut.rawValue, URLError.networkConnectionLost.rawValue,
             URLError.cannotConnectToHost.rawValue].contains(diagnostic.code ?? 0)
    }
    static func wait(timeout: Duration = .seconds(10), interval: Duration = .milliseconds(100),
                     read: @escaping @Sendable () async throws -> Bool,
                     onRetry: @escaping @Sendable (ProbeDiagnostic) throws -> Void = { error in
                         try ProbeReporter.emit("M2_PROBE_EVIDENCE_RETRY:\(error.fields):pid=\(getpid())")
                     }) async throws {
        let clock = ContinuousClock(), deadline = ContinuousClock.now + timeout
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await clock.sleep(until: deadline)
                throw ProbeDiagnostic.capture(APIError.unavailable, phase: .heldPolling)
            }
            group.addTask {
                while clock.now < deadline {
                    try Task.checkCancellation()
                    do {
                        if try await read() {
                            guard clock.now < deadline else { break }
                            return
                        }
                    } catch {
                        guard retryable(error) else { throw error }
                        try onRetry(ProbeDiagnostic.capture(error, phase: .evidenceRequest))
                    }
                    try await clock.sleep(until: min(clock.now + interval, deadline))
                }
                throw ProbeDiagnostic.capture(APIError.unavailable, phase: .heldPolling)
            }
            defer { group.cancelAll() }
            _ = try await group.next()
        }
    }
}
private func exitAtBoundary(_ config: CrashProbeConfiguration, store: KeychainStore) async throws -> Never {
    try ProbeReporter.phase(.boundaryValidation)
    do {
    guard let record = try await AuthJournal(store: store, environment: .development).read(),
          (config.stage == "A13" ? record.generation == 1 && record.pending == nil : record.generation == 0 && record.pending != nil),
          try await store.read("expected-request") != nil,
          try await store.read("expected-receipt") != nil else { throw APIError.invalidPayload }
    try ProbeReporter.emit("M2_BOUNDARY_REACHED:\(config.stage):durable-state-verified:pid=\(getpid())")
    fflush(nil)
    _exit(73)
    } catch { throw ProbeDiagnostic.capture(error, phase: .boundaryValidation) }
}
private actor BoundaryStore: SecureStore {
    let base: KeychainStore
    let config: CrashProbeConfiguration
    init(base: KeychainStore, config: CrashProbeConfiguration) { self.base = base; self.config = config }
    func read(_ key: String) async throws -> Data? {
        do { return try await base.read(key) }
        catch { throw ProbeDiagnostic.capture(error, phase: .journalRead) }
    }
    func remove(_ key: String) async throws { try await base.remove(key) }
    func write(_ data: Data, key: String) async throws {
        var phase = ProbePhase.journalWrite
        do {
        let envelope = key == "auth.development" ? try JSONDecoder().decode(CredentialEnvelope.self, from: data) : nil
        let replacing = config.mode == "CRASH" && envelope?.generation == 1 && envelope?.pending == nil
        if replacing && config.stage == "A12" { try await exitAtBoundary(config, store: base) }
        try await base.write(data, key: key)
        if let request = envelope?.pending?.requestID {
            phase = .expectedRequestWrite
            try await base.write(Data(request.utf8), key: "expected-request")
        }
        if replacing && config.stage == "A13" { try await exitAtBoundary(config, store: base) }
        } catch { throw ProbeDiagnostic.capture(error, phase: phase) }
    }
}
private actor BoundaryTransport: HTTPTransport {
    let probe: LoopbackProbe
    let store: KeychainStore
    init(probe: LoopbackProbe, store: KeychainStore) { self.probe = probe; self.store = store }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        guard request.url?.host == "native.local.test", request.url?.path == "/api/mobile/v1/auth/refresh", request.httpMethod == "POST" else { throw APIError.invalidRequest }
        let probe = self.probe, store = self.store
        try ProbeReporter.phase(.refreshRequest)
        return try await withThrowingTaskGroup(of: HTTPResult.self) { group in
            group.addTask { try await probe.request("/api/mobile/v1/auth/refresh", method: "POST", body: request.httpBody) }
            if probe.configuration.stage == "A11" && probe.configuration.mode == "CRASH" {
                group.addTask {
                    try ProbeReporter.phase(.heldPolling)
                    try await ProbeHeldPolling.wait {
                        let observed = try await probe.evidence()
                        try probeEqual(observed.stage, probe.configuration.stage)
                        guard observed.held else { return false }
                        // The fixture reads D1 and then its in-memory held flag. A GET
                        // racing commit can see an older D1 row with held=true. Read
                        // again after the barrier before asserting a coherent snapshot.
                        let evidence = try await probe.evidence()
                        do {
                            try probeTrue(evidence.held)
                            try probeEqual(evidence.stage, probe.configuration.stage)
                            try probeEqual(evidence.requests.count, 1)
                            try probeEqual(evidence.requests.first?.status, 200)
                            try probeEqual(evidence.requests.first?.generation, 0)
                            try probeEqual(evidence.requests.first?.resultGeneration, 1)
                            try probeEqual(evidence.session.generation, 1)
                            try probeEqual(evidence.session.revoked, 0)
                            try probeEqual(evidence.operations.count, 1)
                            let expected = try await store.read("expected-request")
                            let requestID = try probeUnwrap(expected.flatMap { String(data: $0, encoding: .utf8) })
                            try probeEqual(evidence.requests.first?.requestId, requestID)
                            try probeEqual(evidence.operations.first?.request_id, requestID)
                            try probeEqual(evidence.operations.first?.old_generation, 0)
                        } catch { throw ProbeDiagnostic.capture(error, phase: .boundaryValidation) }
                        return true
                    }
                    try await exitAtBoundary(probe.configuration, store: store)
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
        var phase = ProbePhase.cleanup
        do {
        try ProbeReporter.phase(phase)
        let base = KeychainStore(service: config.service)
        for key in ["auth.development", "deletion.development", "expected-request", "expected-receipt"] { try await base.remove(key) }
        phase = .seedRequest; try ProbeReporter.phase(phase)
        let result = try await LoopbackProbe(configuration: config).request("/fixture/seed", method: "POST", body: JSONSerialization.data(withJSONObject: ["stage": config.stage]))
        guard result.status == 200 else { throw APIError.rejected(result.status) }
        phase = .seedDecode; try ProbeReporter.phase(phase)
        let seed = try NativeJSON.decoder().decode(NativeResponse<NativeTokens>.self, from: result.data)
        let journal = AuthJournal(store: base, environment: .development)
        phase = .sessionInstall; try ProbeReporter.phase(phase)
        try await journal.install(seed.data.credential(environment: .development, serverNow: seed.serverNow))
        phase = .deletionPrepare; try ProbeReporter.phase(phase)
        let receipt = try await DeletionJournal(store: base, environment: .development).prepare(accountID: seed.data.accountId)
        phase = .receiptWrite; try ProbeReporter.phase(phase)
        try await base.write(receipt.receipt, key: "expected-receipt")
        let auth = try service(config, store: BoundaryStore(base: base, config: config), base: base)
        phase = .authRestore; try ProbeReporter.phase(phase)
        try await auth.restore()
        throw ProbeFailure.failed("Expected process termination before publishing refresh success")
        } catch { throw ProbeDiagnostic.capture(error, phase: phase) }
    }
    func testRecoverOriginalOperation() async throws {
        let config = try CrashProbeConfiguration.load()
        guard config.mode == "RECOVER" else { throw APIError.invalidRequest }
        var phase = ProbePhase.recoveryRead
        do {
        try ProbeReporter.phase(phase)
        let base = KeychainStore(service: config.service), journal = AuthJournal(store: base, environment: .development)
        let beforeRecord = try await journal.read()
        let before = try probeUnwrap(beforeRecord)
        let requestData = try await base.read("expected-request")
        let requestID = try probeUnwrap(requestData.flatMap { String(data: $0, encoding: .utf8) })
        try probeEqual(before.generation, config.stage == "A13" ? 1 : 0)
        if config.stage == "A13" { try probeNil(before.pending) } else { try probeEqual(before.pending?.requestID, requestID) }
        phase = .recoveryEvidence; try ProbeReporter.phase(phase)
        let probe = LoopbackProbe(configuration: config), committed = try await probe.evidence()
        try probeEqual(committed.session.generation, 1); try probeEqual(committed.operations.count, 1)
        try probeEqual(committed.operations.first?.request_id, requestID)
        let auth = try service(config, store: base, base: base)
        phase = .authRestore; try ProbeReporter.phase(phase)
        try await auth.restore()
        phase = .recoveryAssertions; try ProbeReporter.phase(phase)
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
        try ProbeReporter.emit("M2_BOUNDARY_RECOVERED:\(config.stage):generation=\(after.generation):operations=\(evidence.operations.count):same-family:receipt-preserved:pid=\(getpid())")
        phase = .recoveryCleanup; try ProbeReporter.phase(phase)
        for key in ["auth.development", "deletion.development", "expected-request", "expected-receipt"] { try await base.remove(key) }
        } catch { throw ProbeDiagnostic.capture(error, phase: phase) }
    }
}
