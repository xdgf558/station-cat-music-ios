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
    var linkUnavailable = false
    var favorites: Set<String> = []
    private(set) var scope = AccountScope.guest
    let playback: PlaybackService
    let library: ScopedLibrary
    let client: any CatalogProviding
    let account: NativeAccountModel
    let musicWebOrigin: URL?
    var detail: TrackDetail?
    var collections: [MusicCollection] = []
    private(set) var featuredTracks: [Track] = []
    private(set) var featuredPhase: Phase = .loading
    var discoveryTracks: [Track] { nativeMusic == nil ? tracks : featuredTracks }
    var discoveryPhase: Phase { nativeMusic == nil ? phase : featuredPhase }
    var activeCollection: MusicCollection?
    var nativeMusic: NativeMusicAPI? { client as? NativeMusicAPI }
    @ObservationIgnored private var detailTask: Task<Void, Never>?
    private var operation = 0
    @ObservationIgnored private var catalogTask: Task<Catalog, Error>?
    init(client: any CatalogProviding, playback: PlaybackService = PlaybackService(), library: ScopedLibrary = ScopedLibrary(), account: NativeAccountModel = NativeAccountModel(), musicWebOrigin: URL? = nil) { self.client = client; self.playback = playback; self.library = library; self.account = account; self.musicWebOrigin = MusicLink.webOrigin(musicWebOrigin)
        if let native = client as? NativeMusicAPI { playback.configure(authorizer: native) }
        playback.onSelection = { [weak self] track in self?.loadDetail(track) }
        account.onInvalidate = { [weak playback] in playback?.clear() }
    }
    func t(_ key: String) -> String { L10n.text(key, locale: locale) }
    func load() async {
        operation += 1; let id = operation; let startedScope = scope
        phase = .loading; featuredPhase = .loading; featuredTracks = []; collections = []; catalogTask?.cancel()
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
            if let nativeMusic {
                do {
                    let featured = try await nativeMusic.featured()
                    guard id == operation, startedScope == scope, !Task.isCancelled else { return }
                    featuredTracks = featured.tracks; collections = featured.collections
                    featuredPhase = featuredTracks.isEmpty ? .empty : .loaded
                } catch {
                    guard id == operation, startedScope == scope, !Task.isCancelled else { return }
                    featuredPhase = .unavailable
                }
            }
        } catch {
            guard id == operation, startedScope == scope, !Task.isCancelled else { return }
            phase = .unavailable; featuredPhase = .unavailable
        }
    }
    var results: [Track] {
        query.isEmpty ? (activeCollection?.tracks ?? tracks) : (activeCollection?.tracks ?? tracks).filter { ($0.title + " " + $0.artist).localizedCaseInsensitiveContains(query) }
    }
    func changeScope(_ scope: AccountScope) async {
        operation += 1; catalogTask?.cancel(); detailTask?.cancel(); detail = nil; collections = []; featuredTracks = []; featuredPhase = .loading; activeCollection = nil; playback.clear(); tracks = []; favorites = []; self.scope = scope
        let value = await library.favorites(in: scope)
        guard self.scope == scope else { return }; favorites = value
    }
    func toggleFavorite(_ track: Track) async {
        let scope = self.scope; let value = !favorites.contains(track.id)
        await library.setFavorite(track.id, value: value, scope: scope)
        let updated = await library.favorites(in: scope)
        guard self.scope == scope else { return }; favorites = updated
    }
    func select(_ track: Track, from list: [Track]? = nil) {
        let list = list ?? results
        if let index = list.firstIndex(of: track) { playback.setQueue(list, startingAt: index, play: false) }
        else { playback.select(track) }
        showPlayer = true
    }
    private func loadDetail(_ track: Track?) {
        detail = nil; detailTask?.cancel()
        guard let track, let nativeMusic else { return }
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
    private func musicURL(name: String, value: String) -> URL? {
        guard nativeMusic != nil, let musicWebOrigin else { return nil }
        var components = URLComponents(url: musicWebOrigin.appending(path: "music/"), resolvingAgainstBaseURL: false)
        components?.queryItems = [.init(name: name, value: value)]; return components?.url
    }
    var trackShareURL: URL? {
        guard let track = playback.selectedTrack, UUID(uuidString: track.id) != nil else { return nil }
        return musicURL(name: "track", value: track.id)
    }
    var collectionShareURL: URL? {
        guard let collection = activeCollection else { return nil }
        return musicURL(name: "collection", value: collection.slug)
    }
    func openMusicLink(_ url: URL) async {
        guard let nativeMusic, let host = musicWebOrigin?.host, let link = MusicLink(url, allowedHost: host) else { return }
        operation += 1; let ticket = operation; let startedScope = scope
        catalogTask?.cancel(); detailTask?.cancel(); linkUnavailable = false
        do {
            switch link {
            case .track(let id):
                let result = try await nativeMusic.resolveTrack(id)
                guard ticket == operation, scope == startedScope, !Task.isCancelled else { return }
                playback.select(result.track); detailTask?.cancel(); detail = result; showPlayer = true
            case .collection(let slug):
                let result = try await nativeMusic.resolveCollection(slug)
                guard ticket == operation, scope == startedScope, !Task.isCancelled else { return }
                activeCollection = result; query = ""; selectedTab = 1; phase = result.tracks.isEmpty ? .empty : .loaded
            }
        } catch { if ticket == operation && scope == startedScope && !Task.isCancelled { linkUnavailable = true } }
    }
    func adjacent(_ offset: Int) { if offset < 0 { playback.previous() } else { playback.next() } }

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
