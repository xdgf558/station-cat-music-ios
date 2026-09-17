import XCTest
@testable import StationCatMusic

private actor RangeTransport: MediaHTTPTransport {
    var requests: [URLRequest] = []
    let statuses: [Int]; let wrongRange: Bool; let changedETag: Bool
    init(_ statuses: [Int] = [], wrongRange: Bool = false, changedETag: Bool = false) { self.statuses = statuses; self.wrongRange = wrongRange; self.changedETag = changedETag }
    func send(_ request: URLRequest) async throws -> MediaHTTPResult {
        requests.append(request)
        let status = statuses.indices.contains(requests.count - 1) ? statuses[requests.count - 1] : request.httpMethod == "HEAD" ? 200 : 206
        let range = request.value(forHTTPHeaderField: "Range")?.replacingOccurrences(of: "bytes=", with: "").split(separator: "-").compactMap { Int($0) }
        let start = range?.first ?? 0, end = range?.last ?? 1023
        let data = request.httpMethod == "HEAD" || status != 206 ? Data() : Data(repeating: 7, count: end - start + 1)
        return MediaHTTPResult(status: status, data: data, headers: ["content-type": "audio/mpeg", "etag": changedETag && requests.count > 1 ? "changed" : "fixture",
            "content-length": request.httpMethod == "HEAD" ? "1024" : String(data.count), "content-range": "bytes \(wrongRange ? start + 1 : start)-\(end)/1024"])
    }
}
private actor GrantStub: PlaybackAuthorizing {
    var current = true; var refreshes = 0; let response: AuthorizedPlayback; let delay: Duration
    init(_ response: AuthorizedPlayback, delay: Duration = .zero) { self.response = response; self.delay = delay }
    func authorize(track: Track, variant: String) async throws -> AuthorizedPlayback { try await Task.sleep(for: delay); return response }
    func isCurrent(_ authorization: AuthorizedPlayback) -> Bool { current }
    func bearer(for authorization: AuthorizedPlayback, refresh: Bool) throws -> String? { if !current { throw APIError.staleResponse }; if refresh { refreshes += 1 }; return refresh ? "new-access" : "old-access" }
    func revoke() { current = false }
}
@MainActor final class NativeMusicTests: XCTestCase {
    private func authorization(_ mode: GrantAuthMode = .sessionBearer) -> AuthorizedPlayback {
        let now = Date(), scope = AccountScope(environment: .development, accountID: mode == .sessionBearer ? "1" : nil)
        let g = PlaybackGrant(playbackUrl: URL(string: "https://native.example.test/api/mobile/v1/music/media/" + String(repeating: "a", count: 43) + "/audio")!,
            expiresAt: now.addingTimeInterval(100), playbackValidUntil: now.addingTimeInterval(100), revalidateAt: now.addingTimeInterval(60), durationSeconds: 120,
            previewSourceStartSeconds: nil, authMode: mode, accountID: scope.accountID, sessionID: mode == .sessionBearer ? "session" : nil, trackID: "fixture", audioVersion: 1, variant: "full")
        let context = mode == .sessionBearer ? NativeAuthContext(epoch: 0, scope: scope, bearer: "old-access", sessionID: "session") : nil
        return AuthorizedPlayback(grant: g, serverNow: now, context: context, scope: scope)
    }
    private func track() -> Track { Track(id: "fixture", title: "Fixture", artist: "Fixture", durationSeconds: 120, audioVersion: 1, access: .free) }
    func testRangeCarriesIndependentBearerAndRejectsWrongRange() async throws {
        let a = authorization(), source = GrantStub(a), transport = RangeTransport(), channel = AuthorizedMediaChannel(authorization: a, authorizer: source, transport: transport, lifetime: 90)
        let size = try await channel.size(); XCTAssertEqual(size, 1024)
        let data = try await channel.read(start: 12, length: 32, total: size); XCTAssertEqual(data.count, 32)
        let requests = await transport.requests; XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer old-access" && $0.url?.query == nil && $0.value(forHTTPHeaderField: "Cookie") == nil })
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Range"), "bytes=12-43")
        let bad = AuthorizedMediaChannel(authorization: a, authorizer: source, transport: RangeTransport(wrongRange: true), lifetime: 90)
        do { _ = try await bad.read(start: 0, length: 2, total: 1024); XCTFail() } catch {}
    }
    func test401RefreshesExactlyOnceAnd403NeverRefreshes() async throws {
        for statuses in [[401, 206], [401, 401], [403]] {
            let a = authorization(), source = GrantStub(a), transport = RangeTransport(statuses), channel = AuthorizedMediaChannel(authorization: a, authorizer: source, transport: transport, lifetime: 90)
            do { _ = try await channel.read(start: 0, length: 2, total: 1024); XCTAssertEqual(statuses, [401, 206]) } catch { XCTAssertNotEqual(statuses, [401, 206]) }
            let count = await source.refreshes, requests = await transport.requests
            XCTAssertEqual(count, statuses[0] == 401 ? 1 : 0); XCTAssertEqual(requests.count, statuses.count)
            if requests.count == 2 { XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer new-access") }
        }
    }
    func testPublicRequestsCarryNoBearerOrCookie() async throws {
        let a = authorization(.publicAccess), source = GrantStub(a), transport = RangeTransport(), channel = AuthorizedMediaChannel(authorization: a, authorizer: source, transport: transport, lifetime: 90)
        _ = try await channel.size(); let requests = await transport.requests
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization")); XCTAssertNil(requests[0].value(forHTTPHeaderField: "Cookie"))
    }
    func testExpiredOrRevokedChannelNeverSendsBytes() async throws {
        for expired in [true, false] {
            let a = authorization(), source = GrantStub(a), transport = RangeTransport(), channel = AuthorizedMediaChannel(authorization: a, authorizer: source, transport: transport, lifetime: expired ? 0 : 90)
            if !expired { await source.revoke() }
            do { _ = try await channel.size(); XCTFail() } catch {}
            let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
        }
    }
    func testChangedObjectIdentityAnd416AndRedirectStop() async throws {
        let a = authorization(), source = GrantStub(a), channel = AuthorizedMediaChannel(authorization: a, authorizer: source, transport: RangeTransport(changedETag: true), lifetime: 90)
        _ = try await channel.size()
        do { _ = try await channel.read(start: 0, length: 2, total: 1024); XCTFail() } catch {}
        for status in [302, 416, 503] {
            let transport = RangeTransport([status]), channel = AuthorizedMediaChannel(authorization: a, authorizer: source, transport: transport, lifetime: 90)
            do { _ = try await channel.read(start: 0, length: 2, total: 1024); XCTFail() } catch {}
            let requests = await transport.requests; XCTAssertEqual(requests.count, 1)
        }
    }
    func testPauseLogoutAndTrackChangeRejectLateAuthorization() async throws {
        for action in 0...2 {
            let response = authorization(.publicAccess), source = GrantStub(response, delay: .milliseconds(30)), player = PlaybackService()
            player.configure(authorizer: source); player.select(track()); player.requestPlay()
            if action == 0 { player.pause() } else if action == 1 { player.deny() } else { player.select(track()) }
            try await Task.sleep(for: .milliseconds(80)); XCTAssertFalse(player.hasAudioSource); XCTAssertFalse(player.isPlaying)
        }
    }
    func testDisabledMusicCannotUseTransport() throws {
        let config = try NativeAuthConfiguration(environment: .development, origin: URL(string: "https://native.example.test")!, explicitlyEnabled: true)
        XCTAssertThrowsError(try NativeMusicAPI(configuration: config, explicitlyEnabled: false, transport: MockTransport(data: Data())))
        XCTAssertThrowsError(try NativeAuthConfiguration(environment: .production, origin: config.origin, explicitlyEnabled: true))
    }
    func testMediaDeadlineDoesNotWaitForUncooperativeRefreshOrTransport() async throws {
        let a = authorization(), source = GrantStub(a)
        let channel = AuthorizedMediaChannel(authorization: a, authorizer: source, transport: SlowMediaTransport(), lifetime: 90)
        let clock = ContinuousClock(), start = ContinuousClock.now
        do { _ = try await channel.size(); XCTFail() } catch {}
        XCTAssertLessThan(start.duration(to: clock.now), .seconds(6))
    }
    func testLyricsPreviewOffsetAndGaps() {
        let lyrics = MusicLyrics(kind: "timed", text: "", lines: [.init(startSeconds: 12, text: "one"), .init(startSeconds: 16, text: "two")], audioVersion: 1)
        XCTAssertNil(lyrics.current(at: 10)); XCTAssertEqual(lyrics.current(at: 1 + 12), 0); XCTAssertEqual(lyrics.current(at: 4 + 12), 1)
    }
}

private actor SlowMediaTransport: MediaHTTPTransport {
    func send(_ request: URLRequest) async throws -> MediaHTTPResult {
        // Deliberately ignores parent cancellation like a separately coalesced refresh.
        await Task.detached { try? await Task.sleep(for: .seconds(7)) }.value
        return MediaHTTPResult(status: 503, data: Data(), headers: [:])
    }
}
