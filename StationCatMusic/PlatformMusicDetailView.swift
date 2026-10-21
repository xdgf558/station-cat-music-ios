import SwiftUI
import AVKit
import UIKit
import WebKit

struct PlatformMusicDetailView: View {
    @Bindable var model: AppModel
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var content = PlatformContentModel()
    @State private var video = PlatformClipPlayer()
    @State private var youtube = YouTubeClipSession.forCurrentEnvironment()
    @State private var section: Section = .lyrics
    @State private var expanded = false
    @AppStorage("platformLyricsFontSize") private var lyricSize = 18
    @ScaledMetric(relativeTo: .body) private var textScale = 1.0
    @State private var failedURL: URL?
    @State private var copied = false
    @State private var showYouTubeInfo = false
    @State private var openOperation = 0
    private enum Section: String, CaseIterable { case lyrics, clips, story
        var key: String { "contentTab." + rawValue }
    }
    private var currentDetail: PlatformTrackDetail? {
        guard model.platformDetail?.track.id == model.playback.selectedTrack?.id else { return nil }
        return model.platformDetail
    }
    private var track: Track? { currentDetail?.track ?? model.playback.selectedTrack }
    private var contentKey: String {
        "\(model.platformDetailGeneration)|\(model.locale)|\(currentDetail?.track.id ?? "")|\(model.showPlayer)"
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: section == .clips && !typeSize.isAccessibilitySize ? 12 : 28) {
                    if let track {
                        identity(track)
                        if let detail = currentDetail, let release = detail.track.release {
                            if section != .clips || typeSize.isAccessibilitySize { platformLinks(release) }
                            if let failedURL { linkFailure(failedURL) }
                            tabs
                            sectionBody(detail)
                            if section == .clips && !typeSize.isAccessibilitySize { platformLinks(release, placement: .remaining) }
                        } else { detailStatus }
                    } else { detailStatus }
                }.padding(.horizontal, 22).padding(.top, section == .clips && !typeSize.isAccessibilitySize ? 12 : 26).padding(.bottom, 36)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.background { OrbitBackground() }.accessibilityIdentifier("platformDetailScreen")
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if section == .clips, !typeSize.isAccessibilitySize, let release = currentDetail?.track.release, !release.platforms.isEmpty {
                        platformLinks(release, placement: .footer)
                            .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 8)
                            .background(Palette.background.opacity(0.96))
                    }
                }
                .sheet(isPresented: $showYouTubeInfo) {
                    NavigationStack {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                Text(model.t("youtubePrivacyNotice")).fixedSize(horizontal: false, vertical: true)
                                youtubePolicies
                            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                        }
                            .background(Palette.background).navigationTitle("YouTube")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .confirmationAction) {
                                Button(model.t("close")) { showYouTubeInfo = false }.accessibilityIdentifier("youtubePrivacyClose")
                            } }
                    }.presentationDetents([.medium, .large]).preferredColorScheme(.dark)
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        OrbitIconButton(symbol: "chevron.down", label: model.t("close")) { stopClips(); model.showPlayer = false }
                            .accessibilityIdentifier("platformDetailClose")
                    }
                    ToolbarItem(placement: .principal) {
                        Text("S T A T I O N   C A T").font(.caption2.weight(.medium)).foregroundStyle(Palette.muted)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if let url = track?.release?.webURL {
                            ShareLink(item: url) { Image(systemName: "square.and.arrow.up").frame(minWidth: 44, minHeight: 44) }
                                .accessibilityLabel(model.t("shareMusic")).accessibilityIdentifier("platformShare")
                        }
                    }
                }
                .task(id: contentKey) {
                    stopClips(); invalidateOpen(); section = .lyrics; expanded = false
                    content.configure(model.showPlayer ? currentDetail : nil, locale: model.locale, provider: model.platformCatalog)
                }
                .onChange(of: currentDetail?.track.release) { _, _ in invalidateOpen() }
                .onChange(of: section) { _, _ in stopClips() }
                .onChange(of: scenePhase) { _, phase in if phase != .active { stopClips() } }
        }.preferredColorScheme(.dark).tint(Palette.accent)
            .onDisappear { content.clear(); stopClips(); invalidateOpen() }
    }
    private func identity(_ track: Track) -> some View {
        ViewThatFits(in: .horizontal) {
            if !typeSize.isAccessibilitySize {
                HStack(alignment: .center, spacing: 18) {
                    artwork(track, side: section == .clips ? 104 : 140)
                    identityText(track).frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
                }
            }
            VStack(alignment: .leading, spacing: 18) { artwork(track, side: 120); identityText(track) }
        }
    }
    private func artwork(_ track: Track, side: CGFloat) -> some View {
        OrbitArtwork(track: track, model: model).frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line, lineWidth: 1))
    }
    private func identityText(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 4) {
                Text(track.title).font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                OrbitIconButton(symbol: model.favorites.contains(track.id) ? "heart.fill" : "heart",
                    label: model.t("favorite") + " " + track.title, selected: model.favorites.contains(track.id)) {
                    Task { await model.toggleFavorite(track) }
                }.accessibilityIdentifier("platformFavorite")
                    .accessibilityValue(model.t(model.favorites.contains(track.id) ? "on" : "off"))
            }
            Text(track.artist).font(.subheadline).foregroundStyle(Palette.muted)
            if let album = track.release?.albums?.first {
                Text(album.title).font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    @ViewBuilder private var tabs: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 0) {
                ForEach(Section.allCases, id: \.self) { tab in
                    Button { section = tab } label: {
                        HStack(spacing: 12) {
                            Text(model.t(tab.key)).font(.body.weight(section == tab ? .semibold : .regular))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            if section == tab { Image(systemName: "checkmark").font(.system(size: 20, weight: .semibold)).accessibilityHidden(true) }
                        }.padding(.vertical, 12).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .foregroundStyle(section == tab ? Palette.accent : Palette.muted).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("contentTab." + tab.rawValue)
                        .accessibilityAddTraits(section == tab ? .isSelected : [])
                    Divider().overlay(Palette.line)
                }
            }
        } else { HStack(spacing: 0) {
            ForEach(Section.allCases, id: \.self) { tab in
                Button { section = tab } label: {
                    VStack(spacing: 12) {
                        Text(model.t(tab.key)).font(.body.weight(section == tab ? .semibold : .regular))
                            .foregroundStyle(section == tab ? Palette.accent : Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Capsule().fill(section == tab ? Palette.accent : .clear).frame(height: 3).padding(.horizontal, 16)
                    }.padding(.top, 12).frame(maxWidth: .infinity, minHeight: 52).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("contentTab." + tab.rawValue)
                    .accessibilityAddTraits(section == tab ? .isSelected : [])
            }
        }.overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 0.5) } }
    }
    @ViewBuilder private func sectionBody(_ detail: PlatformTrackDetail) -> some View {
        switch section {
        case .lyrics: lyricReader
        case .clips: clipList(detail)
        case .story:
            if detail.story.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                empty("storyEmpty", icon: "text.book.closed")
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text(model.t("contentStoryTitle")).font(.headline)
                    Text(detail.story).font(.body).lineSpacing(9).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("contentStoryText")
                }
            }
        }
    }
    @ViewBuilder private var lyricReader: some View {
        switch content.lyricsPhase {
        case .loading: loading
        case .empty: empty("lyricsEmpty", icon: "text.alignleft")
        case .failed: retry(content.lyricsFailureKey, id: "lyricsRetry") { content.retryLyrics() }
        case .loaded:
            if let lyrics = content.lyrics {
                VStack(alignment: .leading, spacing: 28) {
                    HStack {
                        Label(model.t("contentLyricsTitle"), systemImage: "text.alignleft").font(.subheadline).foregroundStyle(Palette.muted)
                        Spacer()
                        Menu {
                            ForEach([18, 21, 24], id: \.self) { size in
                                Button { lyricSize = size } label: {
                                    Label(model.t("lyricSize.\(size)"), systemImage: lyricSize == size ? "checkmark" : "textformat.size")
                                }
                            }
                        } label: {
                            Text("Aa").font(.title3).frame(minWidth: 44, minHeight: 44)
                        }.accessibilityLabel(model.t("lyricTextSize")).accessibilityIdentifier("lyricTextSize")
                    }
                    VStack(alignment: .leading, spacing: 32) {
                        ForEach(Array(lyrics.stanzas.prefix(expanded ? lyrics.stanzas.count : 2).enumerated()), id: \.offset) { index, stanza in
                            Text(stanza).font(.system(size: CGFloat([18, 21, 24].contains(lyricSize) ? lyricSize : 18) * textScale))
                                .lineSpacing(14).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("lyricStanza.\(index)")
                        }
                    }
                    if lyrics.stanzas.count > 2 {
                        Button { expanded.toggle() } label: {
                            Label(model.t(expanded ? "lyricsCollapse" : "lyricsExpand"), systemImage: expanded ? "chevron.up" : "chevron.down")
                                .font(.subheadline).frame(minHeight: 44)
                        }.accessibilityIdentifier("lyricsExpand")
                    }
                }
            }
        }
    }
    @ViewBuilder private func clipList(_ detail: PlatformTrackDetail) -> some View {
        switch content.clipsPhase {
        case .loading: loading
        case .empty: empty("clipsEmpty", icon: "film")
        case .failed: retry(content.clipsFailureKey, id: "clipsRetry") { content.retryClips() }
        case .loaded:
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(model.t("selectedClips")).font(.headline)
                    Spacer()
                    if content.clips.contains(where: { $0.youtube != nil }) {
                        Button { stopClips(); showYouTubeInfo = true } label: {
                            Label("YouTube", systemImage: "info.circle").font(.caption.weight(.semibold))
                        }.frame(minHeight: 44).accessibilityLabel(model.t("youtubePrivacyInfo"))
                            .accessibilityIdentifier("youtubePrivacyInfo")
                    }
                }
                ForEach(content.clips) { clip in
                    VStack(alignment: .leading, spacing: 12) {
                        if clip.youtube != nil {
                            youtubeCard(clip, detail: detail)
                        } else if video.selectedID == clip.id, let player = video.player {
                            ForegroundClipView(player: player).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 16))
                            HStack {
                                Button { video.toggleMute() } label: {
                                    Label(model.t(video.muted ? "clipUnmute" : "clipMute"), systemImage: video.muted ? "speaker.slash" : "speaker.wave.2")
                                }.frame(minHeight: 44).accessibilityIdentifier("clipMute")
                                Spacer()
                                Button(model.t("clipStop")) { stopClips() }.frame(minHeight: 44)
                            }
                        } else if let poster = clip.posterURL {
                            Button { start(clip, detail: detail) } label: {
                                CachedArtwork(url: poster, host: PlatformMusicAPI.productionOrigin.host!, loader: model.artwork, fill: true)
                                    .aspectRatio(16 / 9, contentMode: .fit).clipped()
                                    .overlay { Image(systemName: "play.circle.fill").font(.system(size: 44)).symbolRenderingMode(.palette).foregroundStyle(.white, Palette.background.opacity(0.6)) }
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            }.buttonStyle(.plain).accessibilityLabel(model.t("clipWatch") + " " + clip.title)
                                .accessibilityIdentifier("clip." + clip.id)
                        }
                        if clip.youtube == nil { clipDescription(clip) }
                        if video.selectedID == clip.id, video.loading { loading }
                        if video.selectedID == clip.id, video.failed {
                            retry("clipPlayFailure", id: "clipRetry") { start(clip, detail: detail) }
                        }
                    }
                }
                if content.clips.contains(where: { $0.youtube == nil }) {
                    Text(model.t("clipMutedHint")).font(.caption).foregroundStyle(Palette.muted)
                }
            }
        }
    }
    private func stopClips() { video.stop(); youtube.stop() }
    private func startYouTube(_ clip: PlatformClip, detail: PlatformTrackDetail, externalOnly: Bool = false) {
        guard scenePhase == .active, model.showPlayer, let provider = model.platformCatalog else { return }
        video.stop()
        youtube.start(clip, track: detail.track, locale: model.locale, provider: provider, externalOnly: externalOnly) { url in open(url) }
    }
    @ViewBuilder private func youtubeCard(_ clip: PlatformClip, detail: PlatformTrackDetail) -> some View {
        let width: CGFloat = typeSize.isAccessibilitySize ? 220 : 200
        VStack(alignment: .leading, spacing: typeSize.isAccessibilitySize ? 12 : 8) {
            Group {
                if youtube.selectedID == clip.id, let view = youtube.webView {
                    YouTubeWebView(view: view)
                } else {
                    Button { startYouTube(clip, detail: detail) } label: {
                        ZStack {
                            OrbitArtwork(track: detail.track, model: model)
                            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                            VStack(spacing: 14) {
                                Image(systemName: "play.circle.fill").font(.system(size: 54)).foregroundStyle(.white)
                                Text(model.t("youtubeLoad")).font(.headline).foregroundStyle(.white)
                                Text(model.t("youtubeCoverHint")).font(.caption).foregroundStyle(.white.opacity(0.8))
                            }.padding(20)
                        }.frame(width: width, height: width * 1.5).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 14)).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(model.t("youtubeLoad") + " · " + clip.title)
                        .accessibilityIdentifier("youtubeLoad." + clip.id)
                }
            }.frame(width: width, height: width * 1.5).frame(maxWidth: .infinity)
            // The official iframe fits the complete video in this portrait viewport.
            // Do not crop it or place app-owned overlays over its controls/ads.
            if typeSize.isAccessibilitySize {
                clipDescription(clip)
            } else {
                Text(clip.title).font(.headline).fixedSize(horizontal: false, vertical: true)
            }
            if youtube.selectedID == clip.id, [.checking, .loading].contains(youtube.phase) {
                ProgressView(model.t("contentLoading")).accessibilityIdentifier("youtubeLoading")
            }
            if youtube.selectedID == clip.id, youtube.phase == .failed {
                retry(youtube.failureKey, id: "youtubeRetry") { startYouTube(clip, detail: detail) }
            }
            HStack {
                if !typeSize.isAccessibilitySize, !clip.summary.isEmpty {
                    Text(clip.summary).font(.caption).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                }
                Button { startYouTube(clip, detail: detail, externalOnly: true) } label: {
                    Label(model.t("youtubeOpen"), systemImage: "arrow.up.right").fixedSize(horizontal: false, vertical: true)
                }.frame(minHeight: 44).accessibilityIdentifier("youtubeOpen." + clip.id)
                Spacer(minLength: 8)
                if youtube.selectedID == clip.id, youtube.phase != .failed {
                    Button(model.t("clipStop")) { youtube.stop() }.frame(minHeight: 44).accessibilityIdentifier("youtubeStop")
                }
            }.font(.subheadline)
        }
    }
    private func clipDescription(_ clip: PlatformClip) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(clip.title).font(.headline).fixedSize(horizontal: false, vertical: true)
            if !clip.summary.isEmpty {
                Text(clip.summary).font(.subheadline).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    @ViewBuilder private var youtubePolicies: some View {
        Button(model.t("youtubeTerms")) { open(URL(string: "https://www.youtube.com/t/terms")!) }.frame(minHeight: 44).accessibilityIdentifier("youtubeTerms")
        Button(model.t("youtubePrivacy")) { open(URL(string: "https://policies.google.com/privacy")!) }.frame(minHeight: 44).accessibilityIdentifier("youtubePrivacy")
    }
    private func start(_ clip: PlatformClip, detail: PlatformTrackDetail) {
        guard scenePhase == .active, model.showPlayer, let provider = model.platformCatalog else { return }
        youtube.stop()
        video.play(clip, track: detail.track, locale: model.locale, provider: provider)
    }
    private var loading: some View {
        ProgressView(model.t("contentLoading")).frame(maxWidth: .infinity, minHeight: 100)
    }
    private func empty(_ key: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon).font(.title).foregroundStyle(Palette.accent)
            Text(model.t(key)).font(.body).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 24).frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier(key)
    }
    private func retry(_ key: String, id: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(model.t(key), systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(Palette.muted)
            Button(model.t("retry"), action: action).frame(minHeight: 44).accessibilityIdentifier(id)
        }
    }
    @ViewBuilder private var detailStatus: some View {
        if model.platformDetailFailure {
            VStack(alignment: .leading, spacing: 12) {
                Label(model.t(model.platformDetailFailureKey), systemImage: "exclamationmark.circle").foregroundStyle(Palette.muted)
                    .accessibilityIdentifier("platformDetailFailure")
                Button(model.t("retry")) { model.retryPlatformDetail() }.frame(minHeight: 44).accessibilityIdentifier("platformDetailRetry")
                if let url = track?.release?.webURL { copyButton(url, id: "platformDetailCopyLink") }
            }
        } else { ProgressView(model.t("platformDetailLoading")).frame(maxWidth: .infinity, minHeight: 120) }
    }
    private enum LinkPlacement { case all, footer, remaining }
    @ViewBuilder private func platformLinks(_ release: PlatformTrackRelease, placement: LinkPlacement = .all) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if release.platforms.isEmpty {
                Text(model.t(release.availability == "removed" ? "platformUnavailable" :
                    release.availability == "region_restricted" ? "platformRegionLimited" : "platformLinksPending"))
                    .font(.subheadline).foregroundStyle(Palette.muted).accessibilityIdentifier("platformLinksPending")
            } else {
                let links = model.orderedPlatformLinks(release.platforms)
                let visible = Array(links.enumerated()).filter { index, _ in
                    placement == .all || (placement == .footer ? index == 0 : index > 0)
                }
                ForEach(visible, id: \.element.id) { index, link in
                    Button { open(link.url) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "music.note").font(.system(size: 20)).frame(width: 24).accessibilityHidden(true)
                            Text(model.t("listenOnPlatform").replacingOccurrences(of: "{platform}", with: model.t("platform." + link.provider.rawValue)))
                                .font(.body.weight(index == 0 ? .semibold : .regular)).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right").font(.system(size: 17)).frame(width: 24).accessibilityHidden(true)
                        }.padding(.horizontal, 18).padding(.vertical, index == 0 ? 16 : 8)
                            .frame(maxWidth: .infinity, minHeight: index == 0 ? 54 : 44)
                            .foregroundStyle(index == 0 ? Palette.background : Palette.accent)
                            .background(index == 0 ? Palette.accent : .clear, in: RoundedRectangle(cornerRadius: 20))
                    }.buttonStyle(.plain).accessibilityIdentifier("platformLink." + link.provider.rawValue)
                }
                if placement != .footer, let preferred = model.preferredPlatform, !release.platforms.contains(where: { $0.provider == preferred }) {
                    Text(model.t("preferredPlatformMissing")).font(.caption).foregroundStyle(Palette.muted).accessibilityIdentifier("preferredPlatformMissing")
                }
            }
            if placement != .footer, release.previewAvailable {
                Button { open(release.webURL) } label: {
                    Label(model.t("platformPreviewWebsite"), systemImage: "safari").font(.subheadline).frame(minHeight: 44)
                }.accessibilityIdentifier("platformPreviewWebsite")
            }
        }
    }
    private func open(_ url: URL) {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              let id = track?.id, let release = currentDetail?.track.release else { return }
        stopClips(); invalidateOpen()
        let ticket = openOperation, detailGeneration = model.platformDetailGeneration
        openURL(url) { accepted in
            guard ticket == openOperation, model.showPlayer, model.playback.selectedTrack?.id == id,
                  model.platformDetailGeneration == detailGeneration, currentDetail?.track.release == release else { return }
            if !accepted { failedURL = url }
        }
    }
    private func invalidateOpen() { openOperation += 1; failedURL = nil; copied = false }
    private func copyButton(_ url: URL, id: String) -> some View {
        Button { UIPasteboard.general.url = url; copied = true } label: {
            Label(model.t(copied ? "platformCopied" : "platformCopyLink"), systemImage: copied ? "checkmark" : "link").frame(minHeight: 44)
        }.accessibilityIdentifier(id).accessibilityValue(copied ? "copied" : "ready")
    }
    private func linkFailure(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(model.t("platformOpenFailure"), systemImage: "exclamationmark.circle").font(.subheadline).accessibilityIdentifier("platformOpenFailure")
            Text(url.absoluteString).font(.caption).foregroundStyle(Palette.muted).textSelection(.enabled)
            copyButton(url, id: "platformCopyLink")
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Palette.panel, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct ForegroundClipView: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let view = AVPlayerViewController()
        view.allowsPictureInPicturePlayback = false; view.canStartPictureInPictureAutomaticallyFromInline = false
        view.updatesNowPlayingInfoCenter = false; view.player = player
        return view
    }
    func updateUIViewController(_ view: AVPlayerViewController, context: Context) { view.player = player }
    static func dismantleUIViewController(_ view: AVPlayerViewController, coordinator: ()) { view.player?.pause(); view.player = nil }
}

private struct YouTubeWebView: UIViewRepresentable {
    let view: WKWebView
    func makeUIView(context: Context) -> WKWebView { view }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
