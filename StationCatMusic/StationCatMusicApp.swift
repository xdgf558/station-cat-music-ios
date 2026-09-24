import SwiftUI

@main struct StationCatMusicApp: App {
    @State private var model: AppModel
    init() {
        let configured = Bundle.main.object(forInfoDictionaryKey: "StationEnvironment") as? String ?? "production"
        let environment = AppEnvironment(rawValue: configured) ?? .production
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
        let account = NativeAccountModel.configured(environment: environment)
        var client: any CatalogProviding = APIClient(environment: environment, transport: transport)
        if Bundle.main.object(forInfoDictionaryKey: "StationNativeMusicEnabled") as? String == "YES",
           let raw = Bundle.main.object(forInfoDictionaryKey: "StationNativeAuthOrigin") as? String,
           let origin = URL(string: raw),
           let configuration = try? NativeAuthConfiguration(environment: environment, origin: origin, explicitlyEnabled: account.enabled),
           let native = try? NativeMusicAPI(configuration: configuration, explicitlyEnabled: true, transport: URLSessionTransport(), auth: account.auth) { client = native }
        let webOrigin = (Bundle.main.object(forInfoDictionaryKey: "StationMusicWebOrigin") as? String).flatMap(URL.init(string:))
        let directory = URL.applicationSupportDirectory.appending(path: "PersonalMusic")
        var libraryRemote: NativeLibraryAPI?
        if Bundle.main.object(forInfoDictionaryKey: "StationPersonalSyncEnabled") as? String == "YES", let native = client as? NativeMusicAPI, let auth = account.auth {
            libraryRemote = try? NativeLibraryAPI(configuration: native.configuration, explicitlyEnabled: true, auth: auth, transport: URLSessionTransport())
        }
        let artwork = ArtworkLoader(cacheDirectory: URL.cachesDirectory.appending(path: "PublicMusicArtwork-v1"))
        let model = AppModel(client: client, library: ScopedLibrary(directory: directory), account: account, musicWebOrigin: webOrigin, libraryRemote: libraryRemote, environment: environment, artwork: artwork)
        if let native = client as? NativeMusicAPI, let host = native.configuration.origin.host {
            model.playback.attachSystem(SystemPlayback(playback: model.playback, artworkHost: host, artworkLoader: artwork))
        }
        _model = State(initialValue: model)
    }
    var body: some Scene { WindowGroup { RootView(model: model).preferredColorScheme(.dark) } }
}
