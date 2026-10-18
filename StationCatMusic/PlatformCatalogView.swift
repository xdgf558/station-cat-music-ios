import SwiftUI

struct PlatformCatalogScreen: View {
    @Bindable var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var searching: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 11) {
                    Image("OrbitBrand").resizable().scaledToFit().frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Station Cat Music").font(.system(.headline, design: .rounded))
                        Text("Q U I E T   O R B I T").font(.system(size: 9, weight: .medium)).foregroundStyle(Palette.muted)
                    }
                }.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                Text(model.t("catalog")).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                searchField
                categories
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
            }.padding(.horizontal, 22).padding(.top, 6).padding(.bottom, 24)
        }
        .background { OrbitBackground() }
        .toolbar(.hidden, for: .navigationBar)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await model.load() }
        .accessibilityIdentifier("catalogScreen")
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted).accessibilityHidden(true)
            TextField(model.t("catalogSearch"), text: $model.query, prompt: Text(model.t("catalogSearch")).foregroundStyle(Palette.muted))
                .font(.body).textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search).focused($searching).onSubmit { searching = false }
                .accessibilityIdentifier("catalogSearch")
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(model.t("catalogClearSearch"))
                    .accessibilityIdentifier("catalogClearSearch")
            }
        }.padding(.leading, 16).padding(.trailing, model.query.isEmpty ? 16 : 0)
            .frame(minHeight: 48).background(.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
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
                }.foregroundStyle(Palette.accent).padding(14).frame(maxWidth: .infinity, minHeight: 44)
                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
            }.accessibilityLabel(model.t("catalogCategories"))
                .accessibilityValue(model.t(model.catalogCategory.titleKey)).accessibilityIdentifier("catalogCategoryMenu")
        } else {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 28) {
                ForEach(PlatformCatalogCategory.allCases) { category in
                    Button { searching = false; model.catalogCategory = category } label: {
                        VStack(spacing: 9) {
                            Text(model.t(category.titleKey)).font(.headline).fixedSize()
                                .foregroundStyle(model.catalogCategory == category ? .white : Palette.muted)
                            Capsule().fill(model.catalogCategory == category ? Palette.accent : .clear).frame(height: 3)
                        }.padding(.horizontal, 4).frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("catalogCategory." + category.rawValue)
                        .accessibilityAddTraits(model.catalogCategory == category ? [.isSelected] : [])
                }
            }
        }.accessibilityElement(children: .contain).accessibilityLabel(model.t("catalogCategories"))
        }
    }
    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView(model.t("loading")).frame(maxWidth: .infinity, minHeight: 180)
        case .unavailable:
            ContentUnavailableView {
                Label(model.t("unavailable"), systemImage: "wifi.slash")
            } description: {
                Text(model.t(model.catalogFailure?.messageKey ?? "startupFailure"))
            } actions: { Button(model.t("retry")) { Task { await model.load() } }.frame(minHeight: 44) }
        case .empty:
            ContentUnavailableView(model.t("empty"), systemImage: "music.note")
        case .loaded:
            if model.catalogCategory == .albums { albums }
            else {
                if model.platformCatalogTracks.isEmpty { emptyCategory("catalogNoSingles", symbol: "music.note") }
                else {
                    sectionTitle(model.catalogCategory == .all ? "platformWorks" : "catalogCategory.singles")
                    LazyVStack(spacing: 0) {
                        ForEach(model.platformCatalogTracks) { track in PlatformCatalogSongRow(model: model, track: track) }
                    }
                }
            }
        }
    }
    private func sectionTitle(_ key: String) -> some View {
        Text(model.t(key)).font(.subheadline.weight(.medium)).foregroundStyle(Palette.accent).accessibilityAddTraits(.isHeader)
    }
    @ViewBuilder private var albums: some View {
        if model.platformCatalogAlbums.isEmpty { emptyCategory("catalogNoAlbums", symbol: "square.stack") }
        else {
            sectionTitle("catalogAlbumWorks")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: typeSize.isAccessibilitySize ? 1 : 2), alignment: .leading, spacing: 18) {
                ForEach(model.platformCatalogAlbums) { album in
                    NavigationLink { PlatformAlbumDetailView(model: model, albumID: album.id) } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            OrbitArtwork(track: album.tracks.first, model: model)
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line, lineWidth: 1))
                            Text(album.title).font(.headline).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                            Text(album.artist + " · " + model.albumTrackCount(album.tracks.count))
                                .font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("album." + album.id)
                        .accessibilityLabel(album.title + ", " + album.artist + ", " + model.albumTrackCount(album.tracks.count))
                }
            }
        }
    }
    @ViewBuilder private func emptyCategory(_ key: String, symbol: String) -> some View {
        if !model.query.isEmpty { ContentUnavailableView.search(text: model.query) }
        else if !model.platformClassificationUnavailable {
            ContentUnavailableView { Label(model.t(key), systemImage: symbol) }
                description: { Text(model.t("catalogBrowseAll")) }
                actions: { Button(model.t("catalogCategory.all")) { model.catalogCategory = .all }.frame(minHeight: 44) }
        }
    }
}

struct PlatformAlbumDetailView: View {
    @Bindable var model: AppModel
    let albumID: String
    private var album: PlatformAlbum? { model.platformAlbums.first { $0.id == albumID } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let album {
                    OrbitArtwork(track: album.tracks.first, model: model).aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: 280).clipShape(RoundedRectangle(cornerRadius: 20))
                        .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(album.title).font(.title.bold()).accessibilityAddTraits(.isHeader)
                        Text(album.artist).font(.subheadline).foregroundStyle(Palette.muted)
                        Text(model.albumTrackCount(album.tracks.count)).font(.caption).foregroundStyle(Palette.accent)
                        if !album.summary.isEmpty { Text(album.summary).font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(5) }
                    }
                    if let failure = model.catalogFailure { PlatformCatalogNotice(model: model, message: failure.messageKey, retained: true) }
                    LazyVStack(spacing: 0) {
                        ForEach(Array(album.tracks.enumerated()), id: \.element.id) { index, track in
                            PlatformCatalogSongRow(model: model, track: track, number: index + 1)
                        }
                    }
                } else {
                    ContentUnavailableView(model.t("catalogAlbumUnavailable"), systemImage: "square.stack")
                }
            }.padding(22)
        }.background { OrbitBackground() }.navigationTitle(model.t("catalogCategory.albums"))
            .navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .refreshable { await model.load() }.accessibilityIdentifier("platformAlbumDetail")
    }
}

private struct PlatformCatalogSongRow: View {
    @Bindable var model: AppModel
    let track: Track
    var number: Int? = nil
    var body: some View {
        Button { model.selectPlatformTrack(track) } label: {
            HStack(spacing: 12) {
                if let number { Text(number.formatted()).font(.caption.monospacedDigit()).foregroundStyle(Palette.muted).frame(minWidth: 18) }
                OrbitArtwork(track: track, model: model, thumbnail: true).frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 5) {
                    Text(track.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Text(track.artist).font(.caption).foregroundStyle(Palette.muted)
                }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.caption.weight(.medium)).foregroundStyle(Palette.muted)
            }.padding(.vertical, 14).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("track." + track.id)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 0.5) }
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
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityIdentifier(retained ? "catalogRefreshFailure" : "catalogClassificationUnavailable")
    }
}
