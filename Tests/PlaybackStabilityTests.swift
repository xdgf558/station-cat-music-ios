import XCTest
@testable import StationCatMusic

private struct StabilityFixture: Decodable { let vip: ProbeIdentity; let free: ProbeIdentity }
private actor StabilityAuthorization: PlaybackAuthorizing {
    enum Fault { case none, reject, late }
    let base: ProbeAuthorizer
    let fast: Bool
    private(set) var requests = 0
    private(set) var variants: [String] = []
    private(set) var urls = Set<URL>()
    private var completed = 0
    func progress() -> (requests: Int, completed: Int, unique: Int) { (requests, completed, urls.count) }
    private var fault: Fault = .none
    private var current = true
    init(_ identity: ProbeIdentity, bridge: MusicProbeBridge, fast: Bool = false) {
        base = ProbeAuthorizer(identity: identity, bridge: bridge, shortDeadline: false); self.fast = fast
    }
    func setFault(_ value: Fault) { fault = value }
    func invalidate() { current = false }
    func authorize(track: Track, variant: String) async throws -> AuthorizedPlayback {
        requests += 1; variants.append(variant)
        if fault == .reject { throw APIError.rejected(503) }
        let result = try await base.authorize(track: track, variant: variant)
        if fault == .late { await Task.detached { try? await Task.sleep(for: .seconds(10)) }.value }
        let g = result.grant
        urls.insert(g.playbackUrl); completed += 1
        if !fast { return result }
        // Fault cases only tighten client deadlines. Server time, grant and 60s revalidation stay unchanged.
        let end = min(g.playbackValidUntil, result.serverNow.addingTimeInterval(9))
        let early = min(g.revalidateAt, end, result.serverNow.addingTimeInterval(5))
        let grant = PlaybackGrant(playbackUrl: g.playbackUrl, expiresAt: end, playbackValidUntil: end, revalidateAt: early,
            durationSeconds: g.durationSeconds, previewSourceStartSeconds: g.previewSourceStartSeconds, authMode: g.authMode,
            accountID: g.accountID, sessionID: g.sessionID, trackID: g.trackID, audioVersion: g.audioVersion, variant: g.variant)
        return AuthorizedPlayback(grant: grant, serverNow: result.serverNow, context: result.context, scope: result.scope)
    }
    func isCurrent(_ authorization: AuthorizedPlayback) -> Bool { current }
    func bearer(for authorization: AuthorizedPlayback, refresh: Bool) async throws -> String? {
        guard current else { throw APIError.staleResponse }
        return try await base.bearer(for: authorization, refresh: refresh)
    }
}
private actor StabilityMedia: MediaHTTPTransport {
    let bridge: MusicProbeBridge
    private var offline = false
    private(set) var reads = 0
    let delay: Duration
    init(_ bridge: MusicProbeBridge, delay: Duration = .zero) { self.bridge = bridge; self.delay = delay }
    func disconnect() { offline = true }
    func send(_ request: URLRequest) async throws -> MediaHTTPResult {
        reads += 1
        if offline { throw URLError(.notConnectedToInternet) }
        try await Task.sleep(for: delay)
        return try await bridge.send(request)
    }
}
@MainActor final class PlaybackStabilityTests: XCTestCase {
    private func bridge() throws -> MusicProbeBridge {
        let env = ProcessInfo.processInfo.environment
        guard let value = env["M3_PROBE_PORT"], let port = Int(value), let key = env["M3_PROBE_KEY"] else { throw XCTSkip("Dedicated isolated long-playback probe only") }
        return MusicProbeBridge(port: port, key: key)
    }
    private func track(_ identity: ProbeIdentity, access: AccessPolicy = .free) -> Track {
        Track(id: identity.trackId, title: "Three minute synthesized sine", artist: "Local fixture", durationSeconds: identity.durationSeconds!, audioVersion: 1, access: access)
    }
    private func wait(_ seconds: Double = 8, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(condition(), "Condition did not settle within \(seconds) seconds")
    }
    func testLongTrackTwoRealRenewalsPreservePositionAndFreshURLs() async throws {
        let bridge = try bridge(), fixture = try await bridge.fixture("stability", as: StabilityFixture.self)
        let source = StabilityAuthorization(fixture.vip, bridge: bridge), media = StabilityMedia(bridge, delay: .milliseconds(120))
        let player = PlaybackService(transport: media); defer { player.deny() }
        player.configure(authorizer: source); player.select(track(fixture.vip, access: .vip)); player.requestPlay()
        try await wait { player.isPlaying && player.position > 0.2 }
        player.seek(to: 30); try await wait { player.isPlaying && player.position >= 29.9 }
        player.pause(); let paused = player.position
        player.requestPlay(); try await wait { player.isPlaying && player.position >= paused - 0.1 }
        let baseline = await source.requests, started = ContinuousClock.now
        var previous = player.position, backward: Double = 0, longestStall: Double = 0, stillSince = ContinuousClock.now
        while started.duration(to: .now) < .seconds(135) {
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertEqual(player.state, .playing)
            if player.state != .playing { break }
            backward = max(backward, previous - player.position)
            if player.position > previous + 0.01 { stillSince = .now }
            let stalled = stillSince.duration(to: .now).components
            longestStall = max(longestStall, Double(stalled.seconds) + Double(stalled.attoseconds) / 1e18)
            previous = player.position
            // Playback stays .playing while renewal is in flight. A request count
            // is not evidence of a returned grant; wait for both real responses.
            let progress = await source.progress()
            if progress.completed >= baseline + 2, progress.completed == progress.requests,
               player.isPlaying, player.position > paused + 115 { break }
        }
        let progress = await source.progress(), reads = await media.reads
        let requests = progress.requests, unique = progress.unique
        XCTAssertGreaterThanOrEqual(progress.completed, baseline + 2)
        XCTAssertEqual(progress.completed, requests); XCTAssertEqual(unique, requests)
        XCTAssertGreaterThan(player.position, paused + 115); XCTAssertLessThan(backward, 0.4)
        XCTAssertLessThan(longestStall, 5); XCTAssertGreaterThan(reads, 6)
        XCTAssertGreaterThanOrEqual(started.duration(to: .now), .seconds(110))
        print("M3_LONG_RENEWAL_PASSED: real 60s cadence twice; unique grants=\(unique); backward=\(backward); maxStall=\(longestStall)")
    }
    func testRenewalFailureStopsAndLateRenewalCannotRestart() async throws {
        let bridge = try bridge(), fixture = try await bridge.fixture("stability", as: StabilityFixture.self)
        for fault in [StabilityAuthorization.Fault.reject, .late] {
            let source = StabilityAuthorization(fixture.free, bridge: bridge, fast: true), player = PlaybackService(transport: bridge)
            player.configure(authorizer: source); player.select(track(fixture.free)); player.requestPlay()
            try await wait { player.isPlaying && player.position > 0.1 }
            await source.setFault(fault)
            try await wait(10) { player.state == .verificationRequired }
            XCTAssertFalse(player.hasAudioSource); XCTAssertFalse(player.isPlaying)
            if fault == .late { try await Task.sleep(for: .seconds(8)) }
            XCTAssertEqual(player.state, .verificationRequired); XCTAssertFalse(player.hasAudioSource)
            let count = await source.requests
            XCTAssertEqual(count, 2, "Failed renewal must not schedule automatic retries")
            player.deny()
        }
        print("M3_RENEWAL_FAILURE_PASSED: 503 stops; old deadline wins over late response; no auto-restart")
    }
    func testPauseSwitchAndLogoutDuringRenewalRejectLateResult() async throws {
        let bridge = try bridge(), fixture = try await bridge.fixture("stability", as: StabilityFixture.self)
        for action in 0...2 {
            let source = StabilityAuthorization(fixture.free, bridge: bridge, fast: true), player = PlaybackService(transport: bridge)
            player.configure(authorizer: source); player.select(track(fixture.free)); player.requestPlay()
            try await wait { player.isPlaying && player.position > 0.1 }; await source.setFault(.late)
            for _ in 0..<60 { if await source.requests == 2 { break }; try await Task.sleep(for: .milliseconds(100)) }
            let attempts = await source.requests; XCTAssertEqual(attempts, 2)
            if action == 0 { player.pause() }
            else if action == 1 { player.select(track(fixture.vip, access: .vip)) }
            else { await source.invalidate(); player.deny() }
            try await Task.sleep(for: .seconds(11))
            XCTAssertFalse(player.hasAudioSource); XCTAssertFalse(player.isPlaying)
            XCTAssertEqual(player.state, action == 0 ? .paused : action == 1 ? .selected : .verificationRequired)
        }
        print("M3_LATE_RENEWAL_PASSED: pause, track switch and logout all reject late responses")
    }
    func testOfflineRangeAndRapidSeekSwitchFailClosed() async throws {
        let bridge = try bridge(), fixture = try await bridge.fixture("stability", as: StabilityFixture.self)
        let source = StabilityAuthorization(fixture.free, bridge: bridge), media = StabilityMedia(bridge)
        let player = PlaybackService(transport: media); defer { player.deny() }
        player.configure(authorizer: source)
        player.select(track(fixture.free)); player.requestPlay(variant: "preview")
        try await wait { player.isPlaying && player.position > 0.1 }
        player.pause(); player.requestPlay()
        try await wait { player.isPlaying && player.position > 0.1 }
        XCTAssertLessThan(player.duration, 2)
        let variants = await source.variants; XCTAssertEqual(variants, ["preview", "preview"])
        player.pause()
        for _ in 0..<3 {
            player.select(track(fixture.free)); player.requestPlay()
            try await wait { player.isPlaying && player.position > 0.1 }
            player.seek(to: 120); player.seek(to: 10); player.seek(to: 60)
            try await wait { player.isPlaying && player.position >= 59.9 && player.position < 65 }
            player.pause(); player.requestPlay()
            try await wait { player.isPlaying && player.position >= 59.9 }
        }
        await media.disconnect(); player.pause(); player.requestPlay()
        try await wait { player.state == .verificationRequired }
        XCTAssertFalse(player.hasAudioSource); XCTAssertFalse(player.isPlaying)
        print("M3_OFFLINE_SEEK_PASSED: rapid seek/resume/switch; failed range removes item")
    }
    func testZZRealLimitedFreeAndVIPExpiryClearBufferedPlayback() async throws {
        let bridge = try bridge(), fixture = try await bridge.fixture("stability", as: StabilityFixture.self)
        let limited = try await bridge.fixture("stability/limited", as: ProbeIdentity.self)
        for identity in [limited, fixture.vip] {
            if identity.trackId == fixture.vip.trackId { let _: [String:String] = try await bridge.fixture("stability/expiry", as: [String:String].self) }
            let source = StabilityAuthorization(identity, bridge: bridge), player = PlaybackService(transport: bridge)
            player.configure(authorizer: source); player.select(track(identity, access: identity.trackId == limited.trackId ? .free : .vip)); player.requestPlay()
            try await wait { player.isPlaying && player.position > 0.1 }
            try await wait(14) { player.state == .verificationRequired }
            XCTAssertFalse(player.hasAudioSource); XCTAssertFalse(player.isPlaying)
            // Wait past the actual server boundary, then ask the real Worker again.
            try await Task.sleep(for: .seconds(3))
            do { _ = try await source.authorize(track: track(identity), variant: "full"); XCTFail("Expired policy allowed full playback") } catch { XCTAssertEqual(error as? APIError, .rejected(403)) }
            player.deny()
        }
        print("M3_POLICY_EXPIRY_PASSED: real server limited-free and VIP expiry; buffered player stops")
    }
}
