import SwiftUI

struct RootView: View {
    private let legalOrigin = URL(string: Bundle.main.object(forInfoDictionaryKey: "StationLegalOrigin") as? String ?? "https://example.invalid")!
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showQueue = false
    @State private var confirmHistoryClear = false
    @State private var confirmLocalCleanup = false
    @State private var cleanupScope: AccountScope?
    @State private var showDeletion = false
    @State private var confirmDeletion = false
    @State private var deletionPassword = ""
    @State private var deletionTotp = ""
    var body: some View {
        ZStack {
            if model.startupPhase == .ready {
                mainTabs.transition(.opacity)
            } else {
                StartupView(model: model).transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: model.startupPhase)
        .statusBarHidden(model.startupPhase != .ready)
        .tint(Palette.accent)
        .onOpenURL { url in Task { await model.receiveMusicLink(url) } }
        .alert(model.t("linkUnavailable"), isPresented: $model.linkUnavailable) { Button(model.t("close"), role: .cancel) {} }
        .sheet(isPresented: $model.showPlayer) { player }
        .task { await model.initialize() }
        .onChange(of: model.playback.state) { _, state in
            if state == .verificationRequired && model.nativeMusic != nil { Task { await model.load() } }
        }
        .onChange(of: model.locale) { _, _ in if model.nativeMusic != nil { Task { await model.load() } } }
        .onChange(of: model.account.scope) { _, scope in Task { await model.accountScopeChanged(scope) } }
        .alert(model.t("clearHistoryConfirm"), isPresented: $confirmHistoryClear) { Button(model.t("clearHistory"), role: .destructive) { Task { await model.clearHistory() } }; Button(model.t("cancel"), role: .cancel) {} }
        .confirmationDialog(model.t("localCleanupConfirm"), isPresented: $confirmLocalCleanup, titleVisibility: .visible) {
            Button(model.t("localCleanup"), role: .destructive) {
                if let scope = cleanupScope { Task { await model.removeInactiveAccountData(confirmedScope: scope) } }
            }
            Button(model.t("cancel"), role: .cancel) {}
        } message: { Text(model.t("localCleanupDetail")) }
        .sheet(isPresented: $showDeletion) { deletionSheet }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.playback.becameActive(); model.syncLibrary() } }
        .environment(\.locale, Locale(identifier: model.locale))
    }
    private var mainTabs: some View {
        TabView(selection: $model.selectedTab) {
            NavigationStack { discover.safeAreaInset(edge: .bottom) { miniPlayer } }.tabItem { Label(model.t("discover"), systemImage: "sparkles") }.tag(0)
            NavigationStack { catalog.safeAreaInset(edge: .bottom) { miniPlayer } }.tabItem { Label(model.t("catalog"), systemImage: "music.note.list") }.tag(1)
            NavigationStack { library.safeAreaInset(edge: .bottom) { miniPlayer } }.tabItem { Label(model.t("library"), systemImage: "person.crop.circle") }.tag(2)
        }
    }
    private var featuredTrack: Track? { model.playback.selectedTrack ?? model.discoveryTracks.first }
    private var isPlaying: Bool { model.playback.state == .playing }
    private var isAuthorizing: Bool { model.playback.state == .authorizing }
    private func time(_ seconds: Double) -> String {
        let safe = seconds.isFinite ? max(0, min(seconds, 86400)) : 0
        return String(format: "%02d:%02d", Int(safe) / 60, Int(safe) % 60)
    }
    private func playFeatured() {
        guard let track = featuredTrack else { return }
        if model.playback.selectedTrack?.id != track.id {
            let list = model.discoveryTracks
            model.playback.setQueue(list, startingAt: list.firstIndex(of: track) ?? 0, play: false)
        }
        if model.nativeMusic == nil { model.showPlayer = true }
        else { model.playback.handle(.toggle) }
    }
    @ViewBuilder private var miniPlayer: some View {
        if let track = model.playback.selectedTrack {
            HStack(spacing: 10) {
                Button { model.showPlayer = true } label: {
                    HStack(spacing: 10) {
                        OrbitArtwork(track: track, model: model).frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(track.artist).font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("miniPlayer")
                OrbitIconButton(symbol: isPlaying || isAuthorizing ? "pause.fill" : "play.fill", label: model.t(isPlaying || isAuthorizing ? "pause" : "play")) {
                    if model.nativeMusic == nil { model.showPlayer = true } else { model.playback.handle(.toggle) }
                }
                OrbitIconButton(symbol: "forward.end.fill", label: model.t("next")) { model.adjacent(1) }.disabled(!model.playback.queue.canNext)
            }.padding(.horizontal, 12).padding(.vertical, 8)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line, lineWidth: 1))
                .padding(.horizontal, 16).padding(.bottom, 4)
        }
    }
    private var header: some View {
        HStack(spacing: 10) {
            Image("OrbitBrand").resizable().scaledToFit().frame(width: 38, height: 38).clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Station Cat Music").font(.system(.headline, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                Text("Q U I E T   O R B I T").font(.system(size: 9, weight: .medium)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 4)
            OrbitIconButton(symbol: "magnifyingglass", label: model.t("search")) { model.selectedTab = 1 }
                .background(Palette.panel.opacity(0.8), in: Circle())
        }
    }
    private var discover: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let track = featuredTrack {
                    VStack(spacing: 8) {
                        HStack(alignment: .top) {
                            Text(model.t("orbitIntro")).font(.subheadline).lineSpacing(4).foregroundStyle(Palette.muted)
                            Spacer()
                            Text("A SLOWER\nDAY").font(.system(size: 9, weight: .medium)).tracking(3).lineSpacing(5).foregroundStyle(Palette.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            if model.playback.selectedTrack?.id == track.id { model.showPlayer = true }
                            else { model.select(track, from: model.discoveryTracks) }
                        } label: {
                            OrbitRecord(track: track, model: model).frame(maxWidth: typeSize.isAccessibilitySize ? 260 : 250)
                        }.buttonStyle(.plain).accessibilityIdentifier("track.\(track.id)").accessibilityLabel(track.title + ", " + track.artist)
                        VStack(spacing: 6) {
                            Text(track.title).font(.title2.weight(.bold)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            Text(track.artist).font(.subheadline).foregroundStyle(Palette.muted)
                        }
                        Text(model.t("heroSubtitle")).font(.subheadline).foregroundStyle(Palette.muted)
                            .multilineTextAlignment(.center).lineSpacing(4).padding(.top, 2)
                        progress(for: track)
                        playbackControls(featured: true)
                    }
                } else {
                    trackContent(phase: model.discoveryPhase, tracks: model.discoveryTracks, search: false)
                }
                discoveryShelf
                Text(model.t(model.nativeMusic == nil ? "mockExplanation" : "isolatedMusic"))
                    .font(.caption2).foregroundStyle(Palette.muted).padding(.top, 4)
            }.padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 24)
        }.background { OrbitBackground() }.toolbar(.hidden, for: .navigationBar)
            .accessibilityIdentifier("discoverScreen")
    }
    @ViewBuilder private var discoveryShelf: some View {
        if !model.collections.isEmpty {
            sectionHeading(model.t("featuredAlbums"))
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(model.collections) { collection in
                        Button {
                            model.query = ""; model.selectedTab = 1
                            Task { await model.selectCollection(collection) }
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                OrbitArtwork(track: collection.tracks.first, model: model).frame(width: 140, height: 140).clipShape(RoundedRectangle(cornerRadius: 12))
                                Text(collection.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                Text("\(collection.tracks.count) " + model.t("tracksCount")).font(.caption).foregroundStyle(Palette.muted)
                            }.frame(width: 140, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                }
            }
        } else if !model.discoveryTracks.isEmpty {
            sectionHeading(model.t("tonight"))
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(model.discoveryTracks.filter { $0.id != featuredTrack?.id }) { track in
                        Button { model.select(track, from: model.discoveryTracks) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                OrbitArtwork(track: track, model: model).frame(width: 140, height: 126).clipShape(RoundedRectangle(cornerRadius: 12))
                                Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                Text(track.artist).font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
                            }.frame(width: 140, alignment: .leading)
                        }.buttonStyle(.plain).accessibilityIdentifier("track.\(track.id)")
                    }
                }
            }
        }
    }
    private func sectionHeading(_ title: String) -> some View {
        HStack {
            Text(title).font(.title3.weight(.semibold))
            Spacer()
            Button { model.selectedTab = 1 } label: {
                HStack(spacing: 5) { Text(model.t("viewAll")).font(.caption); Image(systemName: "chevron.right").font(.caption2) }.frame(minHeight: 44)
            }.buttonStyle(.plain).foregroundStyle(Palette.muted)
        }
    }
    private var catalog: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(model.t(model.nativeMusic == nil ? "mockExplanation" : "isolatedMusic"))
                    .font(.caption).foregroundStyle(Palette.muted)
                if !model.collections.isEmpty || model.activeCollection != nil {
                    HStack {
                        Menu {
                            Button(model.t("allTracks")) { model.activeCollection = nil }
                            ForEach(model.collections) { collection in Button(collection.title) { Task { await model.selectCollection(collection) } } }
                        } label: {
                            Label(model.activeCollection?.title ?? model.t("albums"), systemImage: "square.stack")
                                .font(.subheadline.weight(.medium)).padding(.horizontal, 14).frame(minHeight: 44)
                                .background(Palette.panel, in: Capsule())
                        }
                        Spacer()
                        if let url = model.collectionShareURL {
                            ShareLink(item: url) { Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44) }.accessibilityLabel(model.t("shareMusic"))
                        }
                    }
                }
                if let collection = model.activeCollection, !collection.description.isEmpty {
                    Text(collection.description).font(.subheadline).lineSpacing(4).foregroundStyle(Palette.muted)
                }
                LazyVStack(spacing: 0) { trackContent(phase: model.phase, tracks: model.results, search: true) }
            }.padding(.horizontal, 22).padding(.bottom, 24)
        }.background { OrbitBackground() }.accessibilityIdentifier("catalogScreen")
            .navigationTitle(model.t("catalog")).searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(model.t("search")))
    }
    @ViewBuilder private func trackContent(phase: AppModel.Phase, tracks: [Track], search: Bool) -> some View {
        switch phase {
        case .loading: ProgressView(model.t("loading")).frame(maxWidth: .infinity, minHeight: 160).accessibilityIdentifier("loading")
        case .unavailable:
            ContentUnavailableView { Label(model.t("unavailable"), systemImage: "wifi.slash") } description: { Text(model.t("unavailableDetail")) } actions: {
                Button(model.t("retry")) { Task { await model.load() } }.frame(minHeight: 44)
            }
        case .empty: ContentUnavailableView(model.t("empty"), systemImage: "music.note")
        case .loaded:
            if tracks.isEmpty {
                if search { ContentUnavailableView.search(text: model.query) }
                else { ContentUnavailableView(model.t("empty"), systemImage: "music.note") }
            }
            ForEach(tracks) { track in trackRow(track, list: tracks) }
        }
    }
    private func trackRow(_ track: Track, list: [Track]) -> some View {
        HStack(spacing: 12) {
            Button { model.select(track, from: list) } label: {
                HStack(spacing: 12) {
                    OrbitArtwork(track: track, model: model).frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                        Text(track.artist).font(.caption).foregroundStyle(Palette.muted)
                        Text(model.t(model.nativeMusic == nil ? "sampleTrack" : "access." + track.access.rawValue)).font(.caption2).foregroundStyle(Palette.accent)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("track.\(track.id)")
            OrbitIconButton(symbol: model.favorites.contains(track.id) ? "heart.fill" : "heart", label: model.t("favorite") + " " + track.title, selected: model.favorites.contains(track.id)) {
                Task { await model.toggleFavorite(track) }
            }
        }.padding(.vertical, 14).overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 0.5) }
    }
    private var library: some View {
        ScrollView {
            VStack(spacing: 22) {
                NavigationLink { accountPage } label: {
                    HStack(spacing: 14) {
                        Image("OrbitBrand").resizable().frame(width: 58, height: 58).clipShape(RoundedRectangle(cornerRadius: 16)).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(model.t(model.account.scope.accountID == nil ? "guest" : "signedIn")).font(.headline)
                            Text(model.t("accountSecurity")).font(.subheadline).foregroundStyle(Palette.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
                    }.padding(20).background(Palette.panel, in: RoundedRectangle(cornerRadius: 24))
                }.buttonStyle(.plain).accessibilityIdentifier("accountEntry")
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.t("myMusic")).font(.headline).foregroundStyle(Palette.muted)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                        NavigationLink { favoritesPage } label: {
                            libraryTile("favorites", symbol: "heart.fill", count: model.favoriteTracks.count)
                        }.accessibilityIdentifier("favoritesEntry")
                        NavigationLink { historyPage } label: {
                            libraryTile("recent", symbol: "clock.fill", count: model.recentTracks.count)
                        }.accessibilityIdentifier("historyEntry")
                    }.buttonStyle(.plain)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.t("settings")).font(.headline).foregroundStyle(Palette.muted)
                    VStack(spacing: 0) {
                        NavigationLink { offlinePage } label: { libraryCategory("offlineMusic", subtitle: "offlineSummary", symbol: "arrow.down.circle") }.accessibilityIdentifier("offlineEntry")
                        Divider().overlay(Palette.line).padding(.leading, 66)
                        NavigationLink { privacyPage } label: { libraryCategory("privacyStorage", subtitle: "privacyStorageDetail", symbol: "hand.raised") }.accessibilityIdentifier("privacyEntry")
                        Divider().overlay(Palette.line).padding(.leading, 66)
                        NavigationLink { preferencesPage } label: { libraryCategory("preferences", subtitle: "preferencesDetail", symbol: "slider.horizontal.3") }.accessibilityIdentifier("preferencesEntry")
                        Divider().overlay(Palette.line).padding(.leading, 66)
                        NavigationLink { helpPage } label: { libraryCategory("aboutSupport", subtitle: "aboutSupportDetail", symbol: "questionmark.circle") }.accessibilityIdentifier("helpEntry")
                    }.buttonStyle(.plain).background(Palette.panel, in: RoundedRectangle(cornerRadius: 24))
                }
                Text(model.t("yourMusicSpace")).font(.caption).foregroundStyle(Palette.muted).padding(.bottom, 8)
            }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
        }.background { OrbitBackground() }.navigationTitle(model.t("library")).accessibilityIdentifier("libraryHome")
    }
    private func libraryTile(_ key: String, symbol: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: symbol).font(.title3).foregroundStyle(Palette.accent)
                Spacer()
                Text(count, format: .number).font(.title2.weight(.semibold)).monospacedDigit()
            }
            HStack(alignment: .firstTextBaseline) {
                Text(model.t(key)).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Palette.muted)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Palette.panel, in: RoundedRectangle(cornerRadius: 22))
    }
    private func libraryCategory(_ key: String, subtitle: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Palette.accent).frame(width: 32).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.t(key)).font(.body.weight(.medium))
                Text(model.t(subtitle)).font(.caption).foregroundStyle(Palette.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
        }.padding(.horizontal, 18).padding(.vertical, 18).contentShape(Rectangle())
    }
    private func libraryPage<Content: View>(_ title: String, id: String, @ViewBuilder content: () -> Content) -> some View {
        Form { content() }.accessibilityIdentifier(id)
            .scrollContentBackground(.hidden).background { OrbitBackground() }
            .navigationTitle(model.t(title)).navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { miniPlayer }
    }
    private var accountPage: some View {
        libraryPage("accountSecurity", id: "accountPage") {
            Section {
                Label(model.t(model.account.scope.accountID == nil ? "guest" : "signedIn"), systemImage: "person.crop.circle").font(.headline)
                if model.account.enabled {
                    Text(model.t("isolatedAuth")).font(.caption).foregroundStyle(Palette.muted)
                    if model.account.scope.accountID == nil {
                        Button(model.t("signIn")) { Task { await model.account.signIn(locale: model.locale) } }.disabled(model.account.busy)
                    } else {
                        Button(model.t("signOut")) { Task { await model.account.signOut() } }.disabled(model.account.busy)
                    }
                    if !model.account.messageKey.isEmpty { Text(model.t(model.account.messageKey)).font(.footnote).accessibilityIdentifier("authMessage") }
                } else { Text(model.t("authNotReady")).font(.footnote).foregroundStyle(Palette.muted) }
            }.listRowBackground(Palette.panel)
            if model.account.enabled {
                Section(model.t("accountDeletion")) {
                    if model.account.scope.accountID != nil {
                        Button(model.t("deleteAccount"), role: .destructive) { showDeletion = true }.disabled(model.account.busy)
                    }
                    Button(model.t("queryDeletion")) { Task { await model.account.queryDeletion() } }.disabled(model.account.busy)
                    if !model.account.deletionStatus.isEmpty { Text(model.t("deletion." + model.account.deletionStatus)).font(.footnote) }
                }.listRowBackground(Palette.panel)
            }
        }
    }
    private var favoritesPage: some View {
        libraryPage("favorites", id: "favoritesPage") {
            Section {
                let favoriteTracks = model.favoriteTracks
                if favoriteTracks.isEmpty { Label(model.t("noFavorites"), systemImage: "heart").foregroundStyle(Palette.muted).font(.subheadline) }
                ForEach(favoriteTracks) { track in libraryRow(track, list: favoriteTracks) }
            }.listRowBackground(Palette.panel)
            Section {
                Text(model.t(model.libraryStatus)).font(.caption).foregroundStyle(Palette.muted)
                if model.libraryRemote != nil && model.scope.accountID != nil { Button(model.t("syncNow")) { model.syncLibrary() }.disabled(model.libraryBusy) }
            }.listRowBackground(Palette.panel)
        }
    }
    private var historyPage: some View {
        libraryPage("recent", id: "historyPage") {
            Section {
                let recentTracks = model.recentTracks
                ForEach(recentTracks) { track in libraryRow(track, list: recentTracks) }
                if recentTracks.isEmpty { Label(model.t("noRecent"), systemImage: "clock").font(.subheadline).foregroundStyle(Palette.muted) }
            }.listRowBackground(Palette.panel)
            Section { Text(model.t(model.historyEnabled ? "historyOnDetail" : "historyOffDetail")).font(.footnote).foregroundStyle(Palette.muted) }.listRowBackground(Palette.panel)
        }
    }
    private var offlineUsage: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary; formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: Int64(model.offlineBytes)) + " / 500 MB"
    }
    private var offlinePage: some View {
        libraryPage("offlineMusic", id: "offlinePage") {
            Section {
                LabeledContent(model.t("offlineSpace"), value: offlineUsage)
                Toggle(model.t("offlineAuto"), isOn: Binding(get: { model.autoCacheFreeSongs }, set: { model.setAutoCache($0) })).disabled(model.offlineCache == nil)
                Text(model.t("offlineDetail")).font(.footnote).foregroundStyle(Palette.muted)
            }.listRowBackground(Palette.panel)
            Section {
                if model.offlineSongs.isEmpty { Label(model.t("offlineEmpty"), systemImage: "arrow.down.circle").foregroundStyle(Palette.muted) }
                ForEach(model.offlineSongs) { song in
                    HStack {
                        Button { model.select(song.track, from: model.offlineSongs.map(\.track)) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(song.track.title).font(.headline)
                                Text(model.t("offlineUntil") + " " + song.expiresAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(Palette.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                        Button(role: .destructive) { Task { await model.removeOffline(song.id) } } label: { Image(systemName: "trash").frame(width: 44, height: 44) }.accessibilityLabel(model.t("remove") + " " + song.track.title)
                    }
                }
            }.listRowBackground(Palette.panel)
            Section {
                if !model.offlineStatus.isEmpty { Text(model.t(model.offlineStatus)).font(.footnote) }
                if model.offlineDownloading != nil { Button(model.t("cancel")) { model.cancelOfflineDownload() } }
                Button(model.t("offlineClear"), role: .destructive) { Task { await model.removeOffline() } }.disabled(model.offlineBytes == 0 && model.offlineDownloading == nil)
            }.listRowBackground(Palette.panel)
        }.task { await model.refreshOffline() }
    }
    private var privacyPage: some View {
        libraryPage("privacyStorage", id: "privacyPage") {
            Section(model.t("recent")) {
                Toggle(model.t("historyEnabled"), isOn: Binding(get: { model.historyEnabled }, set: { value in Task { await model.setHistory(value) } }))
                Button(model.t("clearHistory"), role: .destructive) { confirmHistoryClear = true }
                Text(model.t(model.libraryStatus)).font(.caption).foregroundStyle(Palette.muted)
            }.listRowBackground(Palette.panel)
            Section {
                Button(model.t("clearCache")) { Task { await model.clearCache() } }
            } header: { Text(model.t("temporaryStorage")) } footer: { Text(model.t("cacheDetail")) }.listRowBackground(Palette.panel)
            Section {
                Button(model.t("localCleanup"), role: .destructive) { cleanupScope = model.scope; confirmLocalCleanup = true }
                if !model.localCleanupStatus.isEmpty { Text(model.t(model.localCleanupStatus)).font(.footnote) }
            } header: { Text(model.t("accountStorage")) } footer: { Text(model.t("localCleanupDetail")) }.listRowBackground(Palette.panel)
        }
    }
    private var preferencesPage: some View {
        libraryPage("preferences", id: "preferencesPage") {
            Section {
                Picker(model.t("language"), selection: $model.locale) { Text("简体中文").tag("zh-Hans"); Text("繁體中文").tag("zh-Hant"); Text("English").tag("en"); Text("日本語").tag("ja") }
            }.listRowBackground(Palette.panel)
        }
    }
    private var helpPage: some View {
        libraryPage("aboutSupport", id: "helpPage") {
            Section {
                Label("Station Cat Music", systemImage: "music.note").font(.headline)
                Text(model.t("yourMusicSpace")).foregroundStyle(Palette.muted)
                LabeledContent(model.t("appVersion"), value: appVersion).accessibilityIdentifier("appVersion")
                Text(model.t(model.nativeMusic == nil ? "mockExplanation" : "isolatedMusic")).font(.caption).foregroundStyle(Palette.muted)
            }.listRowBackground(Palette.panel)
            Section {
                NavigationLink { releaseNotesPage } label: { Label(model.t("releaseNotes"), systemImage: "sparkles") }
                    .accessibilityIdentifier("releaseNotesEntry")
            }.listRowBackground(Palette.panel)
            Section {
                Link(model.t("privacy"), destination: URL(string: "/music/#music-privacy", relativeTo: legalOrigin)!)
                Link(model.t("terms"), destination: URL(string: "/music/#music-listening", relativeTo: legalOrigin)!)
                Link(model.t("support"), destination: URL(string: "mailto:brodstem@protonmail.com")!)
            }.listRowBackground(Palette.panel)
        }
    }
    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
    private var releaseNotesPage: some View {
        libraryPage("releaseNotes", id: "releaseNotesPage") {
            Section {
                Text("Station Cat Music · " + appVersion).font(.headline)
                Text("2026-09-24").font(.caption).foregroundStyle(Palette.muted)
            }.listRowBackground(Palette.panel)
            Section(model.t("thisUpdate")) {
                Label(model.t("releaseArtwork"), systemImage: "photo")
                Label(model.t("releasePlayback"), systemImage: "play.circle")
                Label(model.t("releaseInterface"), systemImage: "person.crop.circle")
                Label(model.t("releaseOffline"), systemImage: "arrow.down.circle")
            }.listRowBackground(Palette.panel)
        }
    }
    private func libraryRow(_ track: Track, list: [Track]) -> some View {
        Button { model.select(track, from: list) } label: {
            HStack(spacing: 12) {
                OrbitArtwork(track: track, model: model).frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 3) { Text(track.title).font(.subheadline); Text(track.artist).font(.caption).foregroundStyle(Palette.muted) }
                Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
            }.frame(minHeight: 44)
        }.buttonStyle(.plain)
    }
    private var deletionSheet: some View {
        NavigationStack {
            Form {
                Section { Text(model.t("deleteScope")); Text(model.t("deleteSubscription")).font(.footnote) }
                Section(model.t("verifyIdentity")) {
                    SecureField(model.t("password"), text: $deletionPassword).textContentType(.password)
                    TextField(model.t("totpCode"), text: $deletionTotp).keyboardType(.numberPad).textContentType(.oneTimeCode)
                    Button(model.t("prepareDeletion")) {
                        let password = deletionPassword, totp = deletionTotp; deletionPassword = ""; deletionTotp = ""
                        Task { await model.account.prepareDeletion(password: password, totp: totp) }
                    }.disabled(deletionPassword.isEmpty || model.account.busy)
                }
                if model.account.confirmationReady {
                    Section { Text(model.t("deleteConfirmDetail")); Button(model.t("confirmDelete"), role: .destructive) { confirmDeletion = true }.disabled(model.account.busy) }
                }
                if !model.account.deletionStatus.isEmpty { Text(model.t("deletion." + model.account.deletionStatus)) }
                if !model.account.messageKey.isEmpty { Text(model.t(model.account.messageKey)) }
                Button(model.t("queryDeletion")) { Task { await model.account.queryDeletion() } }.disabled(model.account.busy)
            }.navigationTitle(model.t("deleteAccount"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(model.t("close")) { showDeletion = false } } }
            .confirmationDialog(model.t("confirmDelete"), isPresented: $confirmDeletion, titleVisibility: .visible) {
                Button(model.t("confirmDelete"), role: .destructive) { Task { await model.account.confirmDeletion() } }
            } message: { Text(model.t("deleteScope")) }
            .onDisappear { deletionPassword = ""; deletionTotp = "" }
        }.preferredColorScheme(.dark)
    }
    private func progress(for track: Track) -> some View {
        let selected = model.playback.selectedTrack?.id == track.id
        let duration = selected ? model.playback.duration : track.durationSeconds
        return VStack(spacing: 0) {
            Slider(value: Binding(get: { selected ? model.playback.position : 0 }, set: { model.playback.seek(to: $0) }), in: 0...max(1, duration))
                .disabled(!selected || ![.playing, .paused, .completed].contains(model.playback.state)).accessibilityLabel(model.t("seek"))
            HStack { Text(time(selected ? model.playback.position : 0)).accessibilityIdentifier("playbackElapsed"); Spacer(); Text(time(duration)) }
                .font(.caption.monospacedDigit()).foregroundStyle(Palette.muted)
        }
    }
    private func playbackControls(featured: Bool = false) -> some View {
        HStack {
            OrbitIconButton(symbol: "shuffle", label: model.t("shuffle"), selected: model.playback.queue.shuffled) { model.playback.setShuffle(!model.playback.queue.shuffled) }
                .accessibilityValue(model.t(model.playback.queue.shuffled ? "on" : "off"))
            Spacer(minLength: 4)
            OrbitIconButton(symbol: "backward.end.fill", label: model.t("previous")) { model.adjacent(-1) }
                .disabled(!model.playback.queue.canPrevious && model.playback.position <= 3)
            Spacer(minLength: 4)
            OrbitPlayButton(playing: isPlaying, loading: isAuthorizing, label: model.t(isPlaying || isAuthorizing ? "pause" : "play")) {
                if featured { playFeatured() }
                else if model.nativeMusic != nil { model.playback.handle(.toggle) }
            }.disabled(!featured && model.nativeMusic == nil)
            Spacer(minLength: 4)
            OrbitIconButton(symbol: "forward.end.fill", label: model.t("next")) { model.adjacent(1) }.disabled(!model.playback.queue.canNext)
            Spacer(minLength: 4)
            Menu {
                ForEach(PlaybackQueue.RepeatMode.allCases, id: \.self) { mode in Button(model.t("repeat." + mode.rawValue)) { model.playback.setRepeat(mode) } }
            } label: {
                Image(systemName: model.playback.queue.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 20, weight: .medium)).frame(minWidth: 44, minHeight: 44)
                    .foregroundStyle(model.playback.queue.repeatMode == .off ? Palette.muted : Palette.accent)
            }.accessibilityLabel(model.t("repeat")).accessibilityValue(model.t("repeat." + model.playback.queue.repeatMode.rawValue))
        }.padding(.vertical, 4)
    }
    private var player: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let track = model.playback.selectedTrack {
                        OrbitRecord(track: track, model: model).frame(maxWidth: model.detail?.lyrics.kind == "timed" ? 180 : 280).padding(.top, 4)
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(track.title).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                                Text(track.artist).font(.subheadline).foregroundStyle(Palette.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            OrbitIconButton(symbol: model.favorites.contains(track.id) ? "heart.fill" : "heart", label: model.t("favorite") + " " + track.title, selected: model.favorites.contains(track.id)) { Task { await model.toggleFavorite(track) } }
                        }
                        if model.nativeMusic == nil {
                            Text(model.t("playbackNotReady")).font(.subheadline).foregroundStyle(Palette.muted).accessibilityIdentifier("playbackUnavailable")
                        } else if model.playback.state == .verificationRequired {
                            Text(model.t("playbackDenied")).font(.subheadline).foregroundStyle(Palette.accent)
                        }
                        if track.offlineEligible == true {
                            let saved = model.offlineSongs.contains { $0.id == track.id && $0.track.audioVersion == track.audioVersion }
                            Button { model.saveOffline(track) } label: {
                                Label(model.t(saved ? "offlineSaved" : model.offlineDownloading == track.id ? "offlineSaving" : "offlineSave"), systemImage: saved ? "checkmark.circle" : "arrow.down.circle")
                            }.font(.subheadline).foregroundStyle(Palette.accent).frame(minHeight: 44)
                                .disabled(saved || model.offlineDownloading != nil).accessibilityIdentifier("saveOffline")
                            if !model.offlineStatus.isEmpty && !saved { Text(model.t(model.offlineStatus)).font(.caption).foregroundStyle(Palette.muted) }
                        }
                        if model.playback.isOfflinePlayback { Label(model.t("offlinePlaying"), systemImage: "wifi.slash").font(.caption).foregroundStyle(Palette.accent) }
                        if let key = model.playback.noticeKey { Text(model.t(key)).font(.footnote).foregroundStyle(Palette.accent) }
                        if let lyrics = model.detail?.lyrics, lyrics.kind != "none" {
                            VStack(alignment: .leading, spacing: 12) {
                                Divider().overlay(Palette.line)
                                Label(model.t("lyrics"), systemImage: "text.alignleft").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.accent)
                                OrbitLyrics(lyrics: lyrics, position: model.playback.position + model.playback.previewOffset)
                            }
                        } else if let summary = model.detail?.summary, !summary.isEmpty {
                            Text(summary).font(.subheadline).lineSpacing(4).foregroundStyle(Palette.muted)
                        }
                    }
                }.padding(.horizontal, 24).padding(.bottom, 30).frame(maxWidth: .infinity)
            }.background { OrbitBackground() }
                .safeAreaInset(edge: .bottom, spacing: 0) { playerDock }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { OrbitIconButton(symbol: "chevron.down", label: model.t("close")) { model.showPlayer = false } }
                    ToolbarItem(placement: .principal) { Text("S T A T I O N   C A T").font(.caption2.weight(.medium)).foregroundStyle(Palette.muted) }
                }
                .sheet(isPresented: $showQueue) { queueSheet }
        }.preferredColorScheme(.dark).tint(Palette.accent)
    }
    @ViewBuilder private var playerDock: some View {
        if let track = model.playback.selectedTrack {
            VStack(spacing: 6) {
                progress(for: track)
                playbackControls()
                HStack {
                    Button { showQueue = true } label: { Label(model.t("queue"), systemImage: "list.bullet").font(.caption).frame(minHeight: 44) }
                        .accessibilityIdentifier("playerQueue")
                    Spacer()
                    if model.detail?.previewAvailable == true {
                        Button(model.t("preview")) { model.playback.requestPlay(variant: "preview") }.font(.caption).frame(minHeight: 44).foregroundStyle(Palette.accent)
                    }
                    Menu {
                        ForEach([15, 30, 60], id: \.self) { minutes in Button("\(minutes) " + model.t("minutes")) { model.playback.setSleepTimer(seconds: Double(minutes * 60)) } }
                        Button(model.t("off")) { model.playback.setSleepTimer(seconds: nil) }
                    } label: { Image(systemName: model.playback.sleepDeadline == nil ? "moon" : "moon.fill").frame(width: 44, height: 44) }.accessibilityLabel(model.t("sleepTimer"))
                    if let url = model.trackShareURL {
                        ShareLink(item: url) { Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44) }.accessibilityLabel(model.t("shareMusic"))
                    }
                }.foregroundStyle(Palette.muted)
            }.padding(.horizontal, 24).padding(.top, 12).background(Palette.background.opacity(0.97))
        }
    }
    private var queueSheet: some View {
        NavigationStack {
            List {
                ForEach(model.playback.queue.orderedEntries) { entry in
                    HStack {
                        Button { model.playback.chooseQueueEntry(entry.id) } label: {
                            HStack(spacing: 12) {
                                OrbitArtwork(track: entry.track, model: model).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(entry.track.title).font(.subheadline)
                                if entry.id == model.playback.queue.currentID { Image(systemName: "speaker.wave.2.fill").foregroundStyle(Palette.accent) }
                            }.frame(minHeight: 44)
                        }.buttonStyle(.plain)
                        Spacer()
                        if entry.id != model.playback.queue.currentID {
                            OrbitIconButton(symbol: "minus.circle", label: model.t("remove") + " " + entry.track.title) { model.playback.removeQueueEntry(entry.id) }
                        }
                    }.listRowBackground(Palette.panel)
                }
                Button(model.t("clearQueue"), role: .destructive) { model.playback.clear(); showQueue = false; model.showPlayer = false }.listRowBackground(Palette.panel)
            }.scrollContentBackground(.hidden).background(Palette.background).navigationTitle(model.t("queue"))
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(model.t("close")) { showQueue = false }.accessibilityIdentifier("queueClose") } }
        }.preferredColorScheme(.dark).tint(Palette.accent)
    }
}
