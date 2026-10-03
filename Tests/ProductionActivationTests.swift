import XCTest
@testable import StationCatMusic

private actor ProductionContractFixture: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    static let trackID = "11111111-1111-4111-8111-111111111111"
    func send(_ request: URLRequest) throws -> HTTPResult {
        requests.append(request)
        let now = Date(), formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let data: [String: Any]
        switch request.url?.path {
        case "/api/mobile/v1/music/catalog":
            data = ["items": [["id": Self.trackID, "title": "Production contract fixture", "artist": "Synthetic",
                               "durationSeconds": 180, "audioVersion": 1, "access": "free"]], "nextCursor": NSNull()]
        case "/api/mobile/v1/music/tracks/" + Self.trackID + "/playback-grants":
            let deadline = formatter.string(from: now.addingTimeInterval(180))
            data = ["playbackUrl": ProductionActivationProfile.origin + "/api/mobile/v1/music/media/" + String(repeating: "G", count: 43) + "/audio",
                    "expiresAt": deadline, "playbackValidUntil": deadline, "revalidateAt": formatter.string(from: now.addingTimeInterval(90)),
                    "durationSeconds": 180, "authMode": "session_bearer", "accountId": "fixture-A", "sessionId": "fixture-session-fixture-A",
                    "trackId": Self.trackID, "audioVersion": 1, "variant": "full"]
        case "/api/mobile/v1/me/music/preferences":
            data = ["historyEnabled": true, "historyEpoch": 0, "version": 0]
        case "/api/mobile/v1/me/music/favorites":
            data = ["items": [], "nextCursor": NSNull(), "syncVersion": 0]
        case "/api/mobile/v1/me/music/recent":
            data = ["items": [], "nextCursor": NSNull(), "historyEpoch": 0]
        default: throw APIError.invalidRequest
        }
        return HTTPResult(status: 200, data: try JSONSerialization.data(withJSONObject: [
            "data": data, "serverNow": formatter.string(from: now), "requestId": "production-contract-fixture"]))
    }
}

@MainActor final class ProductionActivationTests: XCTestCase {
    private func profile(music: Bool = true, sync: Bool = true) -> [String: Any] {
        ["schemaVersion": 1, "profileId": "station-native-production-v1", "enabled": true, "environment": "production",
         "apiOrigin": "https://wwwstationcat.org", "webOrigin": "https://wwwstationcat.org",
         "callback": "https://wwwstationcat.org/auth/mobile/callback", "applicationIdentifier": "2AM5S7BM2N.org.stationcat.music",
         "capabilities": ["nativeAuthentication": true, "musicCatalog": music, "musicPlayback": music,
                          "personalSync": sync, "accountDeletion": false]]
    }
    private func info(profile: [String: Any]? = nil, music: Bool = true, sync: Bool = true) throws -> [String: Any] {
        ["StationEnvironment": "production", "CFBundleIdentifier": "org.stationcat.music",
         "StationNativeAuthEnabled": "YES", "StationNativeMusicEnabled": music ? "YES" : "NO", "StationPersonalSyncEnabled": sync ? "YES" : "NO",
         "StationNativeAuthOrigin": "https://wwwstationcat.org", "StationMusicWebOrigin": "https://wwwstationcat.org",
         "StationProductionActivationEnabled": "YES",
         "StationProductionActivationProfile": try JSONSerialization.data(withJSONObject: profile ?? self.profile()).base64EncodedString()]
    }
    private func assertClosed(_ info: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        let runtime = NativeRuntimeConfiguration(info: info)
        XCTAssertNil(runtime.authentication, file: file, line: line)
        XCTAssertFalse(runtime.musicEnabled, file: file, line: line)
        XCTAssertFalse(runtime.personalSyncEnabled, file: file, line: line)
        XCTAssertNil(runtime.musicWebOrigin, file: file, line: line)
    }
    func testMissingUnknownAndDefaultEnvironmentsStayClosed() throws {
        assertClosed([:])
        for environment in ["mock", "development", "staging", "production", "unknown"] {
            assertClosed(["StationEnvironment": environment, "StationNativeAuthEnabled": "NO",
                          "StationNativeMusicEnabled": "NO", "StationPersonalSyncEnabled": "NO",
                          "StationNativeAuthOrigin": "", "StationMusicWebOrigin": "",
                          "StationProductionActivationEnabled": "NO", "StationProductionActivationProfile": ""])
        }
        var unknown = try info(); unknown["StationEnvironment"] = "unknown"; assertClosed(unknown)
        unknown.removeValue(forKey: "StationEnvironment"); assertClosed(unknown)
    }
    func testSwitchesAloneCannotOpenProductionOrChangeItsIdentity() throws {
        for (key, value) in ["StationProductionActivationEnabled": "NO", "StationProductionActivationProfile": "",
                             "StationNativeAuthOrigin": "https://native.example.test", "StationMusicWebOrigin": "https://native.example.test",
                             "CFBundleIdentifier": "org.stationcat.music.staging", "StationNativeAuthEnabled": "NO"] {
            var changed = try info(); changed[key] = value; assertClosed(changed)
        }
        XCTAssertThrowsError(try NativeAuthConfiguration(environment: .production,
            origin: URL(string: ProductionActivationProfile.origin)!, explicitlyEnabled: true))
    }
    func testProfilesRejectWrongSchemaHostIdentityTypesAndDeletion() throws {
        let invalid: [[String: Any]] = [["schemaVersion": 2], ["schemaVersion": true], ["profileId": "future-profile"],
            ["enabled": false], ["enabled": "YES"], ["environment": "staging"], ["apiOrigin": "https://wwwstationcat.org/"],
            ["webOrigin": "https://wwwstationcat.org.evil.test"], ["callback": "https://wwwstationcat.org/auth/mobile/other"],
            ["applicationIdentifier": "2AM5S7BM2N.org.stationcat.music.staging"], ["futureApproval": true]]
        for values in invalid {
            let changed = profile().merging(values) { _, new in new }
            assertClosed(try info(profile: changed))
        }
        for values in [["accountDeletion": true], ["nativeAuthentication": false], ["musicCatalog": false], ["futureCapability": true]] {
            var changed = profile()
            changed["capabilities"] = (changed["capabilities"] as! [String: Bool]).merging(values) { _, new in new }
            assertClosed(try info(profile: changed))
        }
    }
    func testCapabilityDependenciesAndProfileUpperBounds() throws {
        assertClosed(try info(music: false, sync: true))
        assertClosed(try info(profile: profile(music: false, sync: false)))
        assertClosed(try info(profile: profile(music: true, sync: false)))
        let runtime = NativeRuntimeConfiguration(info: try info(profile: profile(music: false, sync: false), music: false, sync: false))
        let configuration = try XCTUnwrap(runtime.authentication)
        XCTAssertFalse(runtime.musicEnabled); XCTAssertFalse(runtime.personalSyncEnabled)
        XCTAssertThrowsError(try NativeMusicAPI(configuration: configuration, explicitlyEnabled: true, transport: MockTransport(data: Data())))
        let api = NativeAuthAPI(configuration: configuration, transport: AuthFixtureTransport())
        let auth = NativeAuthenticationService(configuration: configuration, api: api,
            journal: AuthJournal(store: MemorySecureStore(), environment: .production), browser: FixtureBrowser())
        XCTAssertThrowsError(try NativeLibraryAPI(configuration: configuration, explicitlyEnabled: true, auth: auth, transport: MockTransport(data: Data())))
    }
    func testProductionProfileCannotBeUsedForAnIsolatedHost() throws {
        let activation = try ProductionActivationProfile(data: JSONSerialization.data(withJSONObject: profile()), bundleIdentifier: "org.stationcat.music")
        for environment in [AppEnvironment.development, .staging, .mock, .production] {
            XCTAssertThrowsError(try NativeAuthConfiguration(environment: environment, origin: URL(string: "https://native.example.test")!,
                explicitlyEnabled: true, productionActivation: activation))
        }
    }
    func testIsolatedConfigurationsRejectBothProductionHostsAndAliases() throws {
        for environment in [AppEnvironment.development, .staging] {
            for host in ["wwwstationcat.org", "stationcat.org"] {
                for alias in [host, host.uppercased(), host + ".", host.uppercased() + "."] {
                    let origin = "https://" + alias
                    XCTAssertThrowsError(try NativeAuthConfiguration(environment: environment,
                        origin: URL(string: origin)!, explicitlyEnabled: true)) { error in
                        XCTAssertEqual(error as? APIError, .networkDisabled)
                    }
                    var settings = try info()
                    settings["StationEnvironment"] = environment.rawValue
                    settings["StationNativeAuthOrigin"] = origin
                    settings["StationMusicWebOrigin"] = origin
                    assertClosed(settings)
                }
            }
        }
    }
    func testProductionDeletionIsHiddenAndRejectedBeforeTransport() async throws {
        let runtime = NativeRuntimeConfiguration(info: try info()), configuration = try XCTUnwrap(runtime.authentication)
        let model = NativeAccountModel.configured(runtime: runtime)
        XCTAssertTrue(model.enabled); XCTAssertFalse(model.deletionEnabled); XCTAssertFalse(model.isolatedAuthentication)
        XCTAssertEqual(model.scope.environment, .production)
        let transport = AuthFixtureTransport(), api = NativeAuthAPI(configuration: configuration, transport: transport)
        for path in ["/auth/reauth", "/me/deletion-requests/prepare", "/me/deletion-requests/abcdefghijklmnop/confirm", "/deletion-requests/abcdefghijklmnop/status"] {
            do { let _ = try await api.request(path, as: NativeAcknowledged.self); XCTFail("Production deletion reached transport") }
            catch { XCTAssertEqual(error as? APIError, .networkDisabled) }
        }
        let count = await transport.requests.count; XCTAssertEqual(count, 0)
    }
    func testStagingKeepsItsIndependentAuthenticationAndDeletion() throws {
        var settings = try info()
        settings["StationEnvironment"] = "staging"
        settings["CFBundleIdentifier"] = "org.stationcat.music.staging"
        settings["StationNativeAuthOrigin"] = "https://native.example.test"
        settings["StationMusicWebOrigin"] = "https://native.example.test"
        settings["StationProductionActivationEnabled"] = "NO"
        settings["StationProductionActivationProfile"] = ""
        let runtime = NativeRuntimeConfiguration(info: settings), model = NativeAccountModel.configured(runtime: runtime)
        XCTAssertTrue(runtime.musicEnabled); XCTAssertTrue(runtime.personalSyncEnabled)
        XCTAssertTrue(model.enabled); XCTAssertTrue(model.deletionEnabled); XCTAssertTrue(model.isolatedAuthentication)
        XCTAssertEqual(runtime.authentication?.origin.host, "native.example.test")
    }
    func testCatalogNoticesDescribeTheActualEnvironment() throws {
        for environment in AppEnvironment.allCases {
            let model = AppModel(client: APIClient(environment: environment, transport: MockTransport(data: Data())), environment: environment)
            XCTAssertEqual(model.catalogNoticeKey, environment == .mock ? "mockExplanation" : nil)
        }
        let production = try XCTUnwrap(NativeRuntimeConfiguration(info: info()).authentication)
        let staging = try NativeAuthConfiguration(environment: .staging, origin: URL(string: "https://native.example.test")!, explicitlyEnabled: true)
        for configuration in [production, staging] {
            let native = try NativeMusicAPI(configuration: configuration, explicitlyEnabled: true, transport: MockTransport(data: Data()))
            let model = AppModel(client: native, environment: configuration.environment)
            XCTAssertEqual(model.catalogNoticeKey, configuration.environment == .production ? nil : "isolatedMusic")
        }
    }
    func testProductionAuthenticationMusicGrantAndLibraryUseFixtureTransports() async throws {
        let runtime = NativeRuntimeConfiguration(info: try info()), configuration = try XCTUnwrap(runtime.authentication)
        let authTransport = AuthFixtureTransport(), api = NativeAuthAPI(configuration: configuration, transport: authTransport)
        let journal = AuthJournal(store: MemorySecureStore(), environment: .production)
        let auth = NativeAuthenticationService(configuration: configuration, api: api, journal: journal, browser: FixtureBrowser())
        try await auth.signIn()
        let saved = try await journal.read(); XCTAssertEqual(saved?.scope.environment, .production)
        let transport = ProductionContractFixture()
        let music = try NativeMusicAPI(configuration: configuration, explicitlyEnabled: runtime.musicEnabled, transport: transport, auth: auth)
        let catalog = try await music.catalog(), track = try XCTUnwrap(catalog.items.first)
        let grant = try await music.authorize(track: track, variant: "full")
        XCTAssertEqual(grant.scope, AccountScope(environment: .production, accountID: "fixture-A"))
        XCTAssertEqual(grant.grant.playbackUrl.host, "wwwstationcat.org")
        let library = try NativeLibraryAPI(configuration: configuration, explicitlyEnabled: runtime.personalSyncEnabled, auth: auth, transport: transport)
        let snapshot = try await library.snapshot(scope: grant.scope)
        XCTAssertTrue(snapshot.favorites.isEmpty); XCTAssertTrue(snapshot.preferences.historyEnabled)
        let requests = await transport.requests
        XCTAssertTrue(requests.allSatisfy { $0.url?.scheme == "https" && $0.url?.host == "wwwstationcat.org" })
        XCTAssertNil(requests.first?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(requests.dropFirst().allSatisfy { $0.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true })
        try await auth.signOut()
        let credential = try await journal.read(); XCTAssertNil(credential)
    }
}
