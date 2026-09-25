import SwiftUI
import Observation

@MainActor @Observable final class AppModel {
    enum Phase: Equatable { case loading, loaded, empty, unavailable }
    enum StartupPhase: Equatable { case loading, ready, unavailable }
    private(set) var startupPhase: StartupPhase = .loading
    private(set) var catalogFailure: CatalogFailure?
    private(set) var featuredFailure: CatalogFailure?
    var startupFailureKey: String {
        if let catalogFailure { return catalogFailure.messageKey }
        if let featuredFailure { return featuredFailure.messageKey }
        return "startupFailure"
    }
    var phase: Phase = .loading
    var tracks: [Track] = []
    var query = ""
    var locale: String = L10n.resolve(Locale.preferredLanguages.first ?? "en")
    var selectedTab = 0
    var showPlayer = false
    var linkUnavailable = false
    var favorites: Set<String> = []
    var recent: [LibraryRecent] = []
    var historyEnabled = true
    var libraryStatus = "libraryLocal"
    var libraryBusy = false
    var localCleanupStatus = ""
    let libraryRemote: (any LibraryRemote)?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    private var libraryGeneration = 0
    private var scopeTransition = false
    private(set) var scope = AccountScope.guest
    let playback: PlaybackService
    let library: ScopedLibrary
    var autoCacheFreeSongs = false
    private var offlinePreferenceKey = ""
    var offlineSongs: [OfflineSong] = []
    var offlineBytes = 0
    var offlineDownloading: String?
    var offlineStatus = ""
    let offlineCache: OfflineMusicCache?
    @ObservationIgnored private var offlineTask: Task<Void, Never>?
    @ObservationIgnored private var offlineTicket: OfflineDownloadTicket?
    let artwork: ArtworkLoader
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
    @ObservationIgnored private var initializationTask: Task<Void, Never>?
    @ObservationIgnored private var pendingMusicLink: URL?
    @ObservationIgnored private var initializationReloadRequested = false
    private var initialized = false
    private var operation = 0
    @ObservationIgnored private var catalogTask: Task<Void, Never>?
    init(client: any CatalogProviding, playback: PlaybackService = PlaybackService(), library: ScopedLibrary = ScopedLibrary(), account: NativeAccountModel = NativeAccountModel(), musicWebOrigin: URL? = nil, libraryRemote: (any LibraryRemote)? = nil, environment: AppEnvironment = .mock, artwork: ArtworkLoader = ArtworkLoader(), offlineStorage: OfflineMusicCache? = nil) { self.artwork = artwork; self.libraryRemote = libraryRemote; self.scope = AccountScope(environment: environment, accountID: nil); self.client = client; self.playback = playback; self.library = library; self.account = account; self.musicWebOrigin = MusicLink.webOrigin(musicWebOrigin)
        if let native = client as? NativeMusicAPI {
            let cache = offlineStorage ?? OfflineMusicCache(origin: native.configuration.origin)
            offlineCache = cache; playback.offlineCache = cache; playback.configure(authorizer: native)
            offlinePreferenceKey = "autoCacheFreeSongs." + native.configuration.origin.absoluteString
            autoCacheFreeSongs = UserDefaults.standard.bool(forKey: offlinePreferenceKey)
        } else { offlineCache = offlineStorage; playback.offlineCache = offlineStorage }
        playback.onSelection = { [weak self] track in self?.loadDetail(track) }
        account.onInvalidate = { [weak self] in
            guard let self else { return }
            self.libraryGeneration += 1; self.syncTask?.cancel(); self.libraryBusy = false; self.scopeTransition = false
            self.favorites = []; self.recent = []; self.playback.clear()
        }
        playback.onListen = { [weak self] track, variant, audible, position, eventID in
            guard let self else { return }; let scope = self.scope, generation = self.libraryGeneration
            if self.autoCacheFreeSongs, variant == "full", track.offlineEligible == true,
               !self.playback.isOfflinePlayback, !self.offlineSongs.contains(where: { $0.id == track.id }) { self.saveOffline(track) }
            Task { [weak self] in
                guard let self, self.libraryGeneration == generation else { return }
                do { try await self.library.record(track, variant: variant, audible: audible, position: position, eventID: eventID, scope: scope); await self.refreshLibrary(); self.syncLibrary() }
                catch { self.libraryStatus = "libraryError" }
            }
        }
    }
    func t(_ key: String) -> String { L10n.text(key, locale: locale) }
    func initialize() async {
        if let initializationTask { await initializationTask.value; return }
        let work = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refreshLibrary()
            await self.refreshOffline()
            // Restore can finish as guest/unavailable. In either case the public
            // catalog remains usable; a failed restore must not strand a link.
            await self.account.restore()
            while true {
                self.initializationReloadRequested = false
                let requestedLocale = self.locale
                let requested = self.account.scope
                if self.scope.accountID != requested.accountID { await self.changeScope(requested) }
                await self.loadCatalog()
                // A user account change during loading invalidates that result.
                // Locale/reload requests are coalesced here, rather than cancelling
                // this load and releasing the URL while a replacement is unfinished.
                if self.scope.accountID == self.account.scope.accountID && requestedLocale == self.locale && !self.initializationReloadRequested { break }
            }
            self.initialized = true
            if let url = self.pendingMusicLink {
                self.pendingMusicLink = nil
                await self.openMusicLink(url)
            }
            self.finishStartup()
        }
        initializationTask = work
        await work.value
    }
    private func finishStartup() {
        // A successful empty response is ready too. A failed secondary section
        // must not block a usable app, or a resolved cold-launch music link.
        startupPhase = phase == .loaded || phase == .empty || featuredPhase == .loaded || featuredPhase == .empty || showPlayer || activeCollection != nil ? .ready : .unavailable
    }
    func retryStartup() async {
        guard startupPhase == .unavailable else { return }
        startupPhase = .loading
        initialized = false; initializationTask = nil
        await initialize()
    }
    func continueAfterStartupFailure() {
        guard startupPhase == .unavailable else { return }
        startupPhase = .ready
    }
    func receiveMusicLink(_ url: URL) async {
        guard nativeMusic != nil, let host = musicWebOrigin?.host, MusicLink(url, allowedHost: host) != nil else { return }
        guard initialized else {
            // OS cold-launch delivery can precede the root view's task. Keep only
            // the latest valid navigation intent; malformed URLs cannot replace it.
            pendingMusicLink = url
            return
        }
        await openMusicLink(url)
        if startupPhase == .unavailable { finishStartup() }
    }
    func accountScopeChanged(_ requested: AccountScope) async {
        // Initialization owns restoration. Its delayed SwiftUI onChange callback
        // must not clear a link that was opened after that scope was reconciled.
        guard initialized, requested == account.scope, scope.accountID != requested.accountID else { return }
        await changeScope(requested)
        await load()
    }
    func load() async {
        if initializationTask != nil && !initialized {
            initializationReloadRequested = true
            return
        }
        await loadCatalog()
    }
    private func loadCatalog() async {
        operation += 1; let id = operation; let startedScope = scope
        if tracks.isEmpty { phase = .loading }
        if featuredTracks.isEmpty && collections.isEmpty { featuredPhase = .loading }
        catalogTask?.cancel()
        catalogFailure = nil; featuredFailure = nil
        let client = self.client, locale = locale
        // The discovery endpoint is independent of the paginated catalog. Publish
        // each section as soon as it arrives; cancellation still owns both tasks.
        let work = Task { @MainActor in
            if let native = client as? NativeMusicAPI {
                await native.setLocale(locale)
                guard id == self.operation, !Task.isCancelled else { return }
                async let catalog: Void = self.loadCatalogSection(client, id: id, scope: startedScope, locale: locale)
                async let featured: Void = self.loadFeaturedSection(native, id: id, scope: startedScope, locale: locale)
                _ = await (catalog, featured)
            } else {
                await self.loadCatalogSection(client, id: id, scope: startedScope, locale: locale)
            }
        }
        catalogTask = work
        await withTaskCancellationHandler(operation: { await work.value }, onCancel: { work.cancel() })
    }
    private func loadCatalogSection(_ client: any CatalogProviding, id: Int, scope startedScope: AccountScope, locale: String) async {
        do {
            let catalog = try await client.catalog()
            guard id == operation, startedScope == scope, locale == self.locale, !Task.isCancelled else { return }
            if let offlineCache {
                do {
                    let candidates = try await offlineCache.reconciliationCandidates(catalog.items)
                    guard id == operation, startedScope == scope, locale == self.locale, !Task.isCancelled else { return }
                    if playback.isOfflinePlayback, let playing = playback.selectedTrack?.id, candidates.contains(playing) { playback.deny() }
                    let result = await offlineCache.removeInvalidated(candidates)
                    if !result.failed.isEmpty { offlineStatus = "offlineFailed" }
                } catch { offlineStatus = "offlineFailed" }
                await refreshOffline()
            }
            guard id == operation, startedScope == scope, locale == self.locale, !Task.isCancelled else { return }
            tracks = catalog.items; phase = tracks.isEmpty ? .empty : .loaded
            if let selected = activeCollection {
                let current = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
                activeCollection = MusicCollection(id: selected.id, slug: selected.slug, title: selected.title, description: selected.description,
                    version: selected.version, tracks: selected.tracks.compactMap { current[$0.id] }, nextCursor: nil)
            }
        } catch {
            guard id == operation, startedScope == scope, locale == self.locale, !Task.isCancelled else { return }
            phase = tracks.isEmpty ? .unavailable : .loaded
            catalogFailure = CatalogFailure(error)
        }
    }
    private func loadFeaturedSection(_ native: NativeMusicAPI, id: Int, scope startedScope: AccountScope, locale: String) async {
        do {
            let featured = try await native.featured()
            guard id == operation, startedScope == scope, locale == self.locale, !Task.isCancelled else { return }
            featuredTracks = featured.tracks; collections = featured.collections
            featuredPhase = featuredTracks.isEmpty ? .empty : .loaded
        } catch {
            guard id == operation, startedScope == scope, locale == self.locale, !Task.isCancelled else { return }
            featuredPhase = featuredTracks.isEmpty && collections.isEmpty ? .unavailable : .loaded
            featuredFailure = CatalogFailure(error)
        }
    }
    var favoriteTracks: [Track] { tracks.filter { favorites.contains($0.id) } }
    var results: [Track] {
        query.isEmpty ? (activeCollection?.tracks ?? tracks) : (activeCollection?.tracks ?? tracks).filter { ($0.title + " " + $0.artist).localizedCaseInsensitiveContains(query) }
    }
    var recentTracks: [Track] { recent.compactMap { item in tracks.first { $0.id == item.trackId } } }
    func refreshLibrary() async {
        guard !scopeTransition else { return }
        let captured = scope, generation = libraryGeneration
        do {
            await library.selectScope(captured)
            guard scope == captured, libraryGeneration == generation else { return }
            let value = try await library.view(in: captured)
            guard scope == captured, libraryGeneration == generation else { return }
            favorites = value.favorites; recent = value.recent; historyEnabled = value.historyEnabled
            libraryStatus = value.conflict ? "libraryConflict" : value.pending > 0 ? "libraryPending" : captured.accountID != nil && libraryRemote != nil && value.synced ? "librarySynced" : "libraryLocal"
        } catch { if scope == captured && libraryGeneration == generation { libraryStatus = "libraryError" } }
    }
    func syncLibrary() {
        guard let libraryRemote, scope.accountID != nil, !libraryBusy, !scopeTransition else { return }
        let captured = scope, generation = libraryGeneration
        libraryBusy = true
        syncTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.libraryGeneration == generation { self.libraryBusy = false } }
            do { try await self.library.synchronize(scope: captured, remote: libraryRemote); await self.refreshLibrary() }
            catch { if !Task.isCancelled && self.libraryGeneration == generation { self.libraryStatus = "libraryPending" } }
        }
    }
    func changeScope(_ requested: AccountScope) async {
        let scope = AccountScope(environment: self.scope.environment, accountID: requested.accountID)
        scopeTransition = true
        libraryGeneration += 1; syncTask?.cancel(); libraryBusy = false
        let transition = libraryGeneration
        operation += 1; catalogTask?.cancel(); detailTask?.cancel(); detail = nil; collections = []; featuredTracks = []; featuredPhase = .loading; activeCollection = nil; playback.clear(); tracks = []; favorites = []; recent = []
        await library.selectScope(scope)
        guard transition == libraryGeneration else { return }
        self.scope = scope; scopeTransition = false
        await library.releaseInactiveScopes(keeping: scope)
        await refreshLibrary(); syncLibrary()
    }
    func toggleFavorite(_ track: Track) async {
        do { try await library.setFavorite(track.id, value: !favorites.contains(track.id), scope: scope); await refreshLibrary(); syncLibrary() }
        catch { libraryStatus = "libraryError" }
    }
    func setHistory(_ enabled: Bool) async {
        do { try await library.setHistory(enabled, scope: scope); await refreshLibrary(); syncLibrary() }
        catch { libraryStatus = "libraryError" }
    }
    func clearHistory() async {
        do { try await library.clearHistory(scope: scope); await refreshLibrary(); syncLibrary() }
        catch { libraryStatus = "libraryError" }
    }
    func removeInactiveAccountData(confirmedScope: AccountScope) async {
        guard scope == confirmedScope, !scopeTransition else { localCleanupStatus = "localCleanupChanged"; return }
        do {
            let removed = try await library.removeInactiveAccountFiles(keeping: confirmedScope)
            localCleanupStatus = removed > 0 ? "localCleanupDone" : "localCleanupNothing"
        } catch { localCleanupStatus = "localCleanupFailed" }
    }
    func setAutoCache(_ enabled: Bool) {
        autoCacheFreeSongs = enabled
        UserDefaults.standard.set(enabled, forKey: offlinePreferenceKey)
    }
    func refreshOffline() async {
        guard let offlineCache else { return }
        offlineSongs = (try? await offlineCache.songs()) ?? []
        offlineBytes = (try? await offlineCache.usage()) ?? 0
    }
    func saveOffline(_ track: Track) {
        guard let nativeMusic, let offlineCache, offlineDownloading == nil else { return }
        offlineDownloading = track.id; offlineStatus = "offlineSaving"
        let ticket = OfflineDownloadTicket(); offlineTicket = ticket
        offlineTask = Task { [weak self] in
            guard let self else { return }
            defer { self.offlineDownloading = nil }
            do { try await offlineCache.download(track, source: nativeMusic, cancellation: ticket); self.offlineStatus = "offlineSaved" }
            catch is CancellationError { self.offlineStatus = "" }
            catch APIError.storageUnavailable { self.offlineStatus = "offlineFull" }
            catch { self.offlineStatus = "offlineFailed" }
            await self.refreshOffline()
        }
    }
    func cancelOfflineDownload() { offlineTicket?.cancel(); offlineTask?.cancel() }
    func removeOffline(_ id: String? = nil) async {
        cancelOfflineDownload()
        if playback.isOfflinePlayback && (id == nil || playback.selectedTrack?.id == id) { playback.pause() }
        do { if let id { try await offlineCache?.remove(id) } else { try await offlineCache?.clear() }; offlineStatus = "" }
        catch { offlineStatus = "offlineFailed" }
        await refreshOffline()
    }
    func clearCache() async {
        detailTask?.cancel(); detail = nil; URLCache.shared.removeAllCachedResponses()
        do { try await artwork.clearCache() } catch { libraryStatus = "libraryError"; return }
        await load()
    }
    func select(_ track: Track, from list: [Track]? = nil) {
        let list = list ?? [track]
        if let index = list.firstIndex(of: track) { playback.setQueue(list, startingAt: index, play: false) }
        else { playback.select(track) }
        showPlayer = true
    }
    private func loadDetail(_ track: Track?) {
        detail = nil; detailTask?.cancel()
        guard let track, let nativeMusic else { return }
        let version = operation, locale = locale
        detailTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
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
