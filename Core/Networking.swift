import Foundation

nonisolated struct HTTPResult: Sendable { let status: Int; let data: Data }
nonisolated protocol HTTPTransport: Sendable { func send(_ request: URLRequest) async throws -> HTTPResult }
nonisolated final class RejectRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
actor URLSessionTransport: HTTPTransport {
    private let session: URLSession
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        session = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
    }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError.invalidPayload }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 262_144 else { throw APIError.invalidPayload }
            data.append(byte)
        }
        return HTTPResult(status: response.statusCode, data: data)
    }
}
actor MockTransport: HTTPTransport {
    private let data: Data
    private let delay: Duration
    private let status: Int
    private(set) var requestCount = 0
    init(data: Data, delay: Duration = .zero, status: Int = 200) { self.data = data; self.delay = delay; self.status = status }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        requestCount += 1
        guard request.httpMethod == "GET", request.url?.path == "/api/mobile/v1/music/catalog" else { throw APIError.invalidRequest }
        try await Task.sleep(for: delay)
        try Task.checkCancellation()
        return HTTPResult(status: status, data: data)
    }
}
actor APIClient {
    private let environment: AppEnvironment
    private let transport: any HTTPTransport
    init(environment: AppEnvironment, transport: any HTTPTransport) { self.environment = environment; self.transport = transport }
    func catalog() async throws -> Catalog {
        guard environment == .mock else { throw APIError.networkDisabled }
        // Reserved .invalid address is never sent over a real network in M1.
        var request = URLRequest(url: URL(string: "https://mock.invalid/api/mobile/v1/music/catalog")!)
        request.httpMethod = "GET"
        let response = try await transport.send(request)
        try Task.checkCancellation()
        guard response.status == 200 else {
            if response.status == 503 { throw APIError.unavailable }
            throw APIError.rejected(response.status)
        }
        do { return try JSONDecoder().decode(APIEnvelope<Catalog>.self, from: response.data).data }
        catch { throw APIError.invalidPayload }
    }
    func mutate() throws { throw APIError.networkDisabled }
}
actor ScopedLibrary {
    private var scopes: [AccountScope: Set<String>] = [:]
    func favorites(in scope: AccountScope) -> Set<String> { scopes[scope, default: []] }
    func setFavorite(_ track: String, value: Bool, scope: AccountScope) {
        if value { scopes[scope, default: []].insert(track) } else { scopes[scope]?.remove(track) }
    }
    func clear(scope: AccountScope) { scopes.removeValue(forKey: scope) }
    // No implicit guest -> account merge. Persistence/cloud sync belongs to M5.
}
