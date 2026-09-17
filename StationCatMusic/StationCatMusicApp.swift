import SwiftUI

@main struct StationCatMusicApp: App {
    @State private var model: AppModel
    init() {
        let configured = Bundle.main.object(forInfoDictionaryKey: "StationEnvironment") as? String ?? "production"
        let environment = AppEnvironment(rawValue: configured) ?? .production
        let data = Bundle.main.url(forResource: "catalog", withExtension: "json").flatMap { try? Data(contentsOf: $0) } ?? Data()
        let transport = MockTransport(data: data)
        let account = NativeAccountModel.configured(environment: environment)
        var client: any CatalogProviding = APIClient(environment: environment, transport: transport)
        if Bundle.main.object(forInfoDictionaryKey: "StationNativeMusicEnabled") as? String == "YES",
           let raw = Bundle.main.object(forInfoDictionaryKey: "StationNativeAuthOrigin") as? String,
           let origin = URL(string: raw),
           let configuration = try? NativeAuthConfiguration(environment: environment, origin: origin, explicitlyEnabled: account.enabled),
           let native = try? NativeMusicAPI(configuration: configuration, explicitlyEnabled: true, transport: URLSessionTransport(), auth: account.auth) { client = native }
        _model = State(initialValue: AppModel(client: client, account: account))
    }
    var body: some Scene { WindowGroup { RootView(model: model).preferredColorScheme(.dark) } }
}
