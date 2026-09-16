import SwiftUI
import Observation

@MainActor @Observable final class AppModel {
    enum Phase: Equatable { case loading, loaded, empty, unavailable }
    var phase: Phase = .loading
    var tracks: [Track] = []
    var query = ""
    var locale: String = L10n.resolve(Locale.preferredLanguages.first ?? "en")
    var selectedTab = 0
    var showPlayer = false
    var favorites: Set<String> = []
    private(set) var scope = AccountScope.guest
    let playback: PlaybackService
    let library: ScopedLibrary
    let client: APIClient
    private var operation = 0
    @ObservationIgnored private var catalogTask: Task<Catalog, Error>?
    init(client: APIClient, playback: PlaybackService = PlaybackService(), library: ScopedLibrary = ScopedLibrary()) { self.client = client; self.playback = playback; self.library = library }
    func t(_ key: String) -> String { L10n.text(key, locale: locale) }
    func load() async {
        operation += 1; let id = operation; let startedScope = scope
        phase = .loading; catalogTask?.cancel()
        let client = self.client
        let work = Task { try await client.catalog() }; catalogTask = work
        do {
            let catalog = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
            guard id == operation, startedScope == scope, !Task.isCancelled else { return }
            tracks = catalog.items; phase = tracks.isEmpty ? .empty : .loaded
        } catch {
            guard id == operation, startedScope == scope, !Task.isCancelled else { return }
            phase = .unavailable
        }
    }
    var results: [Track] {
        query.isEmpty ? tracks : tracks.filter { ($0.title + " " + $0.artist).localizedCaseInsensitiveContains(query) }
    }
    func changeScope(_ scope: AccountScope) async {
        operation += 1; catalogTask?.cancel(); playback.deny(); tracks = []; favorites = []; self.scope = scope
        let value = await library.favorites(in: scope)
        guard self.scope == scope else { return }; favorites = value
    }
    func toggleFavorite(_ track: Track) async {
        let scope = self.scope; let value = !favorites.contains(track.id)
        await library.setFavorite(track.id, value: value, scope: scope)
        let updated = await library.favorites(in: scope)
        guard self.scope == scope else { return }; favorites = updated
    }
    func select(_ track: Track) { playback.select(track); showPlayer = true }
}
nonisolated enum L10n {
    static func resolve(_ value: String) -> String {
        if value.hasPrefix("zh-Hant") || value.hasPrefix("zh-TW") || value.hasPrefix("zh-HK") { return "zh-Hant" }
        if value.hasPrefix("zh") { return "zh-Hans" }
        if value.hasPrefix("ja") { return "ja" }
        return "en"
    }
    static let all: [String: [String: String]] = {
        guard let url = Bundle.main.url(forResource: "Localizations", withExtension: "json"),
              let data = try? Data(contentsOf: url), let values = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return [:] }
        return values
    }()
    static func text(_ key: String, locale: String) -> String { all[locale]?[key] ?? all["en"]?[key] ?? key }
}
