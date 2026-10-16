import XCTest
@testable import StationCatMusic

private nonisolated struct PlatformTestReply: Sendable {
    let data: Data
    var status = 200
    var mime = "application/json; charset=utf-8"
    var redirected = false
    var delay: Duration = .zero
    var headers: [String: String] = [:]
}
private actor PlatformTestTransport: HTTPTransport {
    let replies: [PlatformTestReply]
    private(set) var requests: [URLRequest] = []
    init(_ replies: [PlatformTestReply]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request)
        let reply = replies[min(requests.count - 1, replies.count - 1)]
        try await Task.sleep(for: reply.delay)
        try Task.checkCancellation()
        return HTTPResult(status: reply.status, data: reply.data, headers: reply.headers.merging(["content-type": reply.mime], uniquingKeysWith: { _, new in new }),
            finalURL: reply.redirected ? URL(string: "https://unassociated.example.test/") : request.url)
    }
}

/// Details remain suspended until the test explicitly releases them. This
/// proves concurrent starts without relying on response latency measurements.
private actor PlatformFeaturedTransport: HTTPTransport {
    let home: PlatformTestReply
    let details: [String: PlatformTestReply]
    private(set) var requests: [URLRequest] = []
    private(set) var completed: [String] = []
    private var waiting: [String: CheckedContinuation<Void, Never>] = [:]
    private var releasedAll: Bool
    init(home: PlatformTestReply, details: [String: PlatformTestReply], held: Bool = true) {
        self.home = home; self.details = details; releasedAll = !held
    }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request)
        let path = request.url!.path
        let reply: PlatformTestReply
        if path == "/api/station/content/home" { reply = home }
        else {
            guard let value = details[path] else { throw APIError.invalidRequest }
            reply = value
            if !releasedAll { await withCheckedContinuation { waiting[path] = $0 } }
            try Task.checkCancellation()
            completed.append(path)
        }
        return HTTPResult(status: reply.status, data: reply.data, headers: ["content-type": reply.mime], finalURL: request.url)
    }
    func release(_ path: String) { waiting.removeValue(forKey: path)?.resume() }
    func releaseAll() {
        releasedAll = true
        let held = waiting.values; waiting.removeAll()
        for continuation in held { continuation.resume() }
    }
    func counts() -> (started: Int, completed: Int) {
        (requests.filter { $0.url?.path != "/api/station/content/home" }.count, completed.count)
    }
}

@MainActor final class PlatformMusicTests: XCTestCase {
    private let firstID = "11111111-1111-4111-8111-111111111111"
    private let secondID = "22222222-2222-4222-8222-222222222222"
    private let firstLinkID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    private let secondLinkID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    private let assetID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    private func json(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
    private func href(_ slug: String, locale: String = "en") -> String {
        (locale == "zh-Hant" ? "" : locale == "zh-Hans" ? "/zh-hans" : "/" + locale) + "/music/tracks/" + slug + "/"
    }
    private func link(_ id: String? = nil, provider: String = "netease", url: String = "https://music.163.com/#/song?id=123456789", status: String = "live", verified: String = "2026-01-01T00:00:00.000Z") -> [String: Any] {
        ["id": id ?? firstLinkID, "provider": provider, "status": status, "href": url, "verifiedAt": verified]
    }
    private func track(_ id: String? = nil, slug: String = "a-slower-day", locale: String = "en", links: [[String: Any]]? = nil) -> [String: Any] {
        ["id": id ?? firstID, "slug": slug, "revision": 2, "originalLocale": "en", "title": "A Slower Day", "artist": "Station Cat",
         "summary": "Slow down a little.", "durationMs": NSNull(), "href": href(slug, locale: locale),
         "coverUrl": "/api/station/content/assets/" + assetID, "preview": NSNull(), "fullPlayback": NSNull(),
         "platformAvailability": ["state": "available", "notes": []], "platforms": links ?? [link()],
         "story": "A song\nfor the evening.", "lyricsUrl": "/api/station/content/assets/" + assetID]
    }
    private func page(_ tracks: [[String: Any]], locale: String = "en", cursor: String? = nil, schema: Int = 1) throws -> PlatformTestReply {
        PlatformTestReply(data: try json(["schemaVersion": schema, "locale": locale, "items": tracks, "nextCursor": cursor as Any? ?? NSNull()]))
    }
    private func detail(_ track: [String: Any], locale: String = "en") throws -> PlatformTestReply {
        PlatformTestReply(data: try json(["schemaVersion": 1, "locale": locale, "track": track, "related": []]))
    }
    private func summary(_ value: [String: Any]) -> [String: Any] {
        value.filter { ["id", "title", "artist", "summary", "coverUrl", "href"].contains($0.key) }
    }
    private func home(_ primary: [String: Any]?, selected: [[String: Any]] = [], locale: String = "en") throws -> PlatformTestReply {
        PlatformTestReply(data: try json(["schemaVersion": 1, "home": ["locale": locale, "fixture": false,
            "music": primary.map(summary) as Any? ?? NSNull(), "selectedTracks": selected.map(summary)]]))
    }
    private func api(_ transport: any HTTPTransport) throws -> PlatformMusicAPI {
        try PlatformMusicAPI(explicitlyEnabled: true, transport: transport,
            now: { Date(timeIntervalSince1970: 1_900_000_000) })
    }
    func testDirectSlugDoesNotRequireCatalogAndChecksIdentityAndLocale() async throws {
        let transport = PlatformTestTransport([try detail(track())])
        let client = try api(transport)
        let result = try await client.resolvePlatformTrack(slug: "a-slower-day", locale: "en")
        XCTAssertEqual(result.track.id, firstID)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url?.path, "/api/station/content/tracks/a-slower-day")
        XCTAssertNil(requests.first?.value(forHTTPHeaderField: "Authorization"))
        for value in [track(slug: "wrong-song"), track("not-a-uuid"), track(locale: "ja")] {
            let invalid = try api(PlatformTestTransport([try detail(value)]))
            do { _ = try await invalid.resolvePlatformTrack(slug: "a-slower-day", locale: "en"); XCTFail("Bad identity accepted") }
            catch { XCTAssertEqual(error as? APIError, .invalidPayload) }
        }
    }
    func testBookmarkRequiresExplicitFreshCachePermissionAndMatchingID() async throws {
        let data = try json(["schemaVersion":1,"locale":"en","bookmark":["id":firstID,"slug":"a-slower-day","revision":2,"title":"Saved title","artist":"Station Cat"]])
        let timestamp = Date(timeIntervalSince1970: 1_900_000_000)
        let date = DateFormatter(); date.locale = Locale(identifier: "en_US_POSIX"); date.timeZone = TimeZone(secondsFromGMT: 0); date.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let validHeaders = ["Cache-Control":"private, max-age=86400, must-revalidate", "Date": date.string(from: timestamp)]
        let seed = try api(PlatformTestTransport([try page([track()])]))
        let catalog = try await seed.catalog()
        let target = try XCTUnwrap(catalog.items.first)
        let permitted = try api(PlatformTestTransport([PlatformTestReply(data: data, headers: validHeaders)]))
        let saved = try await permitted.bookmark(target, locale: "en")
        XCTAssertEqual(saved.title, "Saved title"); XCTAssertLessThanOrEqual(saved.expires.timeIntervalSince(timestamp), 86400)
        for headers in [[:], ["Cache-Control":"no-store"], validHeaders.merging(["Vary":"*"], uniquingKeysWith: { _, new in new }), validHeaders.merging(["Age":"86400"], uniquingKeysWith: { _, new in new }), validHeaders.merging(["Cache-Control":"private, max-age=0"], uniquingKeysWith: { _, new in new })] {
            let denied = try api(PlatformTestTransport([PlatformTestReply(data: data, headers: headers)]))
            do { _ = try await denied.bookmark(target, locale: "en"); XCTFail("Cache denial ignored") }
            catch { XCTAssertEqual(error as? APIError, .invalidPayload) }
        }
        let changedData = try json(["schemaVersion":1,"locale":"en","bookmark":["id":secondID,"slug":"a-slower-day","revision":2,"title":"Wrong identity","artist":"Station Cat"]])
        let changed = try api(PlatformTestTransport([PlatformTestReply(data: changedData, headers: validHeaders)]))
        do { _ = try await changed.bookmark(target, locale: "en"); XCTFail("Wrong bookmark identity accepted") }
        catch { XCTAssertEqual(error as? APIError, .invalidPayload) }
    }
    private func featuredTransport(_ primary: [String: Any], selected: [[String: Any]], held: Bool = true) throws -> PlatformFeaturedTransport {
        let values = [primary] + selected
        var replies: [String: PlatformTestReply] = [:]
        for value in values { replies["/api/station/content/tracks/" + (value["slug"] as! String)] = try detail(value) }
        return PlatformFeaturedTransport(home: try home(primary, selected: selected), details: replies, held: held)
    }
    private func waitForDetails(_ transport: PlatformFeaturedTransport, started: Int, completed: Int = 0) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            let counts = await transport.counts()
            if counts.started == started, counts.completed == completed { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        let counts = await transport.counts()
        XCTFail("Featured detail gate did not reach expected counts: \(counts), expected \(started)/\(completed)")
        // A serial implementation must fail the assertion without stranding its
        // current or later requests in continuations when the test tears down.
        await transport.releaseAll()
    }
    private func expectCatalogFailure(_ reply: PlatformTestReply) async throws {
        let client = try api(PlatformTestTransport([reply]))
        do { _ = try await client.catalog(); XCTFail("Invalid metadata was accepted") } catch {}
    }
    func testPublicCatalogNormalizesNetEaseAndNeverGrantsPlaybackOrOffline() async throws {
        let transport = PlatformTestTransport([try page([track()])]), client = try api(transport)
        let catalog = try await client.catalog(), item = try XCTUnwrap(catalog.items.first)
        XCTAssertEqual(item.id, firstID); XCTAssertEqual(item.durationSeconds, 0)
        XCTAssertEqual(item.access, .unavailable); XCTAssertEqual(item.offlineEligible, false)
        XCTAssertEqual(item.release?.platforms.first?.url.absoluteString, "https://music.163.com/song?id=123456789")
        XCTAssertEqual(item.release?.previewAvailable, false)
        XCTAssertEqual(item.coverUrl?.path, "/api/station/content/assets/" + assetID)
        XCTAssertEqual(item.coverUrl?.query, "size=display")
        let sent = await transport.requests
        let request = try XCTUnwrap(sent.first)
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertEqual(request.timeoutInterval, 5)
        XCTAssertFalse(request.httpShouldHandleCookies); XCTAssertNil(request.httpBody)
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie")); XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request.url?.path, "/api/station/content/tracks")
        XCTAssertEqual(request.allHTTPHeaderFields?.count, 1)
    }
    func testVersionedCoverKeyChangesWithArtworkAndOldCatalogsRemainCompatible() async throws {
        let fingerprint = String(repeating: "a", count: 64)
        var first = track(); first["coverCacheVersion"] = fingerprint
        let firstAPI = try api(PlatformTestTransport([try page([first])]))
        let firstCatalog = try await firstAPI.catalog()
        let url = try XCTUnwrap(firstCatalog.items.first?.coverUrl)
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.queryItems, [.init(name: "size", value: "display"), .init(name: "v", value: fingerprint)])
        let card = PlatformArtwork.url(url, thumbnail: true)
        XCTAssertEqual(URLComponents(url: card, resolvingAgainstBaseURL: false)?.queryItems,
            [.init(name: "size", value: "card"), .init(name: "v", value: fingerprint)])
        var updated = first; updated["coverCacheVersion"] = String(repeating: "b", count: 64)
        let secondAPI = try api(PlatformTestTransport([try page([updated])]))
        let changed = try await secondAPI.catalog().items[0].coverUrl
        XCTAssertNotEqual(url, changed)
        for version in ["../source", String(repeating: "A", count: 64), String(repeating: "a", count: 65)] {
            var invalid = first; invalid["coverCacheVersion"] = version
            try await expectCatalogFailure(page([invalid]))
        }
        var missing = first; missing["coverUrl"] = NSNull()
        try await expectCatalogFailure(page([missing]))
        let oldAPI = try api(PlatformTestTransport([try page([track()])]))
        let old = try await oldAPI.catalog().items[0].coverUrl
        XCTAssertEqual(old?.query, "size=display")
    }
    func testAllProvidersUseExactHostsAndNetEaseHasOnlyOneFragmentException() {
        let allowed: [(PlatformProvider, String)] = [(.netease, "https://y.music.163.com/m/song?id=123"),
            (.qishui, "https://qishui.douyin.com/song/123"), (.appleMusic, "https://music.apple.com/us/album/demo/123"),
            (.youtube, "https://youtu.be/example123"), (.spotify, "https://open.spotify.com/track/example")]
        for (provider, value) in allowed { XCTAssertNotNil(PlatformMusicAPI.platformURL(value, provider: provider), value) }
        let invalid = ["http://music.163.com/song?id=1", "https://music.163.com.evil.test/song?id=1", "https://user@music.163.com/song?id=1",
            "https://music.163.com:444/song?id=1", "https://music.163.com/login", "https://music.163.com/redirect/go",
            "https://music.163.com/song?redirect=https://evil.test", "https://music.163.com/song?%74oken=private",
            "https://music.163.com/song?next=private", "https://music.163.com/song?signature=private", "https://music.163.com/",
            "https://music.163.com/#/song?id=1&extra=2", "https://music.163.com/#/song?id=0", "https://music.163.com/#/album?id=1",
            "https://music.163.com/?x=1#/song?id=1", "https://music.163.com/song?id=1#other", "https://music.163.com/song\\evil",
            "https://music.163.com/song? target=evil", "javascript:alert(1)"]
        for value in invalid { XCTAssertNil(PlatformMusicAPI.platformURL(value, provider: .netease), value) }
        XCTAssertNil(PlatformMusicAPI.platformURL("https://youtu.be/example#fragment", provider: .youtube))
        XCTAssertNil(PlatformMusicAPI.platformURL("https://music.apple.com/us/album/demo/123", provider: .netease))
    }
    func testMalformedUnverifiedFutureAndDuplicateLinksAreDroppedInOperatorOrder() async throws {
        let links = [link(secondLinkID, provider: "spotify", url: "https://open.spotify.com/track/one"), link(),
            link(), link(UUID().uuidString, status: "planned"), link(UUID().uuidString, verified: "2100-01-01T00:00:00Z"),
            link(UUID().uuidString, provider: "unknown"), link(UUID().uuidString, url: "https://evil.example.test/song"),
            link(UUID().uuidString, verified: "not-a-date"), link(UUID().uuidString, verified: "1960-01-01T00:00:00Z")]
        let client = try api(PlatformTestTransport([try page([track(links: links)])]))
        let catalog = try await client.catalog()
        let item = try XCTUnwrap(catalog.items.first)
        XCTAssertEqual(item.release?.platforms.map(\.id), [secondLinkID])
        let ordered = try api(PlatformTestTransport([try page([track(links: [link(secondLinkID), link()])])]))
        let valid = try await ordered.catalog()
        XCTAssertEqual(valid.items[0].release?.platforms.map(\.id), [secondLinkID, firstLinkID])
    }
    func testUnreleasedAndInvalidAvailableRecordsHaveNoInventedListeningTarget() async throws {
        var value = track(links: []); value["platformAvailability"] = ["state": "unreleased"]
        let client = try api(PlatformTestTransport([try page([value])]))
        let item = try await client.catalog().items[0]
        XCTAssertEqual(item.release?.availability, "unreleased"); XCTAssertEqual(item.release?.platforms, [])
        let invalid = try api(PlatformTestTransport([try page([track(links: [link(url: "https://evil.test/song")])])]))
        let invalidItem = try await invalid.catalog().items[0]
        XCTAssertEqual(invalidItem.release?.availability, "unconfirmed")
    }
    func testDetailUsesPublicStoryAndControlledLyricsWithoutRequestingTheirBodies() async throws {
        let value = track(), transport = PlatformTestTransport([try page([value]), try detail(value)])
        let client = try api(transport), item = try await client.catalog().items[0]
        let result = try await client.platformDetail(item, locale: "en")
        XCTAssertEqual(result.story, "A song\nfor the evening.")
        XCTAssertEqual(result.lyricsURL?.path, "/api/station/content/assets/" + assetID)
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url!.path }, ["/api/station/content/tracks", "/api/station/content/tracks/a-slower-day"])
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "GET" && $0.value(forHTTPHeaderField: "Authorization") == nil && $0.value(forHTTPHeaderField: "Cookie") == nil })
    }
    func testFeaturedPreservesPrimaryAndSelectedOrderAndEmptyConfigurationStaysEmpty() async throws {
        let first = track(), second = track(secondID, slug: "night-window")
        let transport = try featuredTransport(second, selected: [first], held: false)
        let client = try api(transport), featured = try await client.featuredTracks()
        XCTAssertEqual(featured.map(\.id), [secondID, firstID])
        let sent = await transport.requests
        XCTAssertEqual(sent.first?.url?.path, "/api/station/content/home")
        XCTAssertEqual(sent.dropFirst().map { $0.url!.path }.sorted(), ["/api/station/content/tracks/a-slower-day", "/api/station/content/tracks/night-window"])
        let emptyTransport = PlatformTestTransport([try home(nil)]), emptyClient = try api(emptyTransport)
        let empty = try await emptyClient.featuredTracks()
        let emptyCount = await emptyTransport.requests.count
        XCTAssertTrue(empty.isEmpty); XCTAssertEqual(emptyCount, 1)
    }
    func testFeaturedDetailsStartTogetherAndReverseCompletionPreservesEditorOrder() async throws {
        let thirdID = "33333333-3333-4333-8333-333333333333", fourthID = "44444444-4444-4444-8444-444444444444"
        let values = [track(), track(secondID, slug: "night-window"), track(thirdID, slug: "morning-light"), track(fourthID, slug: "far-away")]
        let transport = try featuredTransport(values[0], selected: Array(values.dropFirst()))
        let client = try api(transport), pending = Task { try await client.featuredTracks() }
        try await waitForDetails(transport, started: 4)
        let paths = values.map { "/api/station/content/tracks/" + ($0["slug"] as! String) }
        for (index, path) in paths.reversed().enumerated() {
            await transport.release(path)
            try await waitForDetails(transport, started: 4, completed: index + 1)
        }
        await transport.releaseAll()
        let featured = try await pending.value, completed = await transport.completed
        XCTAssertEqual(completed, Array(paths.reversed()))
        XCTAssertEqual(featured.map(\.id), [firstID, secondID, thirdID, fourthID])
    }
    func testLocaleSwitchRejectsAllLateFeaturedDetails() async throws {
        let transport = try featuredTransport(track(), selected: [track(secondID, slug: "night-window")])
        let client = try api(transport), pending = Task { try await client.featuredTracks() }
        try await waitForDetails(transport, started: 2)
        await client.setLocale("ja"); await transport.releaseAll()
        do { _ = try await pending.value; XCTFail("Late featured language result was accepted") }
        catch { XCTAssertEqual(error as? APIError, .staleResponse) }
        let requests = await transport.requests
        XCTAssertTrue(requests.allSatisfy {
            URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "locale" }?.value == "en"
        })
    }
    func testCancelledFeaturedGroupDoesNotPublishCompletedDetails() async throws {
        let transport = try featuredTransport(track(), selected: [track(secondID, slug: "night-window")])
        let client = try api(transport), pending = Task { try await client.featuredTracks() }
        try await waitForDetails(transport, started: 2)
        pending.cancel(); await transport.releaseAll()
        do { _ = try await pending.value; XCTFail("Cancelled featured result was accepted") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testFailedFeaturedDetailRejectsTheWholeGroupAndInvalidSummaryStartsNone() async throws {
        let primary = track(), selected = track(secondID, slug: "night-window")
        var failed = try detail(selected); failed.status = 503
        let transport = PlatformFeaturedTransport(home: try home(primary, selected: [selected]), details: [
            "/api/station/content/tracks/a-slower-day": try detail(primary), "/api/station/content/tracks/night-window": failed])
        let client = try api(transport), pending = Task { try await client.featuredTracks() }
        try await waitForDetails(transport, started: 2)
        await transport.releaseAll()
        do { _ = try await pending.value; XCTFail("Partial featured result was published") }
        catch { XCTAssertEqual(error as? APIError, .rejected(503)) }
        var invalid = selected; invalid["coverUrl"] = "https://evil.test/cover"
        let invalidTransport = PlatformFeaturedTransport(home: try home(primary, selected: [invalid]), details: [:], held: false)
        let invalidClient = try api(invalidTransport)
        do { _ = try await invalidClient.featuredTracks(); XCTFail("Invalid summary was accepted") }
        catch { XCTAssertEqual(error as? APIError, .invalidPayload) }
        let count = await invalidTransport.requests.count
        XCTAssertEqual(count, 1)
    }
    func testPaginationKeepsCursorAndRejectsDuplicateTracksOrLoops() async throws {
        let transport = PlatformTestTransport([try page([track()], cursor: "page_2"), try page([track(secondID, slug: "night-window")])])
        let client = try api(transport), items = try await client.catalog().items
        XCTAssertEqual(items.map(\.id), [firstID, secondID])
        let query = URLComponents(url: (await transport.requests)[1].url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "cursor" }?.value, "page_2")
        let duplicates = try api(PlatformTestTransport([try page([track()], cursor: "page_2"), try page([track()])]))
        do { _ = try await duplicates.catalog(); XCTFail("Duplicate track was accepted") } catch { XCTAssertEqual(error as? APIError, .invalidPayload) }
        let loopTransport = PlatformTestTransport([try page([], cursor: "same_cursor")]), loop = try api(loopTransport)
        do { _ = try await loop.catalog(); XCTFail("Cursor loop was accepted") } catch {}
        let loopCount = await loopTransport.requests.count
        XCTAssertEqual(loopCount, 2)
    }
    func testCatalogHasATenPageFiveHundredTrackBudgetEvenForEmptyFilteredPages() async throws {
        var replies: [PlatformTestReply] = []
        for index in 0..<10 { replies.append(try page([], cursor: "page_" + String(index + 1))) }
        let transport = PlatformTestTransport(replies), client = try api(transport)
        do { _ = try await client.catalog(); XCTFail("Unbounded pagination was accepted") } catch {}
        let count = await transport.requests.count
        XCTAssertEqual(count, 10)
    }
    func testWrongSchemaLocaleIdentityHrefAndUnsafeAssetsFailClosed() async throws {
        try await expectCatalogFailure(page([track()], schema: 2))
        try await expectCatalogFailure(page([track()], locale: "ja"))
        for (key, invalid) in [("id", "not-a-uuid"), ("slug", "../other"), ("href", "https://evil.test/music"),
                               ("coverUrl", "https://wwwstationcat.org/api/music/tracks/" + firstID + "/cover"),
                               ("coverUrl", "/api/station/content/assets/" + assetID + "?redirect=evil")] {
            var value = track(); value[key] = invalid; try await expectCatalogFailure(page([value]))
        }
    }
    func testWrongMimeOversizedBodiesErrorsAndRedirectsAreRejected() async throws {
        var mime = try page([track()]); mime.mime = "text/html"
        var redirect = try page([track()]); redirect.redirected = true
        var error = try page([track()]); error.status = 503
        var redirectStatus = try page([track()]); redirectStatus.status = 302
        for reply in [mime, redirect, error, redirectStatus, PlatformTestReply(data: Data(repeating: 32, count: 262_145)), PlatformTestReply(data: Data("not-json".utf8))] {
            try await expectCatalogFailure(reply)
        }
    }
    func testPreviewAffordanceDoesNotGrantNativeAudioAndMalformedPreviewIsRejected() async throws {
        var value = track(); value["preview"] = ["revision": 1, "durationMs": 20_000, "playbackPath": "/api/station/content/tracks/a-slower-day/playback?variant=preview"]
        let transport = PlatformTestTransport([try page([value])]), client = try api(transport)
        let item = try await client.catalog().items[0]
        XCTAssertEqual(item.release?.previewAvailable, true); XCTAssertEqual(item.access, .unavailable); XCTAssertEqual(item.offlineEligible, false)
        let count = await transport.requests.count
        XCTAssertEqual(count, 1)
        value["preview"] = ["revision": 1, "durationMs": 20_000, "playbackPath": "/api/station/content/tracks/a-slower-day/playback?variant=full"]
        try await expectCatalogFailure(page([value]))
    }
    func testLocaleSwitchRejectsLateCatalogAndSupportsAllFourRoutes() async throws {
        var delayed = try page([track()]); delayed.delay = .milliseconds(100)
        let transport = PlatformTestTransport([delayed]), client = try api(transport)
        let pending = Task { try await client.catalog() }
        try await Task.sleep(for: .milliseconds(25)); await client.setLocale("ja")
        do { _ = try await pending.value; XCTFail("Late language result was accepted") } catch { XCTAssertEqual(error as? APIError, .staleResponse) }
        for locale in PlatformMusicAPI.locales {
            let localized = try api(PlatformTestTransport([try page([track(locale: locale)], locale: locale)]))
            await localized.setLocale(locale)
            let item = try await localized.catalog().items[0]
            XCTAssertEqual(item.release?.webURL.absoluteString, PlatformMusicAPI.productionOrigin.absoluteString + href("a-slower-day", locale: locale))
        }
    }
    func testDisabledAndAlternateOriginsNeverReachTransport() async throws {
        let transport = PlatformTestTransport([try page([])])
        XCTAssertThrowsError(try PlatformMusicAPI(explicitlyEnabled: false, transport: transport))
        for value in ["http://wwwstationcat.org", "https://stationcat.org", "https://wwwstationcat.org.evil.test", "https://user@wwwstationcat.org", "https://wwwstationcat.org:444", "https://wwwstationcat.org/path", "https://wwwstationcat.org?token=secret"] {
            XCTAssertThrowsError(try PlatformMusicAPI(origin: URL(string: value)!, explicitlyEnabled: true, transport: transport))
        }
        let count = await transport.requests.count
        XCTAssertEqual(count, 0)
    }
    func testLegacyTrackWithoutReleaseStillDecodes() throws {
        let data = try json(["id": firstID, "title": "Old", "artist": "Station Cat", "durationSeconds": 30, "audioVersion": 1, "access": "free"])
        let result = try JSONDecoder().decode(Track.self, from: data)
        XCTAssertNil(result.release); XCTAssertEqual(result.access, .free)
    }
}
