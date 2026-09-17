import XCTest
@testable import StationCatMusic

// Test-only loopback mapping. No HTTP origin or ATS exception is added to the App.
private struct MusicProbeBridge: HTTPTransport, MediaHTTPTransport {
    let port: Int; let key: String
    private func local(_ request: URLRequest) throws -> URLRequest {
        guard request.url?.host == "native.local.test", let path = request.url?.path else { throw APIError.invalidRequest }
        var copy = request
        var c = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        c.scheme = "http"; c.host = "127.0.0.1"; c.port = port; c.path = path
        copy.url = c.url; copy.setValue(key, forHTTPHeaderField: "X-Probe-Key"); return copy
    }
    func send(_ request: URLRequest) async throws -> HTTPResult { try await URLSessionTransport().send(local(request)) }
    func send(_ request: URLRequest) async throws -> MediaHTTPResult { try await NativeMediaTransport().send(local(request)) }
    func fixture<T: Decodable>(_ path: String, as: T.Type) async throws -> T {
        let request = URLRequest(url: URL(string: "https://native.local.test/fixture/" + path)!)
        let result: HTTPResult = try await send(request)
        guard result.status == 200 else { throw APIError.rejected(result.status) }; return try JSONDecoder().decode(T.self, from: result.data)
    }
}
private struct FeaturedExpectation: Decodable { let primaryTrackId: String; let trackIds: [String]; let collectionIds: [String] }
private struct ProbeIdentity: Decodable, Sendable { let accountId: String; let sessionId: String; let token: String; let trackId: String }
private struct ProbeRequest: Decodable { let method: String; let range: String?; let bearerMatched: Bool; let status: Int; let r2Reads: Int }
private struct ProbeAuthorizer: PlaybackAuthorizing {
    let identity: ProbeIdentity; let bridge: MusicProbeBridge; let shortDeadline: Bool
    func authorize(track: Track, variant: String) async throws -> AuthorizedPlayback {
        var request = URLRequest(url: URL(string: "https://native.local.test/api/mobile/v1/music/tracks/" + track.id + "/playback-grants")!)
        request.httpMethod = "POST"; request.setValue("Bearer " + identity.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["audioVersion": 1, "variant": variant])
        let result: HTTPResult = try await bridge.send(request)
        guard result.status == 200 else { throw APIError.rejected(result.status) }
        let response = try NativeJSON.decoder().decode(NativeResponse<PlaybackGrant>.self, from: result.data)
        var grant = response.data
        if shortDeadline {
            // A tighter client-only deadline exercises buffered playback cut-off; never widens server validity.
            let end = response.serverNow.addingTimeInterval(3)
            grant = PlaybackGrant(playbackUrl: grant.playbackUrl, expiresAt: end, playbackValidUntil: end, revalidateAt: end, durationSeconds: grant.durationSeconds,
                previewSourceStartSeconds: grant.previewSourceStartSeconds, authMode: grant.authMode, accountID: grant.accountID, sessionID: grant.sessionID, trackID: grant.trackID, audioVersion: grant.audioVersion, variant: grant.variant)
        }
        let scope = AccountScope(environment: .development, accountID: identity.accountId)
        try grant.validate(serverNow: response.serverNow, scope: scope, session: identity.sessionId, track: track, allowedHosts: ["native.local.test"])
        return AuthorizedPlayback(grant: grant, serverNow: response.serverNow, context: NativeAuthContext(epoch: 0, scope: scope, bearer: identity.token, sessionID: identity.sessionId), scope: scope)
    }
    func isCurrent(_ authorization: AuthorizedPlayback) -> Bool { true }
    func bearer(for authorization: AuthorizedPlayback, refresh: Bool) -> String? { identity.token }
}
@MainActor final class NativeMediaIntegrationTests: XCTestCase {
    func testRealAVPlayerRangeAndHardStopAgainstIsolatedWorker() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["M3_PROBE_PORT"], let port = Int(raw), let key = env["M3_PROBE_KEY"] else { throw XCTSkip("Dedicated isolated Worker probe only") }
        let bridge = MusicProbeBridge(port: port, key: key), identity = try await bridge.fixture("bootstrap", as: ProbeIdentity.self)
        let track = Track(id: identity.trackId, title: "Synthetic sine", artist: "Local fixture", durationSeconds: 4.049, audioVersion: 1, access: .vip)
        let player = PlaybackService(transport: bridge)
        player.configure(authorizer: ProbeAuthorizer(identity: identity, bridge: bridge, shortDeadline: false))
        player.select(track); player.requestPlay()
        for _ in 0..<50 { if player.position > 0.15 { break }; try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(player.hasAudioSource); XCTAssertTrue(player.isPlaying); XCTAssertGreaterThan(player.position, 0.15)
        player.seek(to: 2)
        try await Task.sleep(for: .milliseconds(400)); XCTAssertGreaterThan(player.position, 1.5)
        player.pause(); XCTAssertFalse(player.hasAudioSource); XCTAssertFalse(player.isPlaying)
        // A manual pause retains its resume point.
        player.requestPlay()
        for _ in 0..<50 { if player.isPlaying && player.position > 1.5 { break }; try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(player.isPlaying); XCTAssertGreaterThan(player.position, 1.5)
        player.pause()
        // Listen to the entire short fixture: completion must differ from pause.
        player.select(track); player.requestPlay()
        for _ in 0..<100 { if player.state == .completed { break }; try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(player.state, .completed); XCTAssertEqual(player.position, 0)
        XCTAssertFalse(player.hasAudioSource); XCTAssertFalse(player.isPlaying)
        player.requestPlay()
        for _ in 0..<50 { if player.position > 0.15 { break }; try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(player.isPlaying); XCTAssertGreaterThan(player.position, 0.15); XCTAssertLessThan(player.position, 1.5)
        player.pause()
        player.configure(authorizer: ProbeAuthorizer(identity: identity, bridge: bridge, shortDeadline: true))
        player.select(track); player.requestPlay(); try await Task.sleep(for: .seconds(2))
        XCTAssertFalse(player.hasAudioSource); XCTAssertFalse(player.isPlaying); XCTAssertEqual(player.state, .verificationRequired)
        let evidence = try await bridge.fixture("evidence", as: [ProbeRequest].self)
        let ranges = evidence.filter { $0.range != nil }
        XCTAssertFalse(ranges.isEmpty); XCTAssertTrue(ranges.allSatisfy { $0.bearerMatched && $0.status == 206 })
        XCTAssertTrue(evidence.contains { $0.method == "HEAD" && $0.bearerMatched && $0.status == 200 })
        let authorization = try await ProbeAuthorizer(identity: identity, bridge: bridge, shortDeadline: false).authorize(track: track, variant: "full")
        let _: [String: String] = try await bridge.fixture("revoke", as: [String: String].self)
        let channel = AuthorizedMediaChannel(authorization: authorization, authorizer: ProbeAuthorizer(identity: identity, bridge: bridge, shortDeadline: false), transport: bridge, lifetime: 30)
        do { _ = try await channel.read(start: 0, length: 2, total: 65245); XCTFail("Revoked session delivered audio") } catch {}
        let after = try await bridge.fixture("evidence", as: [ProbeRequest].self)
        XCTAssertTrue(after.suffix(2).allSatisfy { $0.status == 401 && $0.r2Reads == 0 })
        print("M3_NATIVE_MEDIA_PASSED: actual AVPlayer advancement, natural-end replay, manual-pause resume, seek, HEAD/Range Bearer, buffered hard-stop, revoked-session denial")
    }
    func testConfiguredFeaturedReachesNativeDiscoveryFromRealWorker() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["M3_PROBE_PORT"], let port = Int(raw), let key = env["M3_PROBE_KEY"] else { throw XCTSkip("Dedicated isolated Worker probe only") }
        let bridge = MusicProbeBridge(port: port, key: key)
        let expected = try await bridge.fixture("featured", as: FeaturedExpectation.self)
        let config = try NativeAuthConfiguration(environment: .development, origin: URL(string: "https://native.local.test")!, explicitlyEnabled: true)
        let native = try NativeMusicAPI(configuration: config, explicitlyEnabled: true, transport: bridge)
        let model = AppModel(client: native)
        await model.load()
        XCTAssertEqual(model.discoveryPhase, .loaded)
        XCTAssertFalse(model.tracks.prefix(6).contains { $0.id == expected.primaryTrackId })
        XCTAssertEqual(model.discoveryTracks.map(\.id), expected.trackIds)
        XCTAssertEqual(model.collections.map(\.id), expected.collectionIds)
        // Catalog search/collection selection must not replace curated discovery.
        model.query = "no matching catalog result"
        model.activeCollection = model.collections.first
        XCTAssertEqual(model.discoveryTracks.map(\.id), expected.trackIds)
        let _: [String: String] = try await bridge.fixture("featured-clear", as: [String: String].self)
        await model.load()
        XCTAssertFalse(model.tracks.isEmpty); XCTAssertTrue(model.discoveryTracks.isEmpty)
        XCTAssertTrue(model.collections.isEmpty); XCTAssertEqual(model.discoveryPhase, .empty)
        print("M3_FEATURED_PASSED: configured oldest primary reaches AppModel discovery; cleared recommendations stay empty")
    }

}
