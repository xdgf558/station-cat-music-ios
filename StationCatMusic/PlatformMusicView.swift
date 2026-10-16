import SwiftUI
import UIKit

/// Platform presentation deliberately has no audio, queue or playback controls.
struct PlatformMusicScreen: View {
    @Bindable var model: AppModel
    let discovery: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    private var tracks: [Track] { discovery ? model.discoveryTracks : model.results }
    private var phase: AppModel.Phase { discovery ? model.discoveryPhase : model.phase }
    private var failure: CatalogFailure? { discovery ? model.discoveryFailure : model.catalogFailure }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if discovery { brandHeader }
                if phase != .unavailable, let failure { refreshFailure(failure) }
                if discovery, let featured = tracks.first {
                    featuredCard(featured)
                    if tracks.count > 1 {
                        HStack {
                            Text(model.t("platformWorks")).font(.title3.weight(.semibold))
                            Spacer()
                            Button(model.t("viewAll")) { model.selectedTab = 1 }
                                .font(.subheadline).frame(minHeight: 44)
                        }
                        LazyVStack(spacing: 0) { ForEach(Array(tracks.dropFirst())) { track in songRow(track) } }
                    }
                } else {
                    listContent
                }
                if let notice = model.catalogNoticeKey {
                    Text(model.t(notice)).font(.caption).foregroundStyle(Palette.muted)
                }
            }.padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 30)
        }
        .background { OrbitBackground() }
        .accessibilityIdentifier(discovery ? "discoverScreen" : "catalogScreen")
        .navigationTitle(discovery ? "" : model.t("catalog"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(discovery ? .hidden : .visible, for: .navigationBar)
        .modifier(PlatformSearchModifier(model: model, enabled: !discovery))
    }
    private var brandHeader: some View {
        HStack(spacing: 12) {
            Image("OrbitBrand").resizable().scaledToFit().frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Station Cat Music").font(.system(.headline, design: .rounded))
                Text("Q U I E T   O R B I T").font(.system(size: 9, weight: .medium)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 4)
            OrbitIconButton(symbol: "magnifyingglass", label: model.t("search")) { model.selectedTab = 1 }
        }
    }
    private func featuredCard(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(model.t("platformDiscoverIntro")).font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(5)
            Button { model.selectPlatformTrack(track) } label: {
                OrbitArtwork(track: track, model: model).aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: typeSize.isAccessibilitySize ? 260 : 300)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.line, lineWidth: 1))
                    .shadow(color: Palette.accent.opacity(0.12), radius: 24, y: 12)
                    .frame(maxWidth: .infinity)
            }.buttonStyle(.plain).accessibilityIdentifier("track.\(track.id)")
                .accessibilityLabel(track.title + ", " + track.artist)
            VStack(alignment: .leading, spacing: 9) {
                Text(model.t(model.featuredTracks.first?.id == track.id ? "platformFeatured" : "platformWorks"))
                    .font(.caption.weight(.medium)).foregroundStyle(Palette.accent)
                Text(track.title).font(.title.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                Text(track.artist).font(.subheadline).foregroundStyle(Palette.muted)
                if let summary = track.release?.summary, !summary.isEmpty {
                    Text(summary).font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button { model.selectPlatformTrack(track) } label: {
                Label(model.t("platformListening"), systemImage: "arrow.up.right")
                    .font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(Palette.background).background(Palette.accent, in: Capsule())
            }.buttonStyle(.plain).accessibilityIdentifier("platformFeaturedOpen")
        }.padding(20).background(Palette.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(Palette.line, lineWidth: 1))
    }
    @ViewBuilder private var listContent: some View {
        switch phase {
        case .loading:
            ProgressView(model.t("loading")).frame(maxWidth: .infinity, minHeight: 160).accessibilityIdentifier("loading")
        case .unavailable:
            ContentUnavailableView { Label(model.t("unavailable"), systemImage: "wifi.slash") }
                description: { Text(model.t("unavailableDetail")) }
                actions: { Button(model.t("retry")) { Task { await model.load() } }.frame(minHeight: 44) }
        case .empty:
            ContentUnavailableView(model.t("empty"), systemImage: "music.note")
        case .loaded:
            if tracks.isEmpty {
                if !discovery, !model.query.isEmpty { ContentUnavailableView.search(text: model.query) }
                else { ContentUnavailableView(model.t("empty"), systemImage: "music.note") }
            } else {
                LazyVStack(spacing: 0) { ForEach(tracks) { track in songRow(track) } }
            }
        }
    }
    private func songRow(_ track: Track) -> some View {
        Button { model.selectPlatformTrack(track) } label: {
            HStack(spacing: 14) {
                OrbitArtwork(track: track, model: model, thumbnail: true).frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text(track.title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(track.artist).font(.caption).foregroundStyle(Palette.muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
            }.padding(.vertical, 15).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("track.\(track.id)")
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 0.5) }
    }
    private func refreshFailure(_ failure: CatalogFailure) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.t("refreshRetained"), systemImage: "exclamationmark.circle").font(.subheadline.weight(.semibold))
                .accessibilityIdentifier(discovery ? "discoveryRefreshFailure" : "catalogRefreshFailure")
            Text(model.t(failure.messageKey)).font(.caption).foregroundStyle(Palette.muted)
            Button(model.t("retry")) { Task { await model.load() } }.frame(minHeight: 44)
                .accessibilityIdentifier(discovery ? "discoveryRefreshFailure.retry" : "catalogRefreshFailure.retry")
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct PlatformSearchModifier: ViewModifier {
    @Bindable var model: AppModel
    let enabled: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(model.t("search")))
        } else { content }
    }
}

struct PlatformMusicDetailView: View {
    @Bindable var model: AppModel
    @Environment(\.openURL) private var openURL
    @State private var failedURL: URL?
    @State private var copied = false
    @State private var openOperation = 0
    private var currentDetail: PlatformTrackDetail? {
        guard model.platformDetail?.track.id == model.playback.selectedTrack?.id else { return nil }
        return model.platformDetail
    }
    private var track: Track? { currentDetail?.track ?? model.playback.selectedTrack }
    var body: some View {
        NavigationStack {
            ScrollView {
                if let track {
                    VStack(alignment: .leading, spacing: 24) {
                        OrbitArtwork(track: track, model: model).aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: 320).clipShape(RoundedRectangle(cornerRadius: 24))
                            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.line, lineWidth: 1))
                            .frame(maxWidth: .infinity)
                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 9) {
                                Text(track.title).font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                                Text(track.artist).font(.subheadline).foregroundStyle(Palette.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            OrbitIconButton(symbol: model.favorites.contains(track.id) ? "heart.fill" : "heart",
                                label: model.t("favorite") + " " + track.title, selected: model.favorites.contains(track.id)) {
                                Task { await model.toggleFavorite(track) }
                            }.accessibilityIdentifier("platformFavorite")
                                .accessibilityValue(model.t(model.favorites.contains(track.id) ? "on" : "off"))
                        }
                        if let summary = track.release?.summary, !summary.isEmpty {
                            Text(summary).font(.body).lineSpacing(6).foregroundStyle(Palette.muted)
                        }
                        if let detail = currentDetail, let release = detail.track.release {
                            platformLinks(release)
                            if !detail.story.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(model.t("platformWorkIntro")).font(.headline)
                                    Text(detail.story).font(.body).lineSpacing(7).foregroundStyle(Palette.muted)
                                }
                            }
                        } else if model.platformDetailFailure {
                            VStack(alignment: .leading, spacing: 12) {
                                Label(model.t(model.platformDetailFailureKey), systemImage: "exclamationmark.circle").foregroundStyle(Palette.muted)
                                    .accessibilityIdentifier("platformDetailFailure")
                                Button(model.t("retry")) { model.retryPlatformDetail() }.frame(minHeight: 44)
                                    .accessibilityIdentifier("platformDetailRetry")
                                if let url = track.release?.webURL {
                                    Button {
                                        UIPasteboard.general.url = url; copied = true
                                    } label: {
                                        Label(model.t(copied ? "platformCopied" : "platformCopyLink"), systemImage: copied ? "checkmark" : "link")
                                            .font(.subheadline).frame(minHeight: 44)
                                    }.accessibilityIdentifier("platformDetailCopyLink")
                                        .accessibilityValue(copied ? "copied" : "ready")
                                }
                            }
                        } else {
                            ProgressView(model.t("platformDetailLoading")).frame(maxWidth: .infinity, minHeight: 60)
                        }
                        if let failedURL { linkFailure(failedURL) }
                        if let release = track.release {
                            ShareLink(item: release.webURL) {
                                Label(model.t("shareMusic"), systemImage: "square.and.arrow.up")
                                    .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                            }.accessibilityIdentifier("platformShare")
                        }
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 18) {
                        if model.platformDetailFailure {
                            Label(model.t(model.platformDetailFailureKey), systemImage: "exclamationmark.circle")
                                .accessibilityIdentifier("platformDetailFailure")
                            Button(model.t("retry")) { model.retryPlatformDetail() }.frame(minHeight: 44)
                                .accessibilityIdentifier("platformDetailRetry")
                        } else { ProgressView(model.t("platformDetailLoading")) }
                    }.padding(24).frame(maxWidth: .infinity, minHeight: 240)
                }
            }.background { OrbitBackground() }.accessibilityIdentifier("platformDetailScreen")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        OrbitIconButton(symbol: "chevron.down", label: model.t("close")) { model.showPlayer = false }
                            .accessibilityIdentifier("platformDetailClose")
                    }
                    ToolbarItem(placement: .principal) {
                        Text("S T A T I O N   C A T").font(.caption2.weight(.medium)).foregroundStyle(Palette.muted)
                    }
                }
                .onChange(of: track?.id) { _, _ in invalidateOpen() }
                .onChange(of: currentDetail?.track.release) { _, _ in invalidateOpen() }
                .onChange(of: model.platformDetailGeneration) { _, _ in invalidateOpen() }
                .onChange(of: model.showPlayer) { _, presented in if !presented { invalidateOpen() } }
        }.preferredColorScheme(.dark).tint(Palette.accent)
            .onDisappear { invalidateOpen() }
    }
    @ViewBuilder private func platformLinks(_ release: PlatformTrackRelease) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(model.t("platformListening")).font(.headline)
            if release.platforms.isEmpty {
                Text(model.t(release.availability == "removed" ? "platformUnavailable" :
                    release.availability == "region_restricted" ? "platformRegionLimited" : "platformLinksPending"))
                    .font(.subheadline).foregroundStyle(Palette.muted)
                    .accessibilityIdentifier("platformLinksPending")
            } else {
                ForEach(release.platforms, id: \.id) { link in
                    Button { open(link.url) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "music.note").foregroundStyle(Palette.accent).accessibilityHidden(true)
                            Text(model.t("platform." + link.provider.rawValue)).font(.body.weight(.medium))
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right").font(.subheadline).foregroundStyle(Palette.muted)
                        }.padding(.horizontal, 18).padding(.vertical, 16)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line, lineWidth: 1))
                    }.buttonStyle(.plain).accessibilityIdentifier("platformLink." + link.provider.rawValue)
                }
            }
            if release.previewAvailable {
                Button { open(release.webURL) } label: {
                    Label(model.t("platformPreviewWebsite"), systemImage: "safari").font(.subheadline).frame(minHeight: 44)
                }.accessibilityIdentifier("platformPreviewWebsite")
            }
        }
    }
    private func open(_ url: URL) {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              let id = track?.id, let release = currentDetail?.track.release else { return }
        invalidateOpen()
        let ticket = openOperation, detailGeneration = model.platformDetailGeneration
        openURL(url) { accepted in
            guard ticket == openOperation, model.showPlayer, model.playback.selectedTrack?.id == id,
                  model.platformDetailGeneration == detailGeneration, currentDetail?.track.release == release else { return }
            if !accepted { failedURL = url }
        }
    }
    private func invalidateOpen() {
        openOperation += 1; failedURL = nil; copied = false
    }
    private func linkFailure(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(model.t("platformOpenFailure"), systemImage: "exclamationmark.circle").font(.subheadline)
                .accessibilityIdentifier("platformOpenFailure")
            Text(url.absoluteString).font(.caption).foregroundStyle(Palette.muted).textSelection(.enabled)
            Button {
                UIPasteboard.general.url = url; copied = true
            } label: {
                Label(model.t(copied ? "platformCopied" : "platformCopyLink"), systemImage: copied ? "checkmark" : "link")
                    .font(.subheadline).frame(minHeight: 44)
            }.accessibilityIdentifier("platformCopyLink").accessibilityValue(copied ? "copied" : "ready")
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 18))
    }
}
