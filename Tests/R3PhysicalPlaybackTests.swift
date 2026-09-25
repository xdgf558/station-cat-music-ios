import XCTest
import MediaPlayer
@testable import StationCatMusic

/// Explicit opt-in, real device, isolated public music only. Synthetic by default;
/// R3_ENABLE_REAL_TRACKS=YES selects the copied, published free album. No login,
/// Keychain mutation, personal library upload or production requests.
@MainActor final class R3PhysicalPlaybackTests: XCTestCase {
    func testIsolatedHTTPSOfflineAndArtworkAcceptance() async throws {
        guard ProcessInfo.processInfo.environment["R3_ENABLE_OFFLINE_ACCEPTANCE"] == "YES" else { throw XCTSkip("Explicit isolated offline acceptance only") }
        let origin = URL(string: "https://station-cat-music-r2.yehao1105.workers.dev")!
        guard Bundle.main.bundleIdentifier == "org.stationcat.music.staging",
              Bundle.main.object(forInfoDictionaryKey: "StationNativeAuthOrigin") as? String == origin.absoluteString else { XCTFail("Isolated Staging only"); return }
        let config = try NativeAuthConfiguration(environment: .staging, origin: origin, explicitlyEnabled: true)
        let native = try NativeMusicAPI(configuration: config, explicitlyEnabled: true, transport: URLSessionTransport())
        let catalog = try await native.catalog()
        let track = try XCTUnwrap(catalog.items.first { $0.id == "cae8ef9b-a808-4669-b907-c07cdbeec1c0" && $0.offlineEligible == true })
        let cover = try XCTUnwrap(track.coverUrl)
        let temporary = FileManager.default.temporaryDirectory.appending(path: "R3-Artwork-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let images = ArtworkLoader(cacheDirectory: temporary)
        var sent = ContinuousClock.now
        let coldImage = try await images.load(cover, allowedHost: origin.host!)
        XCTAssertNotNil(coldImage); let cold = elapsed(sent)
        sent = .now
        let warmImage = try await images.load(cover, allowedHost: origin.host!)
        let warm = elapsed(sent); XCTAssertTrue(coldImage === warmImage)
        sent = .now
        let reopenedImage = try await ArtworkLoader(cacheDirectory: temporary).load(cover, allowedHost: origin.host!)
        let disk = elapsed(sent); XCTAssertNotNil(reopenedImage)
        print("R3_ARTWORK_CACHE: cold=\(cold); memory=\(warm); reopened_disk=\(disk)")
        // A real, permanently free track is deliberately retained for the user's
        // subsequent offline check. No existing library or cache is cleared.
        let cache = OfflineMusicCache(origin: origin)
        if try await cache.playable(track) == nil { try await cache.download(track, source: native) }
        let reopened = OfflineMusicCache(origin: origin)
        let playable = try await reopened.playable(track); XCTAssertNotNil(playable)
        let denied = R3OfflineNetworkDenied()
        let player = PlaybackService(transport: denied); player.configure(authorizer: denied); player.offlineCache = reopened
        player.attachSystem(SystemPlayback(playback: player, artworkHost: origin.host!))
        defer { player.shutdown() }
        player.select(track); sent = .now; player.requestPlay()
        try await wait { player.isPlaying && player.position > 1 }
        let startup = elapsed(sent)
        XCTAssertTrue(player.isOfflinePlayback)
        player.seek(to: 41); try await wait { player.position > 44 }
        player.deny(); let stopped = player.position
        player.requestPlay(); try await wait { player.position > stopped + 1 }
        player.pause(); let paused = player.position
        player.requestPlay(); try await wait { player.position > paused + 1 }
        let networkCalls = await denied.calls; XCTAssertEqual(networkCalls, 0)
        print("R3_FREE_OFFLINE: actual_MP3_verified=true; fresh_cache_instance=true; blocked_network_calls=\(networkCalls); startup=\(startup); resumed_from=\(stopped); final=\(player.position)")
    }
    func testPhysicalHTTPSPlaybackPauseSeekAndRenewal() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("R3 requires a physical device")
        #else
        guard ProcessInfo.processInfo.environment["R3_ENABLE_PHYSICAL_PLAYBACK"] == "YES" else {
            throw XCTSkip("Explicit physical playback acceptance only")
        }
        let origin = URL(string: "https://station-cat-music-r2.yehao1105.workers.dev")!
        guard Bundle.main.bundleIdentifier == "org.stationcat.music.staging",
              Bundle.main.object(forInfoDictionaryKey: "StationEnvironment") as? String == "staging",
              Bundle.main.object(forInfoDictionaryKey: "StationNativeAuthOrigin") as? String == origin.absoluteString else {
            XCTFail("Expected explicitly configured isolated Staging host"); return
        }
        var stage = "catalog"
        do {
            let config = try NativeAuthConfiguration(environment: .staging, origin: origin, explicitlyEnabled: true)
            let native = try NativeMusicAPI(configuration: config, explicitlyEnabled: true, transport: URLSessionTransport())
            let realTracks = ProcessInfo.processInfo.environment["R3_ENABLE_REAL_TRACKS"] == "YES"
            let selectedID = realTracks ? "cae8ef9b-a808-4669-b907-c07cdbeec1c0" : "a3d01b06-8c4c-4a8a-9d66-25429d2ad843"
            let catalog = try await native.catalog()
            let track = try XCTUnwrap(catalog.items.first { $0.id == selectedID && $0.access == .free })
            let featured = try await native.featured()
            XCTAssertTrue(featured.tracks.contains { $0.id == track.id })
            if realTracks {
                stage = "real_album_detail"
                let album = try XCTUnwrap(featured.collections.first { $0.slug == "wydgb" })
                XCTAssertEqual(album.tracks.count, 7)
                XCTAssertTrue(album.tracks.allSatisfy { $0.access == .free })
                let detail = try await native.detail(track, locale: "zh-Hans")
                XCTAssertEqual(detail.track.title, "把那年还给风")
                XCTAssertEqual(detail.lyrics.kind, "timed")
                XCTAssertEqual(detail.lyrics.audioVersion, track.audioVersion)
                XCTAssertFalse(detail.lyrics.lines.isEmpty)
            }
            let authorizer = R3CountingAuthorizer(base: native)
            let media = R3TimingMediaTransport()
            let playback = PlaybackService(transport: media)
            playback.configure(authorizer: authorizer)
            playback.attachSystem(SystemPlayback(playback: playback, artworkHost: origin.host!))
            defer { playback.shutdown() }
            playback.select(track)
            XCTAssertFalse(playback.hasAudioSource)
            stage = "start"
            let pressedAt = ContinuousClock.now
            playback.requestPlay()
            do { try await wait { playback.isPlaying && playback.position > 1 } }
            catch {
                print("R3_START_DIAGNOSTIC: position=\(playback.position); state=\(playback.state); grants=\(await authorizer.successes); authorizationFailures=\(await authorizer.failures); \(await media.summary())")
                throw error
            }
            let startupSeconds = elapsed(pressedAt)
            print("R3_STARTUP: seconds_to_progress_over_one=\(startupSeconds)")
            XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String, track.title)
            if realTracks {
                stage = "real_now_playing_artwork"
                try await wait { MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] is MPMediaItemArtwork }
            }
            stage = "continuous_renewal"
            var lastPosition = playback.position, lastAdvance = ContinuousClock.now
            var longestGap = 0.0, largestRollback = 0.0
            do {
                try await wait(seconds: 85) {
                    longestGap = max(longestGap, self.elapsed(lastAdvance))
                    largestRollback = max(largestRollback, lastPosition - playback.position)
                    if playback.position > lastPosition + 0.01 { lastAdvance = .now }
                    lastPosition = playback.position
                    return playback.isPlaying && playback.position > 70
                }
            } catch {
                let count = await authorizer.successes
                let failures = await authorizer.failures
                print("R3_PROGRESS_DIAGNOSTIC: position=\(playback.position); state=\(playback.state); grants=\(count); authorizationFailures=\(failures)")
                print("R3_MEDIA_DIAGNOSTIC: \(await media.summary())")
                throw error
            }
            let grants = await authorizer.successes
            XCTAssertGreaterThanOrEqual(grants, 2, "Must cross a real grant renewal")
            print("R3_CONTINUITY: startup=\(startupSeconds); max_progress_gap=\(longestGap); max_rollback=\(largestRollback); \(await media.summary())")
            stage = "pause_seek_resume"
            playback.handle(.pause)
            XCTAssertFalse(playback.hasAudioSource)
            XCTAssertEqual(playback.state, .paused)
            playback.handle(.play)
            try await wait { playback.isPlaying && playback.position > 70 }
            playback.handle(.seek(100))
            try await wait { playback.isPlaying && playback.position > 101 }
            playback.clear()
            XCTAssertFalse(playback.hasAudioSource)
            XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
            print("R3_PHYSICAL_PASSED: real_tracks=\(realTracks); public_https; featured; 70s_progress; grants=\(grants); pause; seek; now_playing_cleanup")
        } catch {
            let category = error is R3ConditionTimeout ? "condition_timeout" : CatalogFailure(error).rawValue
            print("R3_PHYSICAL_FAILED: stage=\(stage); category=\(category)")
            // Do not stringify errors: network errors may carry authorization URLs.
            XCTFail("Physical acceptance failed at \(stage)")
        }
        #endif
    }
    private func wait(seconds: Double = 20, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(100)) }
        guard condition() else { throw R3ConditionTimeout() }
    }
    private func elapsed(_ since: ContinuousClock.Instant) -> Double {
        let value = since.duration(to: .now).components
        return Double(value.seconds) + Double(value.attoseconds) / 1e18
    }
}
private struct R3ConditionTimeout: Error {}
private actor R3TimingMediaTransport: MediaHTTPTransport {
    let base = NativeMediaTransport()
    private var count = 0, failures = 0
    private var firstRequests: [String] = []
    func send(_ request: URLRequest) async throws -> MediaHTTPResult {
        let start = ContinuousClock.now
        count += 1
        do {
            let value = try await base.send(request)
            if firstRequests.count < 8 {
                let duration = start.duration(to: .now).components
                let ms = Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
                firstRequests.append("\(request.httpMethod == "HEAD" ? "HEAD" : "GET") status=\(value.status) bytes=\(value.data.count) ms=\(Int(ms))")
            }
            return value
        } catch { failures += 1; throw error }
    }
    func summary() -> String { "requests=\(count); failures=\(failures); first=\(firstRequests)" }
}
private actor R3CountingAuthorizer: PlaybackAuthorizing {
    let base: NativeMusicAPI
    private(set) var successes = 0
    private(set) var failures: [String] = []
    init(base: NativeMusicAPI) { self.base = base }
    func preferredVariant(for track: Track) async throws -> String { try await base.preferredVariant(for: track) }
    func authorize(track: Track, variant: String) async throws -> AuthorizedPlayback {
        do {
            let value = try await base.authorize(track: track, variant: variant)
            successes += 1
            return value
        } catch {
            failures.append(CatalogFailure(error).rawValue)
            throw error
        }
    }
    func isCurrent(_ value: AuthorizedPlayback) async -> Bool { await base.isCurrent(value) }
    func bearer(for value: AuthorizedPlayback, refresh: Bool) async throws -> String? { try await base.bearer(for: value, refresh: refresh) }
}

private actor R3OfflineNetworkDenied: PlaybackAuthorizing, MediaHTTPTransport {
    var calls = 0
    func authorize(track: Track, variant: String) throws -> AuthorizedPlayback { calls += 1; throw URLError(.notConnectedToInternet) }
    func isCurrent(_ authorization: AuthorizedPlayback) -> Bool { false }
    func bearer(for authorization: AuthorizedPlayback, refresh: Bool) throws -> String? { calls += 1; throw URLError(.notConnectedToInternet) }
    func send(_ request: URLRequest) throws -> MediaHTTPResult { calls += 1; throw URLError(.notConnectedToInternet) }
}
