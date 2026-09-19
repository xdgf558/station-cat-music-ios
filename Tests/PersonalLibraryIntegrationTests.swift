import XCTest
@testable import StationCatMusic
private struct LibraryFixture: Decodable { let first: CredentialEnvelope; let second: CredentialEnvelope; let other: CredentialEnvelope; let trackId: String; let anotherTrackId: String; let durationSeconds: Double }
private struct LibraryBrowser: AuthenticationBrowser {
    @MainActor func authorize(url: URL, callback: URL) throws -> URL { throw APIError.networkDisabled }
}
@MainActor final class PersonalLibraryIntegrationTests: XCTestCase {
    func testRealWorkerTwoDevicesConflictHistoryEpochAndAudiblePlayback() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["M5_PROBE_PORT"], let port = Int(raw), let key = env["M5_PROBE_KEY"] else { throw XCTSkip("Dedicated M5 isolated library probe") }
        let bridge = MusicProbeBridge(port: port, key: key)
        var bootstrap = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/fixture/bootstrap")!); bootstrap.setValue(key, forHTTPHeaderField: "X-Probe-Key")
        let (data, _) = try await URLSession.shared.data(for: bootstrap)
        let fixture = try NativeJSON.decoder().decode(LibraryFixture.self, from: data)
        let config = try NativeAuthConfiguration(environment: .development, origin: URL(string: "https://native.local.test")!, explicitlyEnabled: true)
        func client(_ credential: CredentialEnvelope) async throws -> (NativeLibraryAPI, NativeAuthenticationService) {
            let journal = AuthJournal(store: MemorySecureStore(), environment: .development); try await journal.install(credential)
            let auth = NativeAuthenticationService(configuration: config, api: NativeAuthAPI(configuration: config, transport: bridge), journal: journal, browser: LibraryBrowser())
            try await auth.restore()
            return (try NativeLibraryAPI(configuration: config, explicitlyEnabled: true, auth: auth, transport: bridge), auth)
        }
        let (first, auth) = try await client(fixture.first), (second, _) = try await client(fixture.second), (other, _) = try await client(fixture.other)
        let scope = fixture.first.scope, one = ScopedLibrary(), two = ScopedLibrary()
        let track = Track(id: fixture.trackId, title: "M5 synthesized music", artist: "Fixture", durationSeconds: fixture.durationSeconds, audioVersion: 1, access: .free)
        try await one.setFavorite(track.id, value: true, scope: scope); try await one.synchronize(scope: scope, remote: first)
        try await two.synchronize(scope: scope, remote: second)
        let shared = try await two.view(in: scope); XCTAssertEqual(shared.favorites, [track.id])
        let isolated = try await other.snapshot(scope: fixture.other.scope); XCTAssertTrue(isolated.favorites.isEmpty)
        try await one.setFavorite(track.id, value: false, scope: scope); try await one.synchronize(scope: scope, remote: first)
        try await two.setFavorite(track.id, value: true, scope: scope); try await two.synchronize(scope: scope, remote: second)
        let conflicted = try await two.view(in: scope); XCTAssertTrue(conflicted.conflict); XCTAssertTrue(conflicted.favorites.isEmpty)
        // Separate songs on two native sessions must survive account-level transaction contention.
        try await one.setFavorite(track.id, value: true, scope: scope)
        try await two.setFavorite(fixture.anotherTrackId, value: true, scope: scope)
        async let left: Void = one.synchronize(scope: scope, remote: first)
        async let right: Void = two.synchronize(scope: scope, remote: second)
        _ = try await (left, right)
        let concurrent = try await first.snapshot(scope: scope)
        XCTAssertEqual(Set(concurrent.favorites.filter(\.favorite).map(\.trackId)), [track.id, fixture.anotherTrackId])
        // An older offline event arriving second must not replace the newer event's position.
        let occurred = Date().addingTimeInterval(-3600)
        let newerEvent = LibraryOperation(id: UUID().uuidString, created: occurred, kind: .listen, trackID: track.id, epoch: 0, audioVersion: 1, variant: "full", audibleSeconds: 5, position: 40)
        let olderEvent = LibraryOperation(id: UUID().uuidString, created: occurred.addingTimeInterval(-86400), kind: .listen, trackID: track.id, epoch: 0, audioVersion: 1, variant: "full", audibleSeconds: 5, position: 5)
        try await first.apply(newerEvent, scope: scope); try await second.apply(olderEvent, scope: scope)
        let merged = try await first.snapshot(scope: scope)
        XCTAssertEqual(merged.recent.first?.positionSeconds, 40)
        XCTAssertEqual(try XCTUnwrap(merged.recent.first?.lastPlayedAt).timeIntervalSince1970, occurred.timeIntervalSince1970, accuracy: 0.002)
        let music = try NativeMusicAPI(configuration: config, explicitlyEnabled: true, transport: bridge, auth: auth)
        let player = PlaybackService(transport: bridge); defer { player.shutdown() }
        var heard: (Double, Double, String)?
        player.onListen = { _, _, audible, position, id in heard = (audible, position, id) }
        player.configure(authorizer: music); player.select(track); player.requestPlay()
        for _ in 0..<120 { if heard != nil { break }; try await Task.sleep(for: .milliseconds(100)) }
        player.pause(); let event = try XCTUnwrap(heard)
        XCTAssertGreaterThanOrEqual(event.0, 5)
        try await one.record(track, variant: "full", audible: event.0, position: event.1, eventID: event.2, scope: scope)
        try await one.synchronize(scope: scope, remote: first)
        try await two.synchronize(scope: scope, remote: second)
        let recent = try await two.view(in: scope); XCTAssertEqual(recent.recent.map(\.trackId), [track.id])
        // Device two is offline with an old epoch while device one clears history.
        try await two.record(track, variant: "full", audible: 5, position: 5, eventID: UUID().uuidString, scope: scope)
        try await one.clearHistory(scope: scope); try await one.synchronize(scope: scope, remote: first)
        try await two.synchronize(scope: scope, remote: second)
        let cleared = try await two.view(in: scope); XCTAssertTrue(cleared.recent.isEmpty); XCTAssertEqual(cleared.pending, 0)
        try await one.setHistory(false, scope: scope); try await one.synchronize(scope: scope, remote: first)
        try await two.synchronize(scope: scope, remote: second)
        let disabled = try await two.view(in: scope); XCTAssertFalse(disabled.historyEnabled)
        try await auth.signOut()
        do { _ = try await first.snapshot(scope: scope); XCTFail("Signed-out account sent personal request") } catch {}
        print("M5_LIBRARY_PASSED: two native sessions, shared favorites, independent concurrent favorites, late offline ordering, conflict, real audible threshold, history epoch, disabled history, logout isolation")
    }
}
