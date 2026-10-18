import SwiftUI

@main struct StationCatMusicApp: App {
    @State private var model: AppModel
    private var discardPlatformOpen = false
    init() {
        let runtime = NativeRuntimeConfiguration(info: Bundle.main.infoDictionary ?? [:])
        let publicConfiguration = PlatformConfiguration(info: Bundle.main.infoDictionary ?? [:])
        let environment = runtime.environment
        var legacyPreview = false
        #if DEBUG && targetEnvironment(simulator)
        legacyPreview = environment == .mock && ProcessInfo.processInfo.arguments.contains("--legacy-player-fixture")
        discardPlatformOpen = environment == .mock && ProcessInfo.processInfo.arguments.contains("--platform-music-fixture") && ProcessInfo.processInfo.environment["STATION_PLATFORM_OPEN_FAIL"] == "1"
        #endif
        let platformMode = !legacyPreview
        let data = Bundle.main.url(forResource: "catalog", withExtension: "json").flatMap { try? Data(contentsOf: $0) } ?? Data()
        var previewDelay: Duration = .zero
        var previewStatus = 200
        #if DEBUG && targetEnvironment(simulator)
        // Screenshot/error-path fixtures affect Mock only, never a native host.
        if environment == .mock {
            let preview = ProcessInfo.processInfo.environment["STATION_STARTUP_PREVIEW"]
            if preview == "slow" { previewDelay = .seconds(5) }
            if preview == "failure" { previewStatus = 503 }
        }
        #endif
        let transport = MockTransport(data: data, delay: previewDelay, status: previewStatus)
        let account = platformMode ? NativeAccountModel(environment: environment) : NativeAccountModel.configured(runtime: runtime)
        var client: any CatalogProviding = APIClient(environment: environment, transport: transport)
        if !platformMode, runtime.musicEnabled, let configuration = runtime.authentication, account.enabled,
           let native = try? NativeMusicAPI(configuration: configuration, explicitlyEnabled: true, transport: URLSessionTransport(), auth: account.auth) { client = native }
        if platformMode, environment == .mock {
            var fixtureName = "platform-catalog"
            var detailFailure = false
            #if DEBUG && targetEnvironment(simulator)
            detailFailure = ProcessInfo.processInfo.environment["STATION_PLATFORM_FIXTURE"] == "detail-failure"
            if ProcessInfo.processInfo.environment["STATION_PLATFORM_FIXTURE"] == "catalog-categories" { fixtureName = "platform-albums" }
            #endif
            let platformData = Bundle.main.url(forResource: fixtureName, withExtension: "json").flatMap { try? Data(contentsOf: $0) } ?? Data()
            let fixture = PlatformFixtureTransport(data: platformData, delay: previewDelay, status: previewStatus, detailFailure: detailFailure)
            if let platform = try? PlatformMusicAPI(explicitlyEnabled: true, transport: fixture) { client = platform }
        } else if platformMode, let origin = publicConfiguration.origin,
                  let platform = try? PlatformMusicAPI(origin: origin, explicitlyEnabled: true, transport: URLSessionTransport()) { client = platform }
        let webOrigin = platformMode ? (client as? any PlatformMusicProviding)?.webOrigin : runtime.musicWebOrigin
        let directory = URL.applicationSupportDirectory.appending(path: "PersonalMusic")
        var libraryRemote: NativeLibraryAPI?
        if !platformMode, runtime.personalSyncEnabled, let native = client as? NativeMusicAPI, let auth = account.auth {
            libraryRemote = try? NativeLibraryAPI(configuration: native.configuration, explicitlyEnabled: true, auth: auth, transport: URLSessionTransport())
        }
        let artwork = ArtworkLoader(cacheDirectory: URL.cachesDirectory.appending(path: "PublicMusicArtwork-v1"))
        // A configured old cache can be managed, but the platform catalog never
        // reconciles it, authorizes it or installs it in the player.
        let existingOffline = platformMode ? publicConfiguration.legacyOfflineOrigin.map {
            OfflineMusicCache(origin: $0, transport: LegacyOfflineManagementTransport())
        } : nil
        let model = AppModel(client: client, library: ScopedLibrary(directory: directory), account: account, musicWebOrigin: webOrigin, libraryRemote: libraryRemote, environment: environment, artwork: artwork, offlineStorage: existingOffline, platformMode: platformMode, bookmarks: PlatformBookmarkStore(directory: URL.cachesDirectory.resolvingSymlinksInPath().appending(path: "PublicMusicBookmarks-v1")))
        if !platformMode, let native = client as? NativeMusicAPI, let host = native.configuration.origin.host {
            model.playback.attachSystem(SystemPlayback(playback: model.playback, artworkHost: host, artworkLoader: artwork))
        }
        _model = State(initialValue: model)
    }
    var body: some Scene {
        WindowGroup {
            if discardPlatformOpen {
                RootView(model: model).preferredColorScheme(.dark)
                    .environment(\.openURL, OpenURLAction { _ in .discarded })
            } else { RootView(model: model).preferredColorScheme(.dark) }
        }
    }
}
