import Foundation
@testable import StationCatMusic

// Test target only. Product URLs retain their production identity; only this
// adapter can reach a proof-protected random loopback listener. No real account,
// production Keychain, ASWebAuthenticationSession or public network is used.
enum ProductionLocalFixture {
    static let origin = URL(string: ProductionActivationProfile.origin)!
    enum Failure: Error { case input, boundary, response, assertion }
    static func require(_ condition: Bool) throws { if !condition { throw Failure.assertion } }
    static func configuration() throws -> NativeAuthConfiguration {
        let profile: [String: Any] = ["schemaVersion": 1, "profileId": ProductionActivationProfile.identifier,
            "enabled": true, "environment": "production", "apiOrigin": origin.absoluteString,
            "webOrigin": origin.absoluteString, "callback": origin.appending(path: "auth/mobile/callback").absoluteString,
            "applicationIdentifier": ProductionActivationProfile.applicationIdentifier,
            "capabilities": ["nativeAuthentication": true, "musicCatalog": true, "musicPlayback": true,
                             "personalSync": true, "accountDeletion": false]]
        let runtime = NativeRuntimeConfiguration(info: ["StationEnvironment": "production",
            "CFBundleIdentifier": ProductionActivationProfile.bundleIdentifier,
            "StationNativeAuthEnabled": "YES", "StationNativeMusicEnabled": "YES", "StationPersonalSyncEnabled": "YES",
            "StationNativeAuthOrigin": origin.absoluteString, "StationMusicWebOrigin": origin.absoluteString,
            "StationProductionActivationEnabled": "YES",
            "StationProductionActivationProfile": try JSONSerialization.data(withJSONObject: profile).base64EncodedString()])
        guard let configuration = runtime.authentication, runtime.musicEnabled, runtime.personalSyncEnabled,
              !configuration.accountDeletionAllowed else { throw Failure.input }
        return configuration
    }
    static func validate(_ url: URL?) throws -> URL {
        guard let url, let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme == "https", c.host == origin.host, c.port == nil,
              c.user == nil, c.password == nil, c.fragment == nil else { throw Failure.boundary }
        return url
    }
    static func category(_ error: Error) -> String {
        if let error = error as? URLError { return "url_error_\(error.code.rawValue)" }
        if let error = error as? NativeFailure { return "native_http_\(error.status)" }
        if error is DecodingError { return "decoding" }
        if let error = error as? Failure {
            switch error {
            case .input: return "fixture_input"
            case .boundary: return "fixture_boundary"
            case .response: return "fixture_response"
            case .assertion: return "fixture_assertion"
            }
        }
        if let error = error as? APIError {
            switch error {
            case .rejected(let status): return "api_http_\(status)"
            case .invalidPayload: return "api_invalid_payload"
            case .invalidRequest: return "api_invalid_request"
            case .staleResponse: return "api_stale_response"
            default: return "api_error"
            }
        }
        return "other" // Deliberately omit URLs, credentials, bodies and localized errors.
    }
    struct Identity: Decodable, Sendable { let id: String; let identifier: String; let password: String }
    struct Tracks: Decodable, Sendable { let freeTrackId: String; let vipTrackId: String }
    struct Bootstrap: Decodable, Sendable {
        let schemaVersion: Int; let origin: String
        let account: Identity; let vipAccount: Identity; let tracks: Tracks; let collectionSlug: String
    }
    struct WireResponse: Decodable, Sendable { let status: Int; let headers: [String: String]; let bodyBase64: String }
}

actor ProductionLocalBridge {
    private let port: Int
    private let key: String
    private let session: URLSession
    private(set) var dispatched = 0
    init(port: Int, key: String) throws {
        guard (1024...65535).contains(port), key.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else {
            throw ProductionLocalFixture.Failure.input
        }
        self.port = port; self.key = key
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 20
        session = URLSession(configuration: config, delegate: RejectRedirects(), delegateQueue: nil)
    }
    private func local(_ path: String, body: Data? = nil) async throws -> Data {
        guard ["/request", "/fixture/bootstrap", "/fixture/evidence"].contains(path) else { throw ProductionLocalFixture.Failure.boundary }
        let endpoint = path == "/request" ? "request" : path == "/fixture/bootstrap" ? "bootstrap" : "evidence"
        let url = URL(string: "http://127.0.0.1:\(port)" + path)!
        var request = URLRequest(url: url); request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.setValue(key, forHTTPHeaderField: "X-Production-Probe-Key")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse else {
            print("PRODUCTION_LOCAL_RESPONSE_REJECTED: endpoint=\(endpoint) httpResponse=false status=0 requestURLMatched=false")
            throw ProductionLocalFixture.Failure.response
        }
        guard response.url == url, response.statusCode == 200 else {
            print("PRODUCTION_LOCAL_RESPONSE_REJECTED: endpoint=\(endpoint) httpResponse=true status=\(response.statusCode) requestURLMatched=\(response.url == url)")
            throw ProductionLocalFixture.Failure.response
        }
        var result = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard result.count < 1_048_576 else {
                print("PRODUCTION_LOCAL_RESPONSE_REJECTED: endpoint=\(endpoint) status=\(response.statusCode) responseWithinLimit=false")
                throw ProductionLocalFixture.Failure.response
            }
            result.append(byte)
        }
        return result
    }
    func bootstrap() async throws -> ProductionLocalFixture.Bootstrap {
        let value = try JSONDecoder().decode(ProductionLocalFixture.Bootstrap.self, from: await local("/fixture/bootstrap"))
        guard value.schemaVersion == 1, value.origin == ProductionActivationProfile.origin,
              value.account.id != value.vipAccount.id, !value.account.id.isEmpty, !value.vipAccount.id.isEmpty,
              UUID(uuidString: value.tracks.freeTrackId) != nil, UUID(uuidString: value.tracks.vipTrackId) != nil,
              value.tracks.freeTrackId != value.tracks.vipTrackId,
              value.collectionSlug.range(of: "^[a-z0-9-]{1,100}$", options: .regularExpression) != nil else {
            throw ProductionLocalFixture.Failure.input
        }
        return value
    }
    func send(_ request: URLRequest) async throws -> MediaHTTPResult {
        let original = try ProductionLocalFixture.validate(request.url)
        let method = request.httpMethod ?? "GET"
        guard ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"].contains(method), request.httpBodyStream == nil,
              (request.httpBody?.count ?? 0) <= 65_536 else { throw ProductionLocalFixture.Failure.boundary }
        let headers = Dictionary(uniqueKeysWithValues: (request.allHTTPHeaderFields ?? [:]).map { ($0.key.lowercased(), $0.value) })
        var body: [String: Any] = ["url": original.absoluteString, "method": method, "headers": headers]
        if let data = request.httpBody { body["bodyBase64"] = data.base64EncodedString() }
        dispatched += 1
        let response = try JSONDecoder().decode(ProductionLocalFixture.WireResponse.self,
            from: await local("/request", body: JSONSerialization.data(withJSONObject: body)))
        let data = Data(base64Encoded: response.bodyBase64)
        let statusValid = (100...599).contains(response.status)
        let bodyValid = data.map { $0.count <= 655_360 } ?? false
        let headerNamesValid = response.headers.keys.allSatisfy({ $0 == $0.lowercased() })
        guard statusValid, bodyValid, headerNamesValid, let data else {
            print("PRODUCTION_LOCAL_ENVELOPE_REJECTED: status=\(response.status) statusValid=\(statusValid) bodyValid=\(bodyValid) headerNamesValid=\(headerNamesValid)")
            throw ProductionLocalFixture.Failure.response
        }
        return MediaHTTPResult(status: response.status, data: data, headers: response.headers)
    }
}
struct ProductionLocalAPITransport: HTTPTransport {
    let bridge: ProductionLocalBridge
    func send(_ request: URLRequest) async throws -> HTTPResult {
        let value = try await bridge.send(request)
        return HTTPResult(status: value.status, data: value.data)
    }
}
struct ProductionLocalMediaTransport: MediaHTTPTransport {
    let bridge: ProductionLocalBridge
    func send(_ request: URLRequest) async throws -> MediaHTTPResult { try await bridge.send(request) }
}
struct ProductionLocalFormBrowser: AuthenticationBrowser {
    let bridge: ProductionLocalBridge
    let identity: ProductionLocalFixture.Identity
    @MainActor func authorize(url: URL, callback: URL) async throws -> URL {
        _ = try ProductionLocalFixture.validate(url); _ = try ProductionLocalFixture.validate(callback)
        guard url.path == "/auth/mobile/authorize", callback.path == "/auth/mobile/callback" else { throw ProductionLocalFixture.Failure.boundary }
        let page = try await bridge.send(URLRequest(url: url))
        guard page.status == 200, let html = String(data: page.data, encoding: .utf8), !html.contains("Test accounts only"),
              let range = html.range(of: #"name="flow" value="[a-f0-9-]{36}""#, options: .regularExpression),
              let cookie = page.header("set-cookie"),
              cookie.range(of: #"^__Host-station-native-flow=[A-Za-z0-9_-]{43};"#, options: .regularExpression) != nil,
              cookie.lowercased().contains("; secure"), cookie.lowercased().contains("; httponly") else { throw ProductionLocalFixture.Failure.response }
        let flow = String(html[range]).components(separatedBy: "value=\"")[1].dropLast()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let pairs = ["flow": String(flow), "locale": "en", "identifier": identity.identifier, "password": identity.password, "totpCode": ""]
        let body = pairs.sorted(by: { $0.key < $1.key }).map { key, value in
            key + "=" + value.addingPercentEncoding(withAllowedCharacters: allowed)!
        }.joined(separator: "&")
        var request = URLRequest(url: ProductionLocalFixture.origin.appending(path: "auth/mobile/authorize")); request.httpMethod = "POST"
        request.setValue(ProductionActivationProfile.origin, forHTTPHeaderField: "Origin")
        request.setValue(String(cookie.split(separator: ";", maxSplits: 1)[0]), forHTTPHeaderField: "Cookie")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        let result = try await bridge.send(request)
        guard result.status == 302, let location = result.header("location"), let returned = URL(string: location),
              returned.path == callback.path else { throw ProductionLocalFixture.Failure.response }
        return try ProductionLocalFixture.validate(returned)
    }
}
