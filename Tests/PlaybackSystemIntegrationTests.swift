import XCTest
import AVFoundation
import MediaPlayer
@testable import StationCatMusic

private struct RotationFixture: Decodable { let credential: CredentialEnvelope; let trackId: String; let durationSeconds: Double }
private struct RotationEvidence: Decodable { let generation: Int; let revoked: Int; let absoluteUntil: Double; let operations: [Int] }
private struct SystemFixture: Decodable { let vip: ProbeIdentity; let free: ProbeIdentity }
private struct NoBrowser: AuthenticationBrowser {
    @MainActor func authorize(url: URL, callback: URL) throws -> URL { throw APIError.networkDisabled }
}
// Test-only gate: hold the second authorization so the transitional UI state is deterministic.
private actor PreviewRepeatProbe: PlaybackAuthorizing {
    let base: NativeMusicAPI
    private(set) var requested: [String] = []
    private(set) var granted: [String] = []
    private(set) var holding = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    init(base: NativeMusicAPI) { self.base = base }
    func preferredVariant(for track: Track) async throws -> String { try await base.preferredVariant(for: track) }
    func authorize(track: Track, variant: String) async throws -> AuthorizedPlayback {
        requested.append(variant)
        if requested.count == 2 && !released {
            holding = true
            await withCheckedContinuation { continuation = $0 }
            holding = false
        }
        try Task.checkCancellation()
        let result = try await base.authorize(track: track, variant: variant)
        granted.append(result.grant.variant)
        return result
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
    func isCurrent(_ value: AuthorizedPlayback) async -> Bool { await base.isCurrent(value) }
    func bearer(for value: AuthorizedPlayback, refresh: Bool) async throws -> String? { try await base.bearer(for: value, refresh: refresh) }
}
@MainActor final class PlaybackSystemIntegrationTests: XCTestCase {
    private func bridge() throws -> MusicProbeBridge {
        let env = ProcessInfo.processInfo.environment
        guard let value = env["M3_PROBE_PORT"], let port = Int(value), let key = env["M3_PROBE_KEY"] else { throw XCTSkip("Dedicated M4 system and real auth rotation probe only") }
        return MusicProbeBridge(port: port, key: key)
    }
    private func track(_ identity: ProbeIdentity) -> Track {
        Track(id: identity.trackId, title: "M4 synthesized audio", artist: "Fixture", durationSeconds: identity.durationSeconds!, audioVersion: 1, access: .free)
    }
    private func wait(_ seconds: Double = 8, until condition: () -> Bool) async throws {
        let end = ContinuousClock.now.advanced(by: .seconds(seconds))
        while !condition(), ContinuousClock.now < end { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(condition())
    }
    func testSystemCommandsInterruptionsDisconnectAndReset() async throws {
        let bridge = try bridge(), fixture = try await bridge.fixture("stability", as: SystemFixture.self)
        let player = PlaybackService(transport: bridge)
        let system = SystemPlayback(playback: player, artworkHost: "native.local.test")
        player.attachSystem(system); defer { player.shutdown() }
        player.configure(authorizer: ProbeAuthorizer(identity: fixture.free, bridge: bridge, shortDeadline: false))
        player.setQueue([track(fixture.free), track(fixture.free)], startingAt: 0, play: false)
        player.handle(.play); try await wait { player.isPlaying && player.position > 0.1 }
        let firstID = player.queue.currentID
        player.handle(.seek(20)); try await wait { player.isPlaying && player.position >= 19.9 }
        player.handle(.pause); XCTAssertFalse(player.hasAudioSource); XCTAssertEqual(player.state, .paused)
        player.handle(.play); try await wait { player.isPlaying && player.position >= 19.9 }
        player.handle(.next); try await wait { player.isPlaying && player.queue.currentID != firstID }
        player.handle(.previous); try await wait { player.isPlaying && player.queue.currentID == firstID }
        let session = AVAudioSession.sharedInstance()
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: session, userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        XCTAssertEqual(player.state, .paused); XCTAssertFalse(player.hasAudioSource)
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: session, userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue, AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue])
        try await wait { player.isPlaying }
        player.interruptionBegan(); player.handle(.pause); player.interruptionEnded(shouldResume: true)
        try await Task.sleep(for: .milliseconds(300)); XCTAssertEqual(player.state, .paused); XCTAssertFalse(player.hasAudioSource)
        player.handle(.play); try await wait { player.isPlaying }
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: session, userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        XCTAssertEqual(player.state, .paused); XCTAssertFalse(player.hasAudioSource)
        player.handle(.play); try await wait { player.isPlaying }
        NotificationCenter.default.post(name: AVAudioSession.mediaServicesWereResetNotification, object: session)
        XCTAssertEqual(player.state, .paused); XCTAssertFalse(player.hasAudioSource)
        player.handle(.play); try await wait { player.isPlaying }
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String, "M4 synthesized audio")
        player.clear(); XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        print("M4_SYSTEM_PASSED: one player commands; notification interruption intent; route disconnect; reset requires play; Now Playing cleanup")
    }
    func testNaturalQueueRepeatSleepAndExpiredInterruption() async throws {
        let bridge = try bridge(), fixture = try await bridge.fixture("stability", as: SystemFixture.self)
        let player = PlaybackService(transport: bridge); defer { player.shutdown() }
        player.configure(authorizer: ProbeAuthorizer(identity: fixture.free, bridge: bridge, shortDeadline: false))
        var preview = track(fixture.free)
        preview = Track(id: preview.id, title: preview.title, artist: preview.artist, durationSeconds: preview.durationSeconds, audioVersion: 1, access: .preview)
        player.setQueue([preview, preview], startingAt: 0, play: false); let first = player.queue.currentID
        player.requestPlay(); try await wait { player.queue.currentID != first && player.isPlaying }
        try await wait { player.state == .completed }; XCTAssertEqual(player.position, 0)
        player.setRepeat(.one); player.setSleepTimer(seconds: 3); player.requestPlay()
        try await wait(5) { player.noticeKey == "sleepFinished" }; XCTAssertFalse(player.hasAudioSource)
        player.configure(authorizer: ProbeAuthorizer(identity: fixture.free, bridge: bridge, shortDeadline: true))
        player.select(track(fixture.free)); player.requestPlay(); try await wait { player.isPlaying }
        player.interruptionBegan(); try await Task.sleep(for: .seconds(2)); player.interruptionEnded(shouldResume: true)
        XCTAssertFalse(player.hasAudioSource); XCTAssertFalse(player.isPlaying)
        print("M4_QUEUE_SLEEP_PASSED: natural advance; repeat uses new grants; sleep stops; expired interruption cannot auto-resume")
    }
    func testMusicLinksResolveWithoutAutoplay() async throws {
        let bridge = try bridge(), fixture = try await bridge.fixture("stability", as: SystemFixture.self)
        let config = try NativeAuthConfiguration(environment: .development, origin: URL(string: "https://native.local.test")!, explicitlyEnabled: true)
        let native = try NativeMusicAPI(configuration: config, explicitlyEnabled: true, transport: bridge)
        let model = AppModel(client: native, musicWebOrigin: URL(string: "https://public.native.local.test")!)
        let previewTrack = Track(id: fixture.vip.trackId, title: "VIP preview", artist: "Fixture", durationSeconds: fixture.vip.durationSeconds!, audioVersion: 1, access: .preview)
        let guestVariant = try await native.preferredVariant(for: previewTrack); XCTAssertEqual(guestVariant, "preview")
        await model.openMusicLink(URL(string: "https://public.native.local.test/music/?track=" + fixture.free.trackId)!)
        XCTAssertEqual(model.playback.selectedTrack?.id, fixture.free.trackId); XCTAssertNotNil(model.detail)
        XCTAssertEqual(model.playback.state, .selected); XCTAssertFalse(model.playback.hasAudioSource)
        XCTAssertEqual(model.trackShareURL?.host, "public.native.local.test")
        XCTAssertEqual(model.trackShareURL?.query, "track=" + fixture.free.trackId)
        // The preceding M3 recommendation test deliberately cleared featured configuration.
        let expected = try await bridge.fixture("featured", as: LinkFeatured.self)
        let slug = "featured-2-" + expected.collectionIds[0]
        await model.openMusicLink(URL(string: "https://public.native.local.test/music/?collection=" + slug)!)
        XCTAssertEqual(model.activeCollection?.slug, slug); XCTAssertFalse(model.linkUnavailable)
        XCTAssertEqual(model.activeCollection?.tracks.count, 1); XCTAssertFalse(model.playback.hasAudioSource)
        XCTAssertEqual(model.collectionShareURL?.query, "collection=" + slug)
        model.playback.shutdown()
        print("M4_LINKS_PASSED: configured-origin track/album resolution; no authorization or autoplay")
    }
    private func verifyPreviewRepeat(player: PlaybackService, native: NativeMusicAPI, track: Track) async throws {
        let probe = PreviewRepeatProbe(base: native)
        defer { Task { await probe.release() } }
        player.configure(authorizer: probe)
        player.select(track); player.setRepeat(.one); player.requestPlay(variant: "preview")
        try await wait { player.isPlaying && player.duration < 2 }
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !(await probe.holding), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        let holding = await probe.holding, requests = await probe.requested
        XCTAssertTrue(holding); XCTAssertEqual(requests, ["preview", "preview"])
        XCTAssertEqual(player.state, .authorizing); XCTAssertFalse(player.hasAudioSource)
        // Catalog metadata while waiting is not an issued grant; keep it only as diagnostic evidence.
        let pendingDuration = player.duration
        await probe.release()
        try await wait { player.isPlaying && player.duration < 2 }
        let grants = await probe.granted, allRequests = await probe.requested
        XCTAssertGreaterThanOrEqual(grants.count, 2)
        XCTAssertTrue(grants.allSatisfy { $0 == "preview" }); XCTAssertTrue(allRequests.allSatisfy { $0 == "preview" })
        XCTAssertLessThan(player.duration, 2, "The actually playing repeated item must remain a preview")
        player.pause()
        print("M4_PREVIEW_REPEAT_GUARDED: pendingDuration=\(pendingDuration); held repeat has no audio source; requested/granted preview; resumed preview duration verified")
    }
    func testExplicitPreviewRepeatAcrossHeldAuthorization() async throws {
        let bridge = try bridge(), raw = try await bridge.fixture("rotation", as: RotationRaw.self)
        let fixture = try NativeJSON.decoder().decode(RotationFixture.self, from: JSONEncoder().encode(raw))
        let config = try NativeAuthConfiguration(environment: .development, origin: URL(string: "https://native.local.test")!, explicitlyEnabled: true)
        let journal = AuthJournal(store: MemorySecureStore(), environment: .development)
        try await journal.install(fixture.credential)
        let auth = NativeAuthenticationService(configuration: config, api: NativeAuthAPI(configuration: config, transport: bridge), journal: journal, browser: NoBrowser())
        try await auth.restore()
        let native = try NativeMusicAPI(configuration: config, explicitlyEnabled: true, transport: bridge, auth: auth)
        let track = Track(id: fixture.trackId, title: "Repeat timing fixture", artist: "Fixture", durationSeconds: fixture.durationSeconds, audioVersion: 1, access: .preview)
        let player = PlaybackService(transport: bridge); defer { player.shutdown() }
        try await verifyPreviewRepeat(player: player, native: native, track: track)
        try await auth.signOut()
    }
    func testZRealAuthenticationRotationOverFiveMinutes() async throws {
        let bridge = try bridge(), raw = try await bridge.fixture("rotation", as: RotationRaw.self)
        // Decode dates with the production ISO8601 decoder, while fixture transport stays test-only.
        let fixture = try NativeJSON.decoder().decode(RotationFixture.self, from: JSONEncoder().encode(raw))
        let configuration = try NativeAuthConfiguration(environment: .development, origin: URL(string: "https://native.local.test")!, explicitlyEnabled: true)
        let store = KeychainStore(service: "org.stationcat.m4.rotation." + UUID().uuidString)
        let journal = AuthJournal(store: store, environment: .development)
        try await journal.install(fixture.credential)
        let auth = NativeAuthenticationService(configuration: configuration, api: NativeAuthAPI(configuration: configuration, transport: bridge), journal: journal, browser: NoBrowser())
        try await auth.restore()
        let first = try await auth.requestContext(), before = try await journal.read()!
        let native = try NativeMusicAPI(configuration: configuration, explicitlyEnabled: true, transport: bridge, auth: auth)
        let track = Track(id: fixture.trackId, title: "Real token rotation", artist: "Local fixture", durationSeconds: fixture.durationSeconds, audioVersion: 1, access: .preview)
        let player = PlaybackService(transport: bridge); defer { player.shutdown() }
        try await verifyPreviewRepeat(player: player, native: native, track: track)
        player.configure(authorizer: native)
        player.setQueue([track], startingAt: 0, play: false); player.setRepeat(.one); player.requestPlay()
        try await wait { player.isPlaying && player.position > 0.1 }
        XCTAssertEqual(player.duration, fixture.durationSeconds, accuracy: 0.001) // VIP full despite public catalog advertising preview.
        let started = ContinuousClock.now
        while started.duration(to: .now) < .seconds(315) {
            try await Task.sleep(for: .seconds(1))
            XCTAssertTrue([.playing, .authorizing].contains(player.state))
            if player.state == .verificationRequired { break }
        }
        XCTAssertGreaterThanOrEqual(started.duration(to: .now), .seconds(315))
        let current = try await auth.requestContext(), after = try await journal.read()!
        XCTAssertEqual(current.sessionID, first.sessionID); XCTAssertEqual(current.scope, first.scope)
        XCTAssertEqual(after.familyID, before.familyID); XCTAssertEqual(after.absoluteExpiresAt, before.absoluteExpiresAt)
        XCTAssertGreaterThan(after.generation, before.generation); XCTAssertNil(after.pending); XCTAssertNotEqual(current.bearer, first.bearer)
        XCTAssertTrue(player.isPlaying); XCTAssertGreaterThan(player.position, 100)
        let authorization = try await native.authorize(track: track, variant: "full")
        var request = URLRequest(url: authorization.grant.playbackUrl); request.httpMethod = "HEAD"
        request.setValue("Bearer " + first.bearer, forHTTPHeaderField: "Authorization")
        let old: HTTPResult = try await bridge.send(request); XCTAssertEqual(old.status, 401)
        request.setValue("Bearer " + current.bearer, forHTTPHeaderField: "Authorization")
        let new: HTTPResult = try await bridge.send(request); XCTAssertEqual(new.status, 200)
        let evidence = try await bridge.fixture("rotation-evidence", as: RotationEvidence.self)
        XCTAssertEqual(evidence.generation, after.generation); XCTAssertEqual(evidence.revoked, 0)
        XCTAssertEqual(evidence.operations, Array(0..<after.generation)); XCTAssertEqual(evidence.absoluteUntil / 1000, before.absoluteExpiresAt.timeIntervalSince1970, accuracy: 0.001)
        player.clear(); try await auth.signOut(); let empty = try await journal.read(); XCTAssertNil(empty)
        print("M4_AUTH_ROTATION_PASSED: >315s real clock; NativeAuthenticationService + Keychain journal; same family/session; generation=\(after.generation); old Bearer 401; new Bearer 200")
    }
}
// Fixture control decoding preserves date strings until the production decoder is applied.
private struct RotationRaw: Codable {
    struct Credential: Codable {
        let schemaVersion: Int; let scope: AccountScope; let sessionID: String; let familyID: String; let generation: Int
        let refreshToken: String; let refreshExpiresAt: String; let absoluteExpiresAt: String
    }
    let credential: Credential; let trackId: String; let durationSeconds: Double
}

private struct LinkFeatured: Decodable { let collectionIds: [String] }
