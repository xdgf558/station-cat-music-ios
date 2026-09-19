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
    private struct RestartMarker: Codable {
        let runID: String; let pid: Int32; let scope: AccountScope; let epochAfterClear: Int
    }
    private func restartContext() throws -> (String, URL, MusicProbeBridge, NativeAuthConfiguration, URLRequest) {
        let env = ProcessInfo.processInfo.environment
        guard let run = env["M5_RESTART_RUN"], UUID(uuidString: run) != nil,
              let raw = env["M5_PROBE_PORT"], let port = Int(raw), let key = env["M5_PROBE_KEY"] else {
            throw XCTSkip("Dedicated M5 cross-process privacy probe")
        }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "M5-privacy-" + run)
        var bootstrap = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/fixture/bootstrap")!)
        bootstrap.setValue(key, forHTTPHeaderField: "X-Probe-Key")
        return (run, directory, MusicProbeBridge(port: port, key: key),
            try NativeAuthConfiguration(environment: .development, origin: URL(string: "https://native.local.test")!, explicitlyEnabled: true), bootstrap)
    }
    func testPreparePrivacyConflictForHostRestart() async throws {
        let (run, directory, bridge, config, bootstrap) = try restartContext()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        let (data, _) = try await URLSession.shared.data(for: bootstrap)
        let fixture = try NativeJSON.decoder().decode(LibraryFixture.self, from: data)
        let journal = AuthJournal(store: KeychainStore(service: "org.stationcat.music.m5.privacy." + run), environment: .development)
        try await journal.install(fixture.first)
        let auth = NativeAuthenticationService(configuration: config, api: NativeAuthAPI(configuration: config, transport: bridge), journal: journal, browser: LibraryBrowser())
        try await auth.restore()
        let first = try NativeLibraryAPI(configuration: config, explicitlyEnabled: true, auth: auth, transport: bridge)
        let secondJournal = AuthJournal(store: MemorySecureStore(), environment: .development)
        try await secondJournal.install(fixture.second)
        let secondAuth = NativeAuthenticationService(configuration: config, api: NativeAuthAPI(configuration: config, transport: bridge), journal: secondJournal, browser: LibraryBrowser())
        try await secondAuth.restore()
        let second = try NativeLibraryAPI(configuration: config, explicitlyEnabled: true, auth: secondAuth, transport: bridge)
        let scope = fixture.first.scope, one = ScopedLibrary(directory: directory.appending(path: "library")), two = ScopedLibrary()
        try await one.synchronize(scope: scope, remote: first); try await two.synchronize(scope: scope, remote: second)
        let baseline = try await first.snapshot(scope: scope)
        XCTAssertEqual(baseline.preferences.version, 0); XCTAssertEqual(baseline.preferences.historyEpoch, 0)
        try await one.setHistory(false, scope: scope); try await one.setHistory(true, scope: scope)
        let track = Track(id: fixture.trackId, title: "Privacy regression fixture", artist: "Fixture", durationSeconds: fixture.durationSeconds, audioVersion: 1, access: .free)
        try await one.record(track, variant: "full", audible: 5, position: 5, eventID: UUID().uuidString, scope: scope)
        let pending = try await one.view(in: scope); XCTAssertEqual(pending.pending, 3)
        // B clears after A's offline event; A's first privacy request now gets a real Worker 409.
        try await two.clearHistory(scope: scope); try await two.synchronize(scope: scope, remote: second)
        try await one.synchronize(scope: scope, remote: first)
        let conflicted = try await one.view(in: scope), remote = try await second.snapshot(scope: scope)
        XCTAssertTrue(conflicted.conflict); XCTAssertEqual(conflicted.pending, 1)
        XCTAssertFalse(conflicted.historyEnabled); XCTAssertTrue(conflicted.recent.isEmpty)
        XCTAssertTrue(remote.recent.isEmpty); XCTAssertEqual(remote.preferences.historyEpoch, 1)
        let marker = RestartMarker(runID: run, pid: ProcessInfo.processInfo.processIdentifier, scope: scope, epochAfterClear: remote.preferences.historyEpoch)
        try JSONEncoder().encode(marker).write(to: directory.appending(path: "marker.json"), options: .atomic)
        try await secondAuth.signOut()
        // Keep only the first session in a dedicated Keychain namespace for the new test host.
        print("M5_PRIVACY_PREPARED run=\(run) pid=\(marker.pid)")
    }
    func testRecoverPrivacyConflictInNewHost() async throws {
        let (run, directory, bridge, config, _) = try restartContext()
        let marker = try JSONDecoder().decode(RestartMarker.self, from: Data(contentsOf: directory.appending(path: "marker.json")))
        XCTAssertEqual(marker.runID, run); XCTAssertNotEqual(marker.pid, ProcessInfo.processInfo.processIdentifier)
        let store = KeychainStore(service: "org.stationcat.music.m5.privacy." + run)
        let journal = AuthJournal(store: store, environment: .development)
        let saved = try await journal.read(); XCTAssertEqual(saved?.scope, marker.scope)
        let auth = NativeAuthenticationService(configuration: config, api: NativeAuthAPI(configuration: config, transport: bridge), journal: journal, browser: LibraryBrowser())
        try await auth.restore()
        let remote = try NativeLibraryAPI(configuration: config, explicitlyEnabled: true, auth: auth, transport: bridge)
        let library = ScopedLibrary(directory: directory.appending(path: "library"))
        let before = try await library.view(in: marker.scope)
        XCTAssertEqual(before.pending, 1); XCTAssertFalse(before.historyEnabled); XCTAssertTrue(before.recent.isEmpty)
        try await library.synchronize(scope: marker.scope, remote: remote)
        let after = try await library.view(in: marker.scope), snapshot = try await remote.snapshot(scope: marker.scope)
        XCTAssertEqual(after.pending, 0); XCTAssertFalse(after.historyEnabled); XCTAssertTrue(after.recent.isEmpty)
        XCTAssertTrue(snapshot.recent.isEmpty); XCTAssertFalse(snapshot.preferences.historyEnabled)
        XCTAssertEqual(snapshot.preferences.historyEpoch, marker.epochAfterClear + 1)
        // A second sync must remain empty even after all pending operations have drained.
        try await library.synchronize(scope: marker.scope, remote: remote)
        let again = try await remote.snapshot(scope: marker.scope); XCTAssertTrue(again.recent.isEmpty)
        try await auth.signOut()
        let removed = try await store.read("auth.development"); XCTAssertNil(removed)
        try FileManager.default.removeItem(at: directory)
        print("M5_PRIVACY_RESTART_PASSED run=\(run) old=\(marker.pid) new=\(ProcessInfo.processInfo.processIdentifier)")
    }

}
