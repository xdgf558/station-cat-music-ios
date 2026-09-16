import Foundation
import Security
import CryptoKit

nonisolated protocol SecureStore: Sendable {
    func read(_ key: String) async throws -> Data?
    func write(_ data: Data, key: String) async throws
    func remove(_ key: String) async throws
}
nonisolated enum SecureStoreError: Error, Equatable { case protectedDataUnavailable, osStatus(Int32), corrupt }
actor KeychainStore: SecureStore {
    private let service: String
    init(service: String) { self.service = service }
    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: key, kSecAttrSynchronizable as String: false]
    }
    private func check(_ status: OSStatus) throws {
        if status == errSecInteractionNotAllowed || status == errSecNotAvailable { throw SecureStoreError.protectedDataUnavailable }
        guard status == errSecSuccess else { throw SecureStoreError.osStatus(status) }
    }
    func read(_ key: String) throws -> Data? {
        var q = query(key); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data else { throw SecureStoreError.corrupt }
        return data
    }
    func write(_ data: Data, key: String) throws {
        let q = query(key)
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(q as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(q.merging(attributes) { _, new in new } as CFDictionary, nil)
            if status == errSecDuplicateItem { status = SecItemUpdate(q as CFDictionary, attributes as CFDictionary) }
        }
        try check(status) // Never delete then add: each replacement is one item operation.
    }
    func remove(_ key: String) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
}
actor MemorySecureStore: SecureStore {
    private var values: [String: Data] = [:]
    var failWrites = false
    func setFailure(_ value: Bool) { failWrites = value }
    func read(_ key: String) -> Data? { values[key] }
    func write(_ data: Data, key: String) throws { if failWrites { throw APIError.storageUnavailable }; values[key] = data }
    func remove(_ key: String) { values.removeValue(forKey: key) }
}
actor AuthJournal {
    private let store: any SecureStore
    private let environment: AppEnvironment
    private(set) var epoch = 0
    private var writing = false
    private var key: String { "auth.\(environment.rawValue)" }
    init(store: any SecureStore, environment: AppEnvironment) { self.store = store; self.environment = environment }
    func read() async throws -> CredentialEnvelope? {
        guard let data = try await store.read(key) else { return nil }
        guard let e = try? JSONDecoder().decode(CredentialEnvelope.self, from: data), e.schemaVersion == 1, e.scope.environment == environment, e.scope.accountID != nil, e.generation >= 0, e.refreshExpiresAt <= e.absoluteExpiresAt else { throw SecureStoreError.corrupt }
        return e
    }
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private func acquire() async {
        if !writing { writing = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    private func release() {
        if waiters.isEmpty { writing = false } else { waiters.removeFirst().resume() }
    }
    func install(_ envelope: CredentialEnvelope, expectedEpoch: Int? = nil) async throws {
        let ticket = expectedEpoch ?? epoch
        await acquire(); defer { release() }
        guard ticket == epoch, envelope.schemaVersion == 1, envelope.scope.environment == environment,
              envelope.scope.accountID != nil, envelope.generation >= 0, envelope.refreshExpiresAt <= envelope.absoluteExpiresAt else { throw APIError.staleResponse }
        try await store.write(JSONEncoder().encode(envelope), key: key)
        guard ticket == epoch else { throw APIError.staleResponse }
    }
    func prepare(digest: String) async throws -> CredentialEnvelope {
        let ticket = epoch
        await acquire(); defer { release() }
        guard var envelope = try await read() else { throw APIError.requiresAuthentication }
        guard ticket == epoch else { throw APIError.staleResponse }
        if let pending = envelope.pending {
            guard pending.oldGeneration == envelope.generation, pending.canonicalDigest == digest else { throw APIError.staleResponse }
        } else {
            envelope.pending = PendingRefresh(requestID: UUID().uuidString, oldGeneration: envelope.generation, canonicalDigest: digest)
            try await store.write(JSONEncoder().encode(envelope), key: key)
        }
        guard ticket == epoch else { throw APIError.staleResponse }
        return envelope // M2 may send only after durable persistence succeeds.
    }
    func complete(expected: CredentialEnvelope, replacement: CredentialEnvelope) async throws {
        let ticket = epoch
        await acquire(); defer { release() }
        guard let current = try await read(), current == expected,
              replacement.schemaVersion == 1, replacement.scope == expected.scope, replacement.sessionID == expected.sessionID,
              replacement.familyID == expected.familyID, replacement.generation == expected.generation + 1,
              replacement.refreshExpiresAt <= replacement.absoluteExpiresAt, replacement.absoluteExpiresAt == expected.absoluteExpiresAt,
              expected.pending != nil, replacement.pending == nil, ticket == epoch else { throw APIError.staleResponse }
        try await store.write(JSONEncoder().encode(replacement), key: key)
        guard ticket == epoch else { throw APIError.staleResponse }
    }
    func logout() async throws {
        _ = try await logoutReturningCredential()
    }
    func logoutReturningCredential() async throws -> CredentialEnvelope? {
        epoch += 1 // Invalidate a suspended completion before waiting for its storage operation.
        await acquire(); defer { release() }
        let previous = try await read()
        try await store.remove(key) // Separate deletion recovery namespace survives.
        return previous
    }
}
nonisolated enum DeletionReceipt {
    static func generate() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw APIError.storageUnavailable }
        return Data(bytes)
    }
    static func encode(_ bytes: Data) throws -> String {
        guard bytes.count == 32 else { throw APIError.invalidPayload }
        return bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func hash(_ bytes: Data) throws -> String {
        guard bytes.count == 32 else { throw APIError.invalidPayload }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}
