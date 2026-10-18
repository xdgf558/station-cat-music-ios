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
        if discovery { discoveryContent }
        else { PlatformCatalogScreen(model: model) }
    }
    private var discoveryContent: some View {
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
