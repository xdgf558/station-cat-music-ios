import XCTest
@testable import StationCatMusic

private actor RangeTransport: MediaHTTPTransport {
    var requests: [URLRequest] = []
    let statuses: [Int]; let wrongRange: Bool; let changedETag: Bool; let total: Int
    init(_ statuses: [Int] = [], wrongRange: Bool = false, changedETag: Bool = false, total: Int = 1024) { self.statuses = statuses; self.wrongRange = wrongRange; self.changedETag = changedETag; self.total = total }
    func send(_ request: URLRequest) async throws -> MediaHTTPResult {
        requests.append(request)
        let status = statuses.indices.contains(requests.count - 1) ? statuses[requests.count - 1] : request.httpMethod == "HEAD" ? 200 : 206
        let range = request.value(forHTTPHeaderField: "Range")?.replacingOccurrences(of: "bytes=", with: "").split(separator: "-").compactMap { Int($0) }
        let start = range?.first ?? 0, end = min(range?.last ?? (total - 1), total - 1)
        let data = request.httpMethod == "HEAD" || status != 206 ? Data() : Data(repeating: 7, count: end - start + 1)
        return MediaHTTPResult(status: status, data: data, headers: ["content-type": "audio/mpeg", "etag": changedETag && requests.count > 1 ? "changed" : "fixture",
            "content-length": request.httpMethod == "HEAD" ? String(total) : String(data.count), "content-range": "bytes \(wrongRange ? start + 1 : start)-\(end)/\(total)"])
    }
}
private actor GrantStub: PlaybackAuthorizing {
    var current = true; var refreshes = 0; let response: AuthorizedPlayback; let delay: Duration; let bearerDelay: Duration
    init(_ response: AuthorizedPlayback, delay: Duration = .zero, bearerDelay: Duration = .zero) { self.response = response; self.delay = delay; self.bearerDelay = bearerDelay }
    func authorize(track: Track, variant: String) async throws -> AuthorizedPlayback { try await Task.sleep(for: delay); return response }
    func isCurrent(_ authorization: AuthorizedPlayback) -> Bool { current }
    func bearer(for authorization: AuthorizedPlayback, refresh: Bool) async throws -> String? {
        if !current { throw APIError.staleResponse }; if refresh { refreshes += 1 }
        await Task.detached { [bearerDelay] in try? await Task.sleep(for: bearerDelay) }.value
        return refresh ? "new-access" : "old-access"
    }
    func revoke() { current = false }
}
@MainActor final class NativeMusicTests: XCTestCase {
    func testMetadataReuseIsPerGrantAndStillRejectsRevocationAndExpiry() async throws {
        for revoked in [false, true] {
            let a = authorization(), source = GrantStub(a), transport = RangeTransport()
            let channel = AuthorizedMediaChannel(authorization: a, authorizer: source, transport: transport, lifetime: revoked ? 90 : 0.2)
            _ = try await channel.size(); _ = try await channel.size()
            let first = await transport.requests.count; XCTAssertEqual(first, 1)
            if revoked { await source.revoke() } else { try await Task.sleep(for: .milliseconds(250)) }
            do { _ = try await channel.size(); XCTFail("Cached metadata crossed the authorization boundary") } catch {}
            do { _ = try await channel.read(start: 0, length: 2, total: 1024); XCTFail() } catch {}
            let final = await transport.requests.count; XCTAssertEqual(final, 1)
        }
        let a = authorization(), source = GrantStub(a), transport = RangeTransport()
        for _ in 0..<2 {
            let channel = AuthorizedMediaChannel(authorization: a, authorizer: source, transport: transport, lifetime: 90)
            _ = try await channel.size()
        }
        let count = await transport.requests.count; XCTAssertEqual(count, 2)
    }
    func testLargerRangesRemainBoundedAndUseExactOffsets() async throws {
        let a = authorization(), source = GrantStub(a), transport = RangeTransport(total: 1_048_576)
        let channel = AuthorizedMediaChannel(authorization: a, authorizer: source, transport: transport, lifetime: 90)
        let size = try await channel.size()
        let data = try await channel.read(start: 17, length: 524_288, total: size)
        XCTAssertEqual(data.count, 524_288)
        do { _ = try await channel.read(start: 17, length: 524_289, total: size); XCTFail() } catch {}
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "Range"), "bytes=17-524304")
    }
    func testInitialProbeUsesOneBoundedRangeAndOnlyKeepsPrefixWithinGrant() async throws {
        let a = authorization(), source = GrantStub(a), transport = RangeTransport(total: 1_048_576)
        let channel = AuthorizedMediaChannel(authorization: a, authorizer: source, transport: transport, lifetime: 90)
        let size = try await channel.size()
        let probe = try await channel.read(start: 0, length: 2, total: size)
        let prefix = try await channel.read(start: 0, length: NativeMediaLimits.rangeBytes, total: size)
        XCTAssertEqual(probe.count, 2); XCTAssertEqual(prefix.count, NativeMediaLimits.rangeBytes)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Range"), "bytes=0-524287")
        await source.revoke()
        do { _ = try await channel.read(start: 0, length: 2, total: size); XCTFail("Buffered prefix crossed logout") } catch {}
    }
    func testRenewalValidatesIdentityThenChangesOnlyFutureRequests() async throws {
        let a = authorization(), source = GrantStub(a), old = RangeTransport(), fresh = RangeTransport()
        let loader = NativeMediaLoader(channel: AuthorizedMediaChannel(authorization: a, authorizer: source, transport: old, lifetime: 90), onFailure: {})
        _ = try await loader.read(start: 20, length: 4, total: 1024)
        try await loader.renew(with: AuthorizedMediaChannel(authorization: a, authorizer: source, transport: fresh, lifetime: 90))
        _ = try await loader.read(start: 24, length: 4, total: 1024)
        let oldRequests = await old.requests, newRequests = await fresh.requests
        XCTAssertEqual(oldRequests.count, 2) // Original data and identity validation.
        XCTAssertEqual(newRequests.map(\.httpMethod), ["HEAD", "GET"])
        XCTAssertEqual(newRequests.last?.value(forHTTPHeaderField: "Range"), "bytes=24-27")
        loader.cancelAll()
        do { try await loader.renew(with: AuthorizedMediaChannel(authorization: a, authorizer: source, transport: fresh, lifetime: 90)); XCTFail() } catch {}
        do { _ = try await loader.read(start: 28, length: 4, total: 1024); XCTFail() } catch {}
        let afterCancel = await fresh.requests.count; XCTAssertEqual(afterCancel, 2)
    }
    func testRenewalRejectsChangedAudioAndRevokedScope() async throws {
        for revoked in [false, true] {
            let a = authorization(), source = GrantStub(a), old = RangeTransport(), fresh = RangeTransport(changedETag: true)
            let loader = NativeMediaLoader(channel: AuthorizedMediaChannel(authorization: a, authorizer: source, transport: old, lifetime: 90), onFailure: {})
            let replacement = AuthorizedMediaChannel(authorization: a, authorizer: source, transport: fresh, lifetime: 90)
            // Seed the transport so its next response has a changed identity.
            _ = try await fresh.send(URLRequest(url: a.grant.playbackUrl))
            if revoked { await source.revoke() }
            do { try await loader.renew(with: replacement); XCTFail("Renewal accepted a changed object or stale account") } catch {}
            loader.cancelAll()
        }
    }
    func testInFlightOldRangeIsDiscardedAfterRenewal() async throws {
        for oldFails in [false, true] {
            let a = authorization(), source = GrantStub(a), old = SuspendedMediaTransport(holdMethod: "GET", fails: oldFails), fresh = RangeTransport()
            let loader = NativeMediaLoader(channel: AuthorizedMediaChannel(authorization: a, authorizer: source, transport: old, lifetime: 90), onFailure: {})
            let read = Task { try await loader.read(start: 32, length: 8, total: 1024) }
            while !(await old.waiting) { await Task.yield() }
            try await loader.renew(with: AuthorizedMediaChannel(authorization: a, authorizer: source, transport: fresh, lifetime: 90))
            await old.release()
            let bytes = try await read.value
            XCTAssertEqual(bytes, Data(repeating: 7, count: 8), "Old-grant data must be discarded")
            let requests = await fresh.requests
            XCTAssertEqual(requests.map(\.httpMethod), ["HEAD", "GET"])
            XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "Range"), "bytes=32-39")
            loader.cancelAll()
        }
    }
    func testCancellationWhileValidatingRenewalCannotRestoreLoader() async throws {
        let a = authorization(), source = GrantStub(a), old = RangeTransport(), fresh = SuspendedMediaTransport(holdMethod: "HEAD")
        let loader = NativeMediaLoader(channel: AuthorizedMediaChannel(authorization: a, authorizer: source, transport: old, lifetime: 90), onFailure: {})
        let renewal = Task { try await loader.renew(with: AuthorizedMediaChannel(authorization: a, authorizer: source, transport: fresh, lifetime: 90)) }
        while !(await fresh.waiting) { await Task.yield() }
        loader.cancelAll(); await fresh.release()
        do { try await renewal.value; XCTFail("Late metadata restored a cancelled loader") } catch {}
        do { _ = try await loader.read(start: 0, length: 2, total: 1024); XCTFail() } catch {}
    }
    func testNativeTransportRejectsOversizedBodyWithoutContentLength() async throws {
        let transport = NativeMediaTransport(protocolClasses: [BoundedAudioProtocol.self])
        let valid = try await transport.send(URLRequest(url: URL(string: "https://media.fixture/exact")!))
        XCTAssertEqual(valid.data.count, 524_288)
        do {
            _ = try await transport.send(URLRequest(url: URL(string: "https://media.fixture/oversized")!))
            XCTFail("Unknown-length body exceeded the bounded range")
        } catch {}
    }
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
        let a = authorization(), source = GrantStub(a), transport = RangeTransport(total: 1_048_576), channel = AuthorizedMediaChannel(authorization: a, authorizer: source, transport: transport, lifetime: 90)
        let size = try await channel.size(); XCTAssertEqual(size, 1_048_576)
        let data = try await channel.read(start: 524_288, length: 32, total: size); XCTAssertEqual(data.count, 32)
        let requests = await transport.requests; XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer old-access" && $0.url?.query == nil && $0.value(forHTTPHeaderField: "Cookie") == nil })
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Range"), "bytes=524288-524319")
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
        let a = authorization(), source = GrantStub(a), channel = AuthorizedMediaChannel(authorization: a, authorizer: source, transport: RangeTransport(changedETag: true, total: 1_048_576), lifetime: 90)
        _ = try await channel.size()
        do { _ = try await channel.read(start: 524_288, length: 2, total: 1_048_576); XCTFail() } catch {}
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
    func testLateCredentialRefreshCannotStartMediaAfterCancellationExpiryOrLogout() async throws {
        for mode in 0...2 {
            let a = authorization(), source = GrantStub(a, bearerDelay: .milliseconds(300)), transport = RangeTransport()
            let channel = AuthorizedMediaChannel(authorization: a, authorizer: source, transport: transport, lifetime: mode == 0 ? 0.1 : 90)
            let request = Task { try await channel.size() }
            try await Task.sleep(for: .milliseconds(50))
            if mode == 1 { request.cancel() }; if mode == 2 { await source.revoke() }
            do { _ = try await request.value; XCTFail("Late credential crossed playback boundary") } catch {}
            try await Task.sleep(for: .milliseconds(350))
            let count = await transport.requests.count; XCTAssertEqual(count, 0)
        }
    }
    func testLyricsPreviewOffsetAndGaps() {
        let lyrics = MusicLyrics(kind: "timed", text: "", lines: [.init(startSeconds: 12, text: "one"), .init(startSeconds: 16, text: "two")], audioVersion: 1)
        XCTAssertNil(lyrics.current(at: 10)); XCTAssertEqual(lyrics.current(at: 1 + 12), 0); XCTAssertEqual(lyrics.current(at: 4 + 12), 1)
    }
}

private final class BoundedAudioProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "media.fixture" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 206, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "audio/mpeg"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(repeating: 7, count: request.url?.path == "/exact" ? 524_288 : 524_289))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private actor SlowMediaTransport: MediaHTTPTransport {
    func send(_ request: URLRequest) async throws -> MediaHTTPResult {
        // Deliberately ignores parent cancellation like a separately coalesced refresh.
        await Task.detached { try? await Task.sleep(for: .seconds(7)) }.value
        return MediaHTTPResult(status: 503, data: Data(), headers: [:])
    }
}

private actor SuspendedMediaTransport: MediaHTTPTransport {
    let holdMethod: String; let fails: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    var waiting: Bool { continuation != nil }
    init(holdMethod: String, fails: Bool = false) { self.holdMethod = holdMethod; self.fails = fails }
    func release() { continuation?.resume(); continuation = nil }
    func send(_ request: URLRequest) async throws -> MediaHTTPResult {
        if request.httpMethod == holdMethod {
            await withCheckedContinuation { continuation = $0 }
            if fails { throw APIError.rejected(403) }
        }
        let response = try await RangeTransport().send(request)
        return MediaHTTPResult(status: response.status, data: Data(repeating: 1, count: response.data.count), headers: response.headers)
    }
}
