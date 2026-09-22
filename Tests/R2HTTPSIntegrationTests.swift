import XCTest
@testable import StationCatMusic

// Explicit, test-only public HTTPS probe. The browser below drives the real login
// form over URLSession; it does NOT verify ASWebAuthenticationSession, AASA,
// Universal Links, physical-device Keychain, or background/locked playback.
private enum R2Probe {
    static let origin = URL(string: "https://station-cat-music-r2.yehao1105.workers.dev")!
    enum Failure: Error { case input, boundary, response, assertion }
    static func require(_ condition: Bool) throws { if !condition { throw Failure.assertion } }
    static func url(_ url: URL?) throws -> URL {
        guard let url, let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme == "https", c.host == origin.host, c.port == nil,
              c.user == nil, c.password == nil, c.fragment == nil else { throw Failure.boundary }
        return url
    }
    struct Identity: Decodable, Sendable { let username: String; let password: String }
    struct Tracks: Decodable, Sendable { let free: String; let vip: String }
    struct Input: Decodable, Sendable {
        let origin: String; let free: Identity; let vip: Identity; let tracks: Tracks
        let collectionSlug: String; let allowTestLibraryReset: Bool
    }
    static func input() throws -> Input {
        let env = ProcessInfo.processInfo.environment
        guard env["R2_ENABLE_NATIVE_HTTPS"] == "YES" else { throw XCTSkip("Explicit isolated R2 HTTPS probe only") }
        guard let path = env["R2_PRIVATE_INPUT"], path.hasPrefix("/") else { throw Failure.input }
        let file = URL(fileURLWithPath: path)
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard attrs[.type] as? FileAttributeType == .typeRegular, values.isSymbolicLink != true,
              (attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600,
              ((attrs[.size] as? NSNumber)?.intValue ?? Int.max) <= 8192 else { throw Failure.input }
        let value = try JSONDecoder().decode(Input.self, from: Data(contentsOf: file))
        guard value.origin == origin.absoluteString, value.allowTestLibraryReset,
              value.free.username == "r2tester-free", value.vip.username == "r2tester-vip",
              (16...256).contains(value.free.password.count), (16...256).contains(value.vip.password.count),
              UUID(uuidString: value.tracks.free) != nil, UUID(uuidString: value.tracks.vip) != nil,
              value.tracks.free != value.tracks.vip, value.collectionSlug == "r2-synthetic-album" else { throw Failure.input }
        return value
    }
    static func category(_ error: Error) -> String {
        if let error = error as? URLError { return "url_error_\(error.code.rawValue)" }
        if let error = error as? NativeFailure { return "native_http_\(error.status)" }
        if error is DecodingError { return "decoding" }
        if error is Failure { return "probe_assertion" }
        if error is APIError { return "api_error" }
        if error is CancellationError { return "cancelled" }
        return "other" // Never print localized errors, URLs, credentials or response bodies.
    }
}

private struct R2APITransport: HTTPTransport {
    let underlying = URLSessionTransport()
    func send(_ request: URLRequest) async throws -> HTTPResult {
        _ = try R2Probe.url(request.url)
        return try await underlying.send(request)
    }
}
private actor R2MediaTransport: MediaHTTPTransport {
    private let underlying = NativeMediaTransport()
    private(set) var heads = 0
    private(set) var ranges = 0
    func send(_ request: URLRequest) async throws -> MediaHTTPResult {
        _ = try R2Probe.url(request.url)
        let result = try await underlying.send(request)
        if request.httpMethod == "HEAD", result.status == 200 { heads += 1 }
        if request.httpMethod == "GET", request.value(forHTTPHeaderField: "Range") != nil, result.status == 206 { ranges += 1 }
        return result
    }
}
private struct R2FormBrowser: AuthenticationBrowser {
    let identity: R2Probe.Identity
    @MainActor func authorize(url: URL, callback: URL) async throws -> URL {
        _ = try R2Probe.url(url); _ = try R2Probe.url(callback)
        guard url.path == "/auth/mobile/authorize", callback.path == "/auth/mobile/callback" else { throw R2Probe.Failure.boundary }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 10; config.timeoutIntervalForResource = 15
        let session = URLSession(configuration: config, delegate: RejectRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        func read(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            _ = try R2Probe.url(request.url)
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let response = response as? HTTPURLResponse, response.url == request.url else { throw R2Probe.Failure.response }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 65_536 else { throw R2Probe.Failure.response }
                data.append(byte)
            }
            return (data, response)
        }
        let (data, page) = try await read(URLRequest(url: url))
        guard page.statusCode == 200, let html = String(data: data, encoding: .utf8), html.contains("Test accounts only"),
              let range = html.range(of: #"name="flow" value="[a-f0-9-]{36}""#, options: .regularExpression),
              let cookie = page.value(forHTTPHeaderField: "Set-Cookie"),
              cookie.range(of: #"^__Host-station-native-flow=[A-Za-z0-9_-]{43};"#, options: .regularExpression) != nil,
              cookie.lowercased().contains("; secure"), cookie.lowercased().contains("; httponly") else { throw R2Probe.Failure.response }
        let flow = String(html[range]).components(separatedBy: "value=\"")[1].dropLast()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let pairs = ["flow": String(flow), "locale": "en", "identifier": identity.username, "password": identity.password, "totpCode": ""]
        let body = pairs.sorted(by: { $0.key < $1.key }).map { key, value in
            key + "=" + value.addingPercentEncoding(withAllowedCharacters: allowed)!
        }.joined(separator: "&")
        var request = URLRequest(url: R2Probe.origin.appending(path: "auth/mobile/authorize")); request.httpMethod = "POST"
        request.setValue(R2Probe.origin.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(String(cookie.split(separator: ";", maxSplits: 1)[0]), forHTTPHeaderField: "Cookie")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        let (_, result) = try await read(request)
        guard result.statusCode == 302, let location = result.value(forHTTPHeaderField: "Location"),
              let returned = URL(string: location), returned.path == callback.path else { throw R2Probe.Failure.response }
        return try R2Probe.url(returned) // Real PKCEFlow validates code and state, then NativeAuthAPI exchanges them.
    }
}

@MainActor final class R2HTTPSIntegrationTests: XCTestCase {
    func testExplicitNativeHTTPSAuthenticationPlaybackAndLibrary() async throws {
        // Skip happens before any network or private input read in ordinary CI.
        guard ProcessInfo.processInfo.environment["R2_ENABLE_NATIVE_HTTPS"] == "YES" else { throw XCTSkip("Explicit isolated R2 HTTPS probe only") }
        var stage = "private_input"
        var sessions: [NativeAuthenticationService] = []
        var cleanup: (() async throws -> Void)?
        var player: PlaybackService?
        var failed = false
        do {
            let input = try R2Probe.input()
            let config = try NativeAuthConfiguration(environment: .staging, origin: R2Probe.origin, explicitlyEnabled: true)
            let transport = R2APITransport()
            func signIn(_ identity: R2Probe.Identity) async throws -> NativeAuthenticationService {
                let auth = NativeAuthenticationService(configuration: config, api: NativeAuthAPI(configuration: config, transport: transport),
                    journal: AuthJournal(store: MemorySecureStore(), environment: .staging), browser: R2FormBrowser(identity: identity))
                sessions.append(auth)
                try await auth.signIn(locale: "en")
                return auth
            }
            stage = "form_pkce_login"
            let auth = try await signIn(input.free), peerAuth = try await signIn(input.free), vipAuth = try await signIn(input.vip)
            guard case let .authenticated(scope) = await auth.state(),
                  case let .authenticated(peerScope) = await peerAuth.state(),
                  case let .authenticated(vipScope) = await vipAuth.state() else { throw R2Probe.Failure.assertion }
            try R2Probe.require(scope == peerScope && scope != vipScope)
            stage = "refresh"
            _ = try await auth.accessToken(forceRefresh: true)
            let music = try NativeMusicAPI(configuration: config, explicitlyEnabled: true, transport: transport, auth: auth)
            let vipMusic = try NativeMusicAPI(configuration: config, explicitlyEnabled: true, transport: transport, auth: vipAuth)
            stage = "catalog_album_lyrics"
            let catalog = try await music.catalog()
            guard let track = catalog.items.first(where: { $0.id == input.tracks.free }),
                  let vipTrack = catalog.items.first(where: { $0.id == input.tracks.vip }) else { throw R2Probe.Failure.assertion }
            let detail = try await music.detail(track, locale: "en")
            try R2Probe.require(detail.lyrics.kind == "timed" && detail.lyrics.lines.count >= 2 && detail.lyrics.audioVersion == track.audioVersion)
            let album = try await music.resolveCollection(input.collectionSlug)
            try R2Probe.require(Set(album.tracks.map(\.id)) == [track.id, vipTrack.id])
            stage = "vip_permissions"
            var denied = false
            do { _ = try await music.authorize(track: vipTrack, variant: "full") }
            catch APIError.rejected(let status) { denied = [401, 403].contains(status) }
            try R2Probe.require(denied)
            let vipGrant = try await vipMusic.authorize(track: vipTrack, variant: "full")
            try R2Probe.require(vipGrant.scope == vipScope && vipGrant.grant.variant == "full")

            let remote = try NativeLibraryAPI(configuration: config, explicitlyEnabled: true, auth: auth, transport: transport)
            let peer = try NativeLibraryAPI(configuration: config, explicitlyEnabled: true, auth: peerAuth, transport: transport)
            let other = try NativeLibraryAPI(configuration: config, explicitlyEnabled: true, auth: vipAuth, transport: transport)
            let local = ScopedLibrary(), replica = ScopedLibrary()
            stage = "library_baseline"
            let initial = try await remote.snapshot(scope: scope), otherInitial = try await other.snapshot(scope: vipScope)
            let originalFavorite = initial.favorites.first(where: { $0.trackId == track.id })?.favorite ?? false
            cleanup = {
                try await local.synchronize(scope: scope, remote: remote)
                try await local.clearHistory(scope: scope)
                try await local.setFavorite(track.id, value: originalFavorite, scope: scope)
                try await local.setHistory(initial.preferences.historyEnabled, scope: scope)
                try await local.synchronize(scope: scope, remote: remote)
            }
            try await local.synchronize(scope: scope, remote: remote)
            try await local.clearHistory(scope: scope)
            try await local.setHistory(true, scope: scope)
            try await local.setFavorite(track.id, value: true, scope: scope)
            try await local.synchronize(scope: scope, remote: remote)
            try await replica.synchronize(scope: scope, remote: peer)
            let favoriteView = try await replica.view(in: scope)
            try R2Probe.require(favoriteView.favorites.contains(track.id) && favoriteView.pending == 0)

            stage = "avplayer_https"
            let media = R2MediaTransport(), activePlayer = PlaybackService(transport: media)
            player = activePlayer
            var heard: (audible: Double, position: Double, id: String)?
            activePlayer.onListen = { _, _, audible, position, id in heard = (audible, position, id) }
            activePlayer.configure(authorizer: music); activePlayer.select(track); activePlayer.requestPlay()
            let clock = ContinuousClock(), deadline = clock.now.advanced(by: .seconds(30))
            while clock.now < deadline && (heard == nil || activePlayer.position < 5.1) {
                try await Task.sleep(for: .milliseconds(100))
            }
            let advanced = activePlayer.position, wasPlaying = activePlayer.isPlaying
            activePlayer.pause()
            guard let heard else { throw R2Probe.Failure.assertion }
            try R2Probe.require(wasPlaying && advanced >= 5.1 && heard.audible >= 5)
            let heads = await media.heads, ranges = await media.ranges
            try R2Probe.require(heads > 0 && ranges > 0 && detail.lyrics.current(at: advanced) != nil)

            stage = "audible_history_sync"
            try await local.record(track, variant: "full", audible: heard.audible, position: heard.position, eventID: heard.id, scope: scope)
            try await local.synchronize(scope: scope, remote: remote)
            try await replica.synchronize(scope: scope, remote: peer)
            let recent = try await replica.view(in: scope), otherAfter = try await other.snapshot(scope: vipScope)
            try R2Probe.require(recent.pending == 0 && recent.recent.first?.trackId == track.id && (recent.recent.first?.positionSeconds ?? 0) >= 5)
            try R2Probe.require(otherAfter.favorites == otherInitial.favorites && otherAfter.recent == otherInitial.recent && otherAfter.preferences == otherInitial.preferences)
            print("R2_NATIVE_HTTP_PASSED: form_PKCE=true refresh=true catalog=true album=true lyrics=true vip_boundary=true avplayer_seconds=\(Int(advanced)) head=\(heads) range=\(ranges) favorites=true recent=true account_isolation=true")
        } catch {
            failed = true
            XCTFail("R2_NATIVE_FAILED stage=\(stage) category=\(R2Probe.category(error))")
        }
        player?.shutdown()
        do { try await cleanup?() } catch {
            failed = true; XCTFail("R2_NATIVE_FAILED stage=library_cleanup category=\(R2Probe.category(error))")
        }
        for auth in sessions {
            do { try await auth.signOut() } catch {
                failed = true; XCTFail("R2_NATIVE_FAILED stage=logout_cleanup category=\(R2Probe.category(error))")
            }
        }
        if !failed { print("R2_NATIVE_HTTPS_PASSED: synthetic_library_cleanup=true sessions_closed=true system_browser=false universal_links=false physical_device=false") }
    }
}
