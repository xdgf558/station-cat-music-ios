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
    let client: any CatalogProviding
    let account: NativeAccountModel
    var detail: TrackDetail?
    var collections: [MusicCollection] = []
    var activeCollection: MusicCollection?
    var nativeMusic: NativeMusicAPI? { client as? NativeMusicAPI }
    @ObservationIgnored private var detailTask: Task<Void, Never>?
    private var operation = 0
    @ObservationIgnored private var catalogTask: Task<Catalog, Error>?
    init(client: any CatalogProviding, playback: PlaybackService = PlaybackService(), library: ScopedLibrary = ScopedLibrary(), account: NativeAccountModel = NativeAccountModel()) { self.client = client; self.playback = playback; self.library = library; self.account = account
        if let native = client as? NativeMusicAPI { playback.configure(authorizer: native) }
        account.onInvalidate = { [weak playback] in playback?.deny() }
    }
    func t(_ key: String) -> String { L10n.text(key, locale: locale) }
    func load() async {
        operation += 1; let id = operation; let startedScope = scope
        phase = .loading; catalogTask?.cancel()
        let client = self.client
        let locale = locale
        let work = Task { if let native = client as? NativeMusicAPI { await native.setLocale(locale) }; return try await client.catalog() }; catalogTask = work
        do {
            let catalog = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
            guard id == operation, startedScope == scope, !Task.isCancelled else { return }
            tracks = catalog.items; phase = tracks.isEmpty ? .empty : .loaded
            if let selected = activeCollection {
                let current = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
                activeCollection = MusicCollection(id: selected.id, slug: selected.slug, title: selected.title, description: selected.description,
                    version: selected.version, tracks: selected.tracks.compactMap { current[$0.id] }, nextCursor: nil)
            }
            if let nativeMusic, let featured = try? await nativeMusic.featured(), id == operation, startedScope == scope { collections = featured.collections }
        } catch {
            guard id == operation, startedScope == scope, !Task.isCancelled else { return }
            phase = .unavailable
        }
    }
    var results: [Track] {
        query.isEmpty ? (activeCollection?.tracks ?? tracks) : (activeCollection?.tracks ?? tracks).filter { ($0.title + " " + $0.artist).localizedCaseInsensitiveContains(query) }
    }
    func changeScope(_ scope: AccountScope) async {
        operation += 1; catalogTask?.cancel(); detailTask?.cancel(); detail = nil; collections = []; activeCollection = nil; playback.deny(); tracks = []; favorites = []; self.scope = scope
        let value = await library.favorites(in: scope)
        guard self.scope == scope else { return }; favorites = value
    }
    func toggleFavorite(_ track: Track) async {
        let scope = self.scope; let value = !favorites.contains(track.id)
        await library.setFavorite(track.id, value: value, scope: scope)
        let updated = await library.favorites(in: scope)
        guard self.scope == scope else { return }; favorites = updated
    }
    func select(_ track: Track) {
        playback.select(track); showPlayer = true; detail = nil; detailTask?.cancel()
        guard let nativeMusic else { return }
        let version = operation, locale = locale
        detailTask = Task { [weak self] in
            let value = try? await nativeMusic.detail(track, locale: locale)
            guard let self, !Task.isCancelled, self.operation == version, self.playback.selectedTrack == track else { return }
            self.detail = value
        }
    }
    func selectCollection(_ collection: MusicCollection) async {
        guard let nativeMusic else { return }; operation += 1; let ticket = operation
        phase = .loading
        do {
            let result = try await nativeMusic.collection(collection)
            guard operation == ticket else { return }; activeCollection = result; phase = .loaded
        } catch { if operation == ticket { phase = .unavailable } }
    }
    func adjacent(_ offset: Int) {
        guard let selected = playback.selectedTrack, let index = results.firstIndex(where: { $0.id == selected.id }), results.indices.contains(index + offset) else { return }
        select(results[index + offset])
    }
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
