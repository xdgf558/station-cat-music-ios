import SwiftUI

/// Search published metadata without assigning an album to an unclassified song.
nonisolated enum PlatformShelfSearch {
    static func matches(_ track: Track, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return ([track.title, track.artist] + (track.release?.albums ?? []).map(\.title))
            .contains { $0.localizedStandardContains(query) }
    }
}

struct PlatformCatalogScreen: View {
    @Bindable var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var searching: Bool
    private var visibleTracks: [Track] {
        let source = model.catalogCategory == .singles ? model.platformSingles : model.tracks
        return source.filter { PlatformShelfSearch.matches($0, query: model.query) }
    }
    private var visibleAlbums: [PlatformAlbum] {
        let query = model.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.platformAlbums.filter { $0.matches(query) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("RECORD SHELF").radioMono(10, weight: .semibold).tracking(2)
                        .foregroundStyle(Palette.muted).accessibilityHidden(true)
                    Text(model.t("radio.shelfTitle")).radioSerif(34, weight: .black, relativeTo: .largeTitle)
                        .padding(.vertical, -5)
                        .foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
                }
                VStack(alignment: .leading, spacing: 14) { searchField; categories }
                if model.phase != .unavailable, let failure = model.catalogFailure {
                    PlatformCatalogNotice(model: model, message: failure.messageKey, retained: true)
                }
                if model.phase == .loaded, model.catalogCategory != .all, model.platformClassificationUnavailable {
                    PlatformCatalogNotice(model: model, message: "catalogClassificationUnavailable", retained: false)
                }
                content
                if let notice = model.catalogNoticeKey {
                    Text(model.t(notice)).font(.caption).foregroundStyle(Palette.muted)
                }
            }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 28)
        }.background(Palette.background)
            .navigationTitle(model.t("radio.shelfTitle")).toolbar(.hidden, for: .navigationBar)
            .scrollDismissesKeyboard(.interactively).refreshable { await model.load() }
            .onChange(of: model.radioSearchRequest) { _, _ in focusRequestedSearch() }
            .onChange(of: model.selectedTab) { _, tab in if tab == 1 { focusRequestedSearch() } }
            .onAppear { focusRequestedSearch() }.accessibilityIdentifier("catalogScreen")
    }
    private func focusRequestedSearch() {
        guard model.selectedTab == 1, model.radioSearchRequest > 0 else { return }
        searching = true
        model.radioSearchRequest = 0
    }
    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted).accessibilityHidden(true)
            TextField(model.t("radio.shelfSearch"), text: $model.query,
                      prompt: Text(model.t("radio.shelfSearch")).foregroundStyle(Palette.muted))
                .font(.body).foregroundStyle(Palette.ink)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search).focused($searching).onSubmit { searching = false }
                .accessibilityIdentifier("catalogSearch")
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(model.t("catalogClearSearch"))
                    .accessibilityIdentifier("catalogClearSearch")
            }
        }.padding(.leading, 16).padding(.trailing, model.query.isEmpty ? 16 : 0)
            .frame(minHeight: 46).background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1))
    }
    @ViewBuilder private var categories: some View {
        if typeSize.isAccessibilitySize {
            Menu {
                ForEach(PlatformCatalogCategory.allCases) { category in
                    Button { searching = false; model.catalogCategory = category } label: {
                        Text(model.t(category.titleKey))
                    }.accessibilityIdentifier("catalogCategory." + category.rawValue)
                }
            } label: {
                HStack {
                    Text(model.t(model.catalogCategory.titleKey)).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    Image(systemName: "chevron.down").font(.body)
                }.foregroundStyle(Palette.ink).padding(14).frame(maxWidth: .infinity, minHeight: 44)
                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line))
            }.accessibilityLabel(model.t("catalogCategories"))
                .accessibilityValue(model.t(model.catalogCategory.titleKey)).accessibilityIdentifier("catalogCategoryMenu")
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PlatformCatalogCategory.allCases) { category in
                        let selected = model.catalogCategory == category
                        Button { searching = false; model.catalogCategory = category } label: {
                            Text(model.t(category.titleKey)).font(.subheadline.weight(.semibold)).fixedSize()
                                .foregroundStyle(selected ? Palette.background : Palette.ink)
                                .padding(.horizontal, 18).frame(height: 36)
                                .background(selected ? Palette.ink : .clear, in: Capsule())
                                .overlay(Capsule().stroke(selected ? .clear : Palette.line, lineWidth: 1))
                                .frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("catalogCategory." + category.rawValue)
                            .accessibilityAddTraits(selected ? [.isSelected] : [])
                    }
                }
            }.accessibilityElement(children: .contain).accessibilityLabel(model.t("catalogCategories"))
        }
    }
    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView(model.t("loading")).tint(Palette.accent).frame(maxWidth: .infinity, minHeight: 180)
        case .unavailable:
            ContentUnavailableView {
                Label(model.t("unavailable"), systemImage: "wifi.slash")
            } description: { Text(model.t(model.catalogFailure?.messageKey ?? "startupFailure")) }
                actions: { Button(model.t("retry")) { Task { await model.load() } }.frame(minHeight: 44) }
        case .empty:
            ContentUnavailableView(model.t("empty"), systemImage: "music.note")
        case .loaded:
            if model.catalogCategory == .albums {
                if visibleAlbums.isEmpty { emptyCategory("catalogNoAlbums", symbol: "square.stack") }
                else { albums }
            } else if model.catalogCategory == .singles {
                if visibleTracks.isEmpty { emptyCategory("catalogNoSingles", symbol: "music.note") }
                else { songs }
            } else if visibleAlbums.isEmpty && visibleTracks.isEmpty {
                emptyCategory("empty", symbol: "music.note")
            } else {
                if !visibleAlbums.isEmpty { albums }
                if !visibleTracks.isEmpty { songs }
            }
        }
    }
    private var albums: some View {
        VStack(alignment: .leading, spacing: 18) {
            ShelfSectionHeading(title: model.t("catalogCategory.albums"), count: albumCount(visibleAlbums.count))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 22, alignment: .top),
                                     count: typeSize.isAccessibilitySize ? 1 : 2), alignment: .leading, spacing: 26) {
                ForEach(visibleAlbums) { album in
                    Button { searching = false; model.openRadioAlbum(id: album.id) } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            ShelfAlbumSleeve(album: album, model: model).aspectRatio(1 / 0.88, contentMode: .fit)
                            Text(album.title).radioSerif(16).foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(shelfAlbumNumber(album, model: model) + " · " + model.albumTrackCount(album.tracks.count))
                                .radioMono(11).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("album." + album.id)
                        .accessibilityLabel(album.title + ", " + album.artist + ", " + model.albumTrackCount(album.tracks.count))
                }
            }
        }.accessibilityIdentifier("radioShelfAlbums")
    }
    private var songs: some View {
        VStack(alignment: .leading, spacing: 0) {
            ShelfSectionHeading(title: model.t(model.catalogCategory == .singles ? "catalogCategory.singles" : "radio.shelfTracks"),
                                count: model.albumTrackCount(visibleTracks.count)).padding(.bottom, 8)
            LazyVStack(spacing: 0) {
                ForEach(Array(visibleTracks.enumerated()), id: \.element.id) { index, track in
                    PlatformCatalogSongRow(model: model, track: track, number: index + 1)
                }
            }
        }.accessibilityIdentifier("radioShelfTracks")
    }
    private func albumCount(_ count: Int) -> String {
        String(format: model.t("radio.shelfAlbumCount"), locale: Locale(identifier: model.locale), count)
    }
    @ViewBuilder private func emptyCategory(_ key: String, symbol: String) -> some View {
        if !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView {
                Label(model.t("radio.shelfNoResults"), systemImage: "magnifyingglass")
            } description: { Text(model.t("radio.shelfNoResultsDetail")) }
        } else if !model.platformClassificationUnavailable {
            ContentUnavailableView { Label(model.t(key), systemImage: symbol) }
                description: { Text(model.t("catalogBrowseAll")) }
                actions: { Button(model.t("catalogCategory.all")) { model.catalogCategory = .all }.frame(minHeight: 44) }
        }
    }
}

private struct ShelfSectionHeading: View {
    let title: String
    let count: String
    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).radioSerif(22, weight: .black, relativeTo: .title2).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                Text(count).radioMono(11).foregroundStyle(Palette.muted)
            }.foregroundStyle(Palette.ink)
            Rectangle().fill(Palette.ink).frame(height: 2).accessibilityHidden(true)
        }
    }
}

@MainActor private func shelfAlbumNumber(_ album: PlatformAlbum, model: AppModel) -> String {
    let number = (model.platformAlbums.firstIndex { $0.id == album.id } ?? 0) + 1
    return String(format: "SC-LP-%02d", number)
}

private struct ShelfAlbumSleeve: View {
    let album: PlatformAlbum
    let model: AppModel
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let cover = width * 0.88
            ZStack(alignment: .topLeading) {
                RadioVinyl().frame(width: cover * 0.9, height: cover * 0.9)
                    .offset(x: cover * 0.18, y: cover * 0.05)
                PlatformAlbumArtwork(album: album, model: model)
                    .frame(width: cover, height: cover).clipShape(RoundedRectangle(cornerRadius: 4))
                    .shadow(color: Color(red: 0.16, green: 0.10, blue: 0.04).opacity(0.22), radius: 8, y: 8)
            }.frame(width: width, height: cover, alignment: .topLeading)
        }.accessibilityHidden(true)
    }
}

struct PlatformAlbumDetailView: View {
    @Bindable var model: AppModel
    let albumID: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var shareCard: PlatformShareCard?
    @State private var revealRecord = false
    private var album: PlatformAlbum? { model.platformAlbums.first { $0.id == albumID } }
    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let album {
                        hero(album)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(album.title).radioSerif(30, weight: .black, relativeTo: .title)
                                .foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
                            Text(album.artist + " · " + model.albumTrackCount(album.tracks.count))
                                .radioMono(12).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                            if !album.summary.isEmpty {
                                Text(album.summary).radioSerif(15, weight: .medium).lineSpacing(7)
                                    .foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if let failure = model.catalogFailure {
                            PlatformCatalogNotice(model: model, message: failure.messageKey, retained: true)
                        }
                        albumTracks(album).id("albumTracks")
                    } else {
                        ContentUnavailableView(model.t("catalogAlbumUnavailable"), systemImage: "square.stack")
                    }
                }.padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 24)
            }.background(Palette.background)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if let album, !album.tracks.isEmpty {
                        Button {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                                reader.scrollTo("albumTracks", anchor: .top)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Text(model.t("radio.albumChooseTrack")).font(.body.weight(.semibold))
                                Spacer(minLength: 8)
                                Image(systemName: "arrow.down")
                            }.foregroundStyle(.white).padding(.horizontal, 18).padding(.vertical, 14)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(Palette.accent, in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain).accessibilityIdentifier("radioAlbumChooseTrack")
                            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 12)
                            .background(Palette.background)
                            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
                    }
                }
                .navigationTitle("").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        if let album { Text(shelfAlbumNumber(album, model: model)).radioMono(11).foregroundStyle(Palette.muted) }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if model.catalogFailure == nil, let album, let card = PlatformShareCard.album(album, locale: model.locale) {
                            Button { shareCard = card } label: {
                                Image(systemName: "square.and.arrow.up").frame(minWidth: 44, minHeight: 44)
                            }.accessibilityLabel(model.t("shareMusic")).accessibilityIdentifier("platformAlbumShare")
                        }
                    }
                }
                .sheet(item: $shareCard) { card in
                    PlatformShareCardView(model: model, card: card,
                        isCurrent: model.catalogFailure == nil && album.flatMap { PlatformShareCard.album($0, locale: model.locale) } == card)
                }
                .refreshable { await model.load() }.accessibilityIdentifier("platformAlbumDetail")
        }
    }
    private func hero(_ album: PlatformAlbum) -> some View {
        GeometryReader { geometry in
            let side = min(220, geometry.size.width * 0.66)
            let left = max(18, (geometry.size.width - side) * 0.3)
            ZStack(alignment: .topLeading) {
                RadioVinyl().frame(width: side * 0.9, height: side * 0.9)
                    .rotationEffect(.degrees(revealRecord && !reduceMotion ? 200 : 0))
                    .offset(x: left + (revealRecord ? side * 0.44 : 12), y: (270 - side * 0.9) / 2)
                PlatformAlbumArtwork(album: album, model: model)
                    .frame(width: side, height: side).clipShape(RoundedRectangle(cornerRadius: 4))
                    .shadow(color: Color.black.opacity(0.25), radius: 14, y: 12)
                    .offset(x: left, y: (270 - side) / 2)
            }.frame(width: geometry.size.width, height: 270, alignment: .topLeading)
        }.frame(height: 270).background(Palette.dark, in: RoundedRectangle(cornerRadius: 18))
            .clipShape(RoundedRectangle(cornerRadius: 18)).accessibilityHidden(true)
            .onAppear {
                withAnimation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 1).delay(0.25)) {
                    revealRecord = true
                }
            }
    }
    private func albumTracks(_ album: PlatformAlbum) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.ink).frame(height: 2).accessibilityHidden(true)
            ForEach(Array(album.tracks.enumerated()), id: \.element.id) { index, track in
                Button { model.selectPlatformTrack(track) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(String(format: "%02d", index + 1)).radioMono(13, weight: .semibold)
                            .foregroundStyle(Palette.accent).frame(minWidth: 34, alignment: .leading)
                        if typeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(track.title).radioSerif(17).foregroundStyle(Palette.ink)
                                Text(model.t("radio.albumTrackDetail")).font(.caption).foregroundStyle(Palette.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(track.title).radioSerif(17).foregroundStyle(Palette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
                        }
                    }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 18)
                        .frame(minHeight: 62).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("track." + track.id)
                    .accessibilityLabel(track.title + ", " + model.t("radio.albumTrackDetail"))
                Rectangle().fill(Palette.line).frame(height: 1).accessibilityHidden(true)
            }
        }
    }
}

/// Album art is independent of its member songs. Its endpoint validates the
/// published album and version without relying on the share-card service.
struct PlatformAlbumArtwork: View {
    let album: PlatformAlbum
    let model: AppModel
    nonisolated static func coverURL(album: PlatformAlbum, locale: String, host: String?, mock: Bool) -> URL? {
        guard !mock, let url = PlatformShareCard.album(album, locale: locale)?.albumArtworkURL,
              let originHost = PlatformMusicAPI.productionOrigin.host, host == originHost,
              url.host == originHost else { return nil }
        return url
    }
    private var fixtureArtwork: String? {
        #if DEBUG && targetEnvironment(simulator)
        if model.scope.environment == .mock,
           ProcessInfo.processInfo.environment["STATION_PLATFORM_FIXTURE"] == "catalog-categories",
           let index = ["aaaaaaaa-0000-4000-8000-000000000001", "aaaaaaaa-0000-4000-8000-000000000002",
                        "aaaaaaaa-0000-4000-8000-000000000003", "aaaaaaaa-0000-4000-8000-000000000004"].firstIndex(of: album.id) {
            return "CatalogSample" + String(index + 1)
        }
        #endif
        return nil
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Palette.panel
                if let host = model.artworkHost,
                   let url = Self.coverURL(album: album, locale: model.locale, host: host,
                                           mock: model.scope.environment == .mock) {
                    CachedArtwork(url: url, host: host, loader: model.artwork, fill: true,
                                  retryGeneration: model.artworkRetryGeneration)
                } else if let fixtureArtwork {
                    Image(fixtureArtwork).resizable().scaledToFill()
                } else { Image(systemName: "music.note").foregroundStyle(Palette.muted) }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.accessibilityHidden(true)
    }
}

private struct PlatformCatalogSongRow: View {
    @Bindable var model: AppModel
    let track: Track
    var number: Int? = nil
    var body: some View {
        HStack(spacing: 10) {
            Button { model.selectPlatformTrack(track) } label: {
                HStack(spacing: 12) {
                    if let number {
                        Text(String(format: "%02d", number)).radioMono(11).foregroundStyle(Palette.muted)
                            .frame(width: 24, alignment: .leading)
                    }
                    OrbitArtwork(track: track, model: model, thumbnail: true)
                        .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 3))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(track.title).radioSerif(16).foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(track.release?.albums?.first?.title ?? track.artist)
                            .font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(minHeight: 64).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("track." + track.id)
            Button { Task { await model.toggleFavorite(track) } } label: {
                Image(systemName: model.favorites.contains(track.id) ? "heart.fill" : "heart")
                    .font(.system(size: 20)).foregroundStyle(model.favorites.contains(track.id) ? Palette.accent : Palette.muted)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(model.t("favorite") + " " + track.title)
                .accessibilityValue(model.t(model.favorites.contains(track.id) ? "on" : "off"))
                .accessibilityIdentifier("catalogFavorite." + track.id).disabled(model.libraryBusy)
        }.padding(.vertical, 2)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
    }
}

private struct PlatformCatalogNotice: View {
    @Bindable var model: AppModel
    let message: String
    let retained: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if retained { Label(model.t("refreshRetained"), systemImage: "exclamationmark.circle").font(.subheadline.weight(.medium)) }
            Text(model.t(message)).font(.subheadline).foregroundStyle(Palette.muted)
            Button(model.t("retry")) { Task { await model.load() } }.frame(minHeight: 44)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line))
            .accessibilityIdentifier(retained ? "catalogRefreshFailure" : "catalogClassificationUnavailable")
    }
}
