import SwiftUI

@main struct StationCatMusicApp: App {
    @State private var model: AppModel
    init() {
        let configured = Bundle.main.object(forInfoDictionaryKey: "StationEnvironment") as? String ?? "production"
        let environment = AppEnvironment(rawValue: configured) ?? .production
        let data = Bundle.main.url(forResource: "catalog", withExtension: "json").flatMap { try? Data(contentsOf: $0) } ?? Data()
        let transport = MockTransport(data: data)
        _model = State(initialValue: AppModel(client: APIClient(environment: environment, transport: transport), account: NativeAccountModel.configured(environment: environment)))
    }
    var body: some Scene { WindowGroup { RootView(model: model).preferredColorScheme(.dark) } }
}
