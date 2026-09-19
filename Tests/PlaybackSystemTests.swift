import XCTest
import AVFoundation
import MediaPlayer
@testable import StationCatMusic

@MainActor private final class SystemSpy: PlaybackSystem {
    var activations = 0; var deactivations = 0; var snapshot: PlaybackSnapshot?; var closed = false
    func activate() throws { activations += 1 }
    func deactivate() { deactivations += 1 }
    func publish(_ snapshot: PlaybackSnapshot?) { self.snapshot = snapshot }
    func shutdown() { closed = true }
}
@MainActor private final class SystemClock: PlaybackClock { var now = 0.0 }
private actor RejectingQueueAuthorizer: PlaybackAuthorizing {
    private(set) var requests: [String] = []
    let error: APIError
    init(_ error: APIError = .rejected(403)) { self.error = error }
    func authorize(track: Track, variant: String) async throws -> AuthorizedPlayback { requests.append(track.id); throw error }
    func isCurrent(_ value: AuthorizedPlayback) -> Bool { true }
    func bearer(for value: AuthorizedPlayback, refresh: Bool) -> String? { nil }
}
private actor HeldContextAuthorizer: PlaybackAuthorizing {
    var entered = false
    var continuation: CheckedContinuation<Bool, Never>?
    func authorize(track: Track, variant: String) -> AuthorizedPlayback {
        let now = Date(), end = now.addingTimeInterval(60)
        let grant = PlaybackGrant(playbackUrl: URL(string: "https://native.local.test/api/mobile/v1/music/media/fffffffffffffffffffffffffffffffffffffffffff/audio")!, expiresAt: end, playbackValidUntil: end, revalidateAt: end, durationSeconds: track.durationSeconds, previewSourceStartSeconds: nil, authMode: .publicAccess, accountID: nil, sessionID: nil, trackID: track.id, audioVersion: 1, variant: "full")
        return AuthorizedPlayback(grant: grant, serverNow: now, context: nil, scope: .guest)
    }
    func isCurrent(_ value: AuthorizedPlayback) async -> Bool { entered = true; return await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(returning: true); continuation = nil }
    func bearer(for value: AuthorizedPlayback, refresh: Bool) -> String? { nil }
}
@MainActor final class PlaybackSystemTests: XCTestCase {
    private func track(_ id: String, access: AccessPolicy = .free) -> Track { Track(id: id, title: id, artist: "Fixture", durationSeconds: 180, audioVersion: 1, access: access) }
    func testFavoriteEntryUsesOnlyFavoritesDespiteCatalogFilters() {
        let model = AppModel(client: APIClient(environment: .mock, transport: MockTransport(data: Data())))
        let a = track("a"), b = track("b"), c = track("c")
        model.tracks = [a, b, c]; model.favorites = ["b"]
        for filtered in [false, true] {
            if filtered {
                model.activeCollection = MusicCollection(id: "unrelated", slug: "unrelated", title: "Other", description: "", version: 1, tracks: [a, c], nextCursor: nil)
                model.query = "c"
            }
            let visible = model.favoriteTracks
            XCTAssertEqual(visible, [b]); model.select(b, from: visible)
            XCTAssertEqual(model.playback.queue.entries.map(\.track), [b])
        }
        model.favorites = ["b", "c"]
        let visible = model.favoriteTracks; model.select(b, from: visible)
        model.favorites = []; model.tracks = []
        XCTAssertEqual(model.playback.queue.entries.map(\.track), [b, c], "Queue keeps the displayed favorites snapshot")
        model.select(b)
        XCTAssertEqual(model.playback.queue.entries.map(\.track), [b], "Unspecified list must not inherit unrelated catalog state")
    }
    func testPauseDuringContextCheckCannotActivateAudioSession() async throws {
        let source = HeldContextAuthorizer(), player = PlaybackService(), system = SystemSpy()
        player.attachSystem(system); player.configure(authorizer: source); player.select(track("a")); player.requestPlay()
        for _ in 0..<100 { if await source.entered { break }; try await Task.sleep(for: .milliseconds(10)) }
        let entered = await source.entered; XCTAssertTrue(entered)
        player.pause(); await source.release(); try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(system.activations, 0); XCTAssertEqual(player.state, .paused); XCTAssertFalse(player.hasAudioSource)
    }
    func testExplicitPlayRecoversMissingInterruptionEndNotification() async throws {
        let source = RejectingQueueAuthorizer(.rejected(503)), player = PlaybackService(); player.configure(authorizer: source)
        player.select(track("a")); player.interruptionBegan(); player.handle(.play)
        for _ in 0..<100 { if player.state == .verificationRequired { break }; try await Task.sleep(for: .milliseconds(10)) }
        let calls = await source.requests; XCTAssertEqual(calls, ["a"])
    }
    func testMusicLinkOnlyAcceptsConfiguredHTTPSIdentifiers() {
        XCTAssertNil(MusicLink.webOrigin(URL(string: "https://music.example/path")))
        XCTAssertNil(MusicLink.webOrigin(URL(string: "https://music.example?token=x")))
        XCTAssertNil(MusicLink.webOrigin(nil))
        XCTAssertNotNil(MusicLink.webOrigin(URL(string: "https://music.example")))
        let id = UUID().uuidString, root = "https://native.local.test/music/"
        XCTAssertEqual(MusicLink(URL(string: root + "?track=" + id)!, allowedHost: "native.local.test"), .track(id))
        XCTAssertEqual(MusicLink(URL(string: root + "?collection=example-album")!, allowedHost: "native.local.test"), .collection("example-album"))
        for value in [root + "?track=bad", root + "?track=" + id + "&token=secret", root + "?collection=../other", root + "?collection=a#token", root.replacingOccurrences(of: "https:", with: "http:") + "?track=" + id, "https://other.test/music/?track=" + id] {
            XCTAssertNil(MusicLink(URL(string: value)!, allowedHost: "native.local.test"))
        }
    }
    func testQueueDuplicatesRepeatAndBoundedHistory() {
        var queue = PlaybackQueue(); let a = track("a"), b = track("b")
        queue.replace([a, b, a], startingAt: 0)
        XCTAssertEqual(Set(queue.entries.map(\.id)).count, 3)
        XCTAssertEqual(queue.advance(), b); XCTAssertEqual(queue.advance(), a); XCTAssertNil(queue.advance())
        XCTAssertEqual(queue.previous(), b)
        queue.repeatMode = .one; XCTAssertEqual(queue.advance(natural: true), b)
        queue.repeatMode = .all; _ = queue.advance(); XCTAssertEqual(queue.advance(), a)
        for _ in 0..<700 { _ = queue.advance() }; XCTAssertLessThanOrEqual(queue.history.count, 500)
    }
    func testShuffleRetainsSelectionAndPreviousUsesActualHistory() {
        var queue = PlaybackQueue(); queue.replace([track("a"), track("b"), track("c"), track("d")], startingAt: 1)
        let current = queue.currentID; queue.setShuffle(true)
        XCTAssertEqual(queue.currentID, current); XCTAssertEqual(Set(queue.order), Set(queue.entries.map(\.id)))
        let next = queue.advance(); XCTAssertNotNil(next); XCTAssertEqual(queue.previous()?.id, "b")
        queue.setShuffle(false); XCTAssertEqual(queue.currentID, current); XCTAssertEqual(queue.order, queue.entries.map(\.id))
        XCTAssertFalse(queue.remove(current!)); XCTAssertEqual(queue.entries.count, 4)
    }
    func testEmptyAndOversizedQueuesAreRejected() {
        var queue = PlaybackQueue(); queue.replace([], startingAt: 0); XCTAssertNil(queue.current)
        queue.replace(Array(repeating: track("a"), count: 501), startingAt: 0); XCTAssertTrue(queue.entries.isEmpty)
        queue.replace([track("a")], startingAt: -1); XCTAssertNil(queue.current)
    }
    func testAllUnavailableNeverLoopsEvenWithRepeatAll() async throws {
        let source = RejectingQueueAuthorizer(), player = PlaybackService(); player.configure(authorizer: source)
        player.setQueue([track("a"), track("b"), track("c")], startingAt: 0, play: false); player.setRepeat(.all); player.requestPlay()
        for _ in 0..<100 { if player.state == .verificationRequired { break }; try await Task.sleep(for: .milliseconds(10)) }
        let calls = await source.requests; XCTAssertEqual(calls, ["a", "b", "c"])
        XCTAssertEqual(player.noticeKey, "queueUnavailable"); XCTAssertFalse(player.hasAudioSource)
        try await Task.sleep(for: .milliseconds(100)); let after = await source.requests; XCTAssertEqual(after, calls)
    }
    func test503StopsInsteadOfTryingRestOfQueue() async throws {
        let source = RejectingQueueAuthorizer(.rejected(503)), player = PlaybackService(); player.configure(authorizer: source)
        player.setQueue([track("a"), track("b")], startingAt: 0)
        for _ in 0..<100 { if player.state == .verificationRequired { break }; try await Task.sleep(for: .milliseconds(10)) }
        let calls = await source.requests; XCTAssertEqual(calls, ["a"]); XCTAssertFalse(player.hasAudioSource)
    }
    func testQueueIndependentOfCatalogArrayAndClearRemovesSystemState() {
        let player = PlaybackService(), system = SystemSpy(); player.attachSystem(system)
        var catalog = [track("a"), track("b")]; player.setQueue(catalog, startingAt: 0, play: false); catalog.removeAll()
        XCTAssertEqual(player.queue.entries.count, 2); XCTAssertEqual(system.snapshot?.track.id, "a")
        player.setSleepTimer(seconds: 60); player.clear()
        XCTAssertNil(system.snapshot); XCTAssertNil(player.selectedTrack); XCTAssertNil(player.sleepDeadline); XCTAssertTrue(player.queue.entries.isEmpty)
        player.shutdown(); XCTAssertTrue(system.closed)
    }
    func testPausedSeekRetainsPositionWithoutLoadingAudio() {
        let player = PlaybackService(), system = SystemSpy(); player.attachSystem(system); player.select(track("a")); player.pause()
        player.handle(.seek(65)); XCTAssertEqual(player.position, 65); XCTAssertFalse(player.hasAudioSource)
        XCTAssertEqual(system.snapshot?.position, 65); XCTAssertEqual(system.snapshot?.playing, false)
        player.handle(.seek(.infinity)); XCTAssertEqual(player.position, 65)
    }
    func testSleepDeadlineUsesContinuousClockAndStopsWithoutAutoResume() {
        let clock = SystemClock(), player = PlaybackService(clock: clock); player.select(track("a"))
        player.setSleepTimer(seconds: 10); clock.now = 11; player.becameActive()
        XCTAssertEqual(player.noticeKey, "sleepFinished"); XCTAssertEqual(player.state, .paused); XCTAssertNil(player.sleepDeadline)
        player.interruptionEnded(shouldResume: true); XCTAssertEqual(player.state, .paused)
    }
    func testRouteDisconnectAndResetRequireExplicitPlay() {
        let player = PlaybackService(); player.select(track("a")); player.routeDisconnected()
        XCTAssertEqual(player.state, .paused); XCTAssertEqual(player.noticeKey, "headphonesDisconnected")
        player.mediaServicesReset(); XCTAssertEqual(player.state, .paused); XCTAssertFalse(player.hasAudioSource)
        XCTAssertEqual(player.selectedTrack?.id, "a"); player.becameActive(); XCTAssertFalse(player.isPlaying)
    }
    func testRealSystemAdapterPublishesNoPrivateURLAndCleansUp() {
        let player = PlaybackService(); let adapter = SystemPlayback(playback: player, artworkHost: "native.local.test")
        player.attachSystem(adapter); player.select(track("public-title"))
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        XCTAssertEqual(info?[MPMediaItemPropertyTitle] as? String, "public-title")
        XCTAssertEqual(info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0)
        XCTAssertFalse(String(describing: info).contains("Bearer")); XCTAssertFalse(String(describing: info).contains("/media/"))
        player.shutdown(); XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        XCTAssertFalse(MPRemoteCommandCenter.shared().playCommand.isEnabled)
    }
}
