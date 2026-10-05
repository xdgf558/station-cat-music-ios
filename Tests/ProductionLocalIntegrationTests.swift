import XCTest
@testable import StationCatMusic

@MainActor final class ProductionLocalIntegrationTests: XCTestCase {
    func testBridgeRejectsExternalAndAliasedOriginsBeforeLoopback() async throws {
        let bridge = try ProductionLocalBridge(port: 49152, key: String(repeating: "K", count: 43))
        for value in ["http://wwwstationcat.org/api/mobile/v1/config", "https://stationcat.org/api/mobile/v1/config",
            "https://wwwstationcat.org./api/mobile/v1/config", "https://WWWSTATIONCAT.ORG/api/mobile/v1/config",
            "https://wwwstationcat.org:443/api/mobile/v1/config", "https://wwwstationcat.org.example.test/api/mobile/v1/config",
            "https://user@wwwstationcat.org/api/mobile/v1/config", "https://wwwstationcat.org/api/mobile/v1/config#fragment",
            "http://127.0.0.1:49152/request"] {
            do { _ = try await bridge.send(URLRequest(url: URL(string: value)!)); XCTFail("Origin escaped the test boundary") }
            catch ProductionLocalFixture.Failure.boundary { }
        }
        let dispatched = await bridge.dispatched
        XCTAssertEqual(dispatched, 0)
        XCTAssertThrowsError(try ProductionLocalBridge(port: 80, key: String(repeating: "K", count: 43)))
        XCTAssertThrowsError(try ProductionLocalBridge(port: 49152, key: "invalid"))
        XCTAssertEqual(ProductionLocalFixture.category(ProductionLocalFixture.Failure.input), "fixture_input")
        XCTAssertEqual(ProductionLocalFixture.category(ProductionLocalFixture.Failure.boundary), "fixture_boundary")
        XCTAssertEqual(ProductionLocalFixture.category(ProductionLocalFixture.Failure.response), "fixture_response")
        XCTAssertEqual(ProductionLocalFixture.category(ProductionLocalFixture.Failure.assertion), "fixture_assertion")
    }

    func testProductionProfileWithRealLocalWorkerAuthenticationMusicAndLibrary() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["PRODUCTION_ENABLE_LOCAL_E2E"] == "YES" else { throw XCTSkip("Requires the pinned local production fixture driver") }
        var stage = "bridge_input"
        var sessions: [NativeAuthenticationService] = []
        var succeeded = false
        do {
            guard let port = Int(env["PRODUCTION_PROBE_PORT"] ?? ""), let key = env["PRODUCTION_PROBE_KEY"] else {
                throw ProductionLocalFixture.Failure.input
            }
            let bridge = try ProductionLocalBridge(port: port, key: key)
            let input = try await bridge.bootstrap(), config = try ProductionLocalFixture.configuration()
            let transport = ProductionLocalAPITransport(bridge: bridge)
            func signIn(_ identity: ProductionLocalFixture.Identity) async throws -> NativeAuthenticationService {
                let service = NativeAuthenticationService(configuration: config,
                    api: NativeAuthAPI(configuration: config, transport: transport),
                    journal: AuthJournal(store: MemorySecureStore(), environment: .production),
                    browser: ProductionLocalFormBrowser(bridge: bridge, identity: identity))
                sessions.append(service)
                try await service.signIn(locale: "en")
                return service
            }
            stage = "capability_request"
            let capabilityResponse = try await bridge.send(URLRequest(url: ProductionLocalFixture.origin.appending(path: "api/mobile/v1/config")))
            stage = "capability_decode"
            struct Capabilities: Decodable, Sendable {
                struct Flags: Decodable, Sendable { let nativeAuthentication: Bool; let musicCatalog: Bool; let musicPlayback: Bool; let personalSync: Bool; let accountDeletion: Bool }
                let capabilities: Flags
            }
            let capabilities = try NativeJSON.decoder().decode(NativeResponse<Capabilities>.self, from: capabilityResponse.data).data.capabilities
            stage = "capability_assert"
            // Fixed scalar allowlist only: never print the response, headers, URLs or credentials.
            print("PRODUCTION_CAPABILITIES_OBSERVED: status=\(capabilityResponse.status) nativeAuthentication=\(capabilities.nativeAuthentication) musicCatalog=\(capabilities.musicCatalog) musicPlayback=\(capabilities.musicPlayback) personalSync=\(capabilities.personalSync) accountDeletion=\(capabilities.accountDeletion) localAccountDeletionAllowed=\(config.accountDeletionAllowed)")
            try ProductionLocalFixture.require(capabilityResponse.status == 200 && capabilities.nativeAuthentication && capabilities.musicCatalog &&
                capabilities.musicPlayback && capabilities.personalSync && !capabilities.accountDeletion && !config.accountDeletionAllowed)
            stage = "real_form_pkce_login"
            let auth = try await signIn(input.account), peerAuth = try await signIn(input.account), vipAuth = try await signIn(input.vipAccount)
            guard case let .authenticated(scope) = await auth.state(),
                  case let .authenticated(peerScope) = await peerAuth.state(),
                  case let .authenticated(vipScope) = await vipAuth.state() else { throw ProductionLocalFixture.Failure.assertion }
            try ProductionLocalFixture.require(scope.environment == .production && scope.accountID == input.account.id &&
                scope == peerScope && vipScope.accountID == input.vipAccount.id && scope != vipScope)
            stage = "real_refresh"
            let oldBearer = try await auth.accessToken(forceRefresh: false)
            let refreshed = try await auth.accessToken(forceRefresh: true)
            try ProductionLocalFixture.require(oldBearer != refreshed)
            let music = try NativeMusicAPI(configuration: config, explicitlyEnabled: true, transport: transport, auth: auth)
            let vipMusic = try NativeMusicAPI(configuration: config, explicitlyEnabled: true, transport: transport, auth: vipAuth)
            let guestMusic = try NativeMusicAPI(configuration: config, explicitlyEnabled: true, transport: transport)
            stage = "catalog"
            let catalog = try await music.catalog()
            guard let free = catalog.items.first(where: { $0.id == input.tracks.freeTrackId }),
                  let vip = catalog.items.first(where: { $0.id == input.tracks.vipTrackId }) else { throw ProductionLocalFixture.Failure.assertion }
            stage = "track_detail_lyrics"
            let detail = try await music.detail(free, locale: "en")
            stage = "album"
            let album = try await music.resolveCollection(input.collectionSlug)
            try ProductionLocalFixture.require(detail.lyrics.audioVersion == free.audioVersion &&
                Set(album.tracks.map(\.id)) == [free.id, vip.id])
            stage = "account_entitlement_variants"
            let normalVariant = try await music.preferredVariant(for: vip), vipVariant = try await vipMusic.preferredVariant(for: vip)
            try ProductionLocalFixture.require(normalVariant == "preview" && vipVariant == "full")
            stage = "guest_free_grant"
            let guestGrant = try await guestMusic.authorize(track: free, variant: "full")
            try ProductionLocalFixture.require(guestGrant.context == nil && guestGrant.grant.variant == "full")
            stage = "normal_vip_denial"
            var denied = false
            do { _ = try await music.authorize(track: vip, variant: "full") }
            catch APIError.rejected(let status) { denied = status == 403 }
            try ProductionLocalFixture.require(denied)
            stage = "normal_vip_preview_grant"
            let preview = try await music.authorize(track: vip, variant: "preview")
            stage = "vip_full_grant"
            let vipGrant = try await vipMusic.authorize(track: vip, variant: "full")
            stage = "normal_free_grant"
            let freeGrant = try await music.authorize(track: free, variant: "full")
            try ProductionLocalFixture.require(preview.grant.variant == "preview" && vipGrant.scope == vipScope &&
                vipGrant.grant.variant == "full" && freeGrant.scope == scope)
            stage = "four_grant_head_and_range"
            for (grant, authorizer) in [(guestGrant, guestMusic), (preview, music), (vipGrant, vipMusic), (freeGrant, music)] {
                let channel = AuthorizedMediaChannel(authorization: grant, authorizer: authorizer,
                    transport: ProductionLocalMediaTransport(bridge: bridge), lifetime: 60)
                let metadata = try await channel.metadata()
                let bytes = try await channel.read(start: 0, length: 256, total: metadata.size)
                try ProductionLocalFixture.require(metadata.size > 256 && bytes.count == 256 && !metadata.etag.isEmpty)
            }
            stage = "two_session_library_and_account_isolation"
            let remote = try NativeLibraryAPI(configuration: config, explicitlyEnabled: true, auth: auth, transport: transport)
            let peer = try NativeLibraryAPI(configuration: config, explicitlyEnabled: true, auth: peerAuth, transport: transport)
            let other = try NativeLibraryAPI(configuration: config, explicitlyEnabled: true, auth: vipAuth, transport: transport)
            let local = ScopedLibrary(), replica = ScopedLibrary()
            let otherInitial = try await other.snapshot(scope: vipScope)
            try await local.synchronize(scope: scope, remote: remote)
            try await local.setHistory(true, scope: scope)
            try await local.setFavorite(free.id, value: true, scope: scope)
            // Synthetic listen telemetry tests synchronization only; no AVPlayer/audio-duration claim.
            try await local.record(free, variant: "full", audible: 5.5, position: 0.3, eventID: UUID().uuidString, scope: scope)
            try await local.synchronize(scope: scope, remote: remote)
            try await replica.synchronize(scope: scope, remote: peer)
            let view = try await replica.view(in: scope), otherAfter = try await other.snapshot(scope: vipScope)
            try ProductionLocalFixture.require(view.pending == 0 && view.favorites.contains(free.id) && view.recent.first?.trackId == free.id &&
                otherInitial.favorites == otherAfter.favorites && otherInitial.recent == otherAfter.recent && otherInitial.preferences == otherAfter.preferences)
            stage = "production_deletion_closed_before_transport_and_on_worker"
            let deletionAPI = NativeAuthAPI(configuration: config, transport: transport)
            let beforeDeletion = await bridge.dispatched
            for path in ["/auth/reauth", "/me/deletion-requests/prepare", "/me/deletion-requests/abcdefghijklmnop/confirm"] {
                do { let _ = try await deletionAPI.request(path, as: NativeAcknowledged.self); throw ProductionLocalFixture.Failure.assertion }
                catch APIError.networkDisabled { }
            }
            let afterDeletion = await bridge.dispatched
            try ProductionLocalFixture.require(beforeDeletion == afterDeletion)
            for path in ["me/deletion-requests/prepare", "me/deletion-requests/abcdefghijklmnop/confirm"] {
                var request = URLRequest(url: ProductionLocalFixture.origin.appending(path: "api/mobile/v1/" + path))
                request.httpMethod = "POST"; request.setValue("Bearer " + refreshed, forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = Data("{}".utf8)
                let response = try await bridge.send(request)
                let error = try JSONDecoder().decode(NativeErrorEnvelope.self, from: response.data)
                try ProductionLocalFixture.require(response.status == 503 && error.error.code == "SERVICE_UNAVAILABLE")
            }
            stage = "logout_revokes_session_and_grant"
            try await auth.signOut()
            let state = await auth.state(), current = await music.isCurrent(freeGrant)
            try ProductionLocalFixture.require(state == .guest && !current)
            let vipBearer = try await vipAuth.accessToken(forceRefresh: false)
            try await vipAuth.signOut()
            let vipCurrent = await vipMusic.isCurrent(vipGrant)
            try ProductionLocalFixture.require(!vipCurrent && vipGrant.grant.authMode == .sessionBearer)
            var stale = URLRequest(url: vipGrant.grant.playbackUrl); stale.httpMethod = "HEAD"
            stale.setValue("Bearer " + vipBearer, forHTTPHeaderField: "Authorization")
            let revoked = try await bridge.send(stale)
            try ProductionLocalFixture.require([401, 403].contains(revoked.status))
            let peerStillActive = try await peer.snapshot(scope: peerScope)
            try ProductionLocalFixture.require(peerStillActive.favorites.contains { $0.trackId == free.id && $0.favorite })
            succeeded = true
        } catch { XCTFail("PRODUCTION_NATIVE_LOCAL_FAILED stage=\(stage) category=\(ProductionLocalFixture.category(error))") }
        for session in sessions {
            do { try await session.signOut() }
            catch { succeeded = false; XCTFail("PRODUCTION_NATIVE_LOCAL_FAILED stage=cleanup category=\(ProductionLocalFixture.category(error))") }
        }
        if succeeded {
            print("PRODUCTION_NATIVE_LOCAL_E2E_PASSED: real_main_worker=true real_password_pkce=true refresh=true catalog=true free_vip_boundary=true audio_head_range=true library_two_sessions=true account_isolation=true logout_revocation=true deletion_closed=true production_network=false os_association=false")
        }
    }
}
