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
    @State private var douyin = DouyinClipSession.forCurrentEnvironment()
    @State private var section: Section = .lyrics
    @State private var configuredContentKey: String?
    @State private var expanded = false
    @State private var selectedLyric: String?
    @State private var selectedLyricID: String?
    @State private var showPlatformPicker = false
    @State private var pickedLinkID: String?
    @State private var rememberPlatform = true
    @State private var applyingPlatform = false
    @State private var pickerGeneration = 0
    @State private var pickerScope = AccountScope.guest
    @State private var pendingPickedLink: PlatformLink?
    @State private var notebookSaved = false
    @AppStorage("platformLyricsFontSize") private var lyricSize = 18
    @ScaledMetric(relativeTo: .body) private var textScale = 1.0
    @State private var failedURL: URL?
    @State private var copied = false
    @State private var showYouTubeInfo = false
    @State private var showDouyinInfo = false
    @State private var listeningRequest: NetEaseListeningRequest?
    @State private var notebookEditor: PlatformNotebookEditorContext?
    @State private var notebookPendingWork: NotebookWork?
    @State private var preparingNotebook = false
    @State private var notebookEntryFailed = false
    @State private var shareCard: PlatformShareCard?
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
                VStack(alignment: .leading, spacing: 22) {
                    if let track {
                        identity(track)
                        if let detail = currentDetail {
                            if let failedURL { linkFailure(failedURL) }
                            tabs
                            sectionBody(detail)
                        } else { detailStatus }
                    } else { detailStatus }
                }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.background(Palette.background).accessibilityIdentifier("platformDetailScreen")
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    // Keep persistent controls compact like native toolbars;
                    // lyrics, stories and the scrollable content retain full AX scaling.
                    listeningFooter.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                }
                .sheet(isPresented: $showYouTubeInfo) {
                    NavigationStack {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                Text(model.t("youtubePrivacyNotice")).fixedSize(horizontal: false, vertical: true)
                                youtubePolicies
                            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                        }.background(Palette.background).navigationTitle("YouTube")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .confirmationAction) {
                                Button(model.t("close")) { showYouTubeInfo = false }.accessibilityIdentifier("youtubePrivacyClose")
                            } }
                    }.presentationDetents([.medium, .large])
                }
                .sheet(isPresented: $showDouyinInfo) {
                    NavigationStack {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                Text(model.t("douyinPrivacyNotice")).fixedSize(horizontal: false, vertical: true)
                                Button(model.t("douyinPrivacy")) { open(URL(string: "https://www.douyin.com/privacy/")!) }
                                    .frame(minHeight: 44).accessibilityIdentifier("douyinPrivacy")
                            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                        }.background(Palette.background).navigationTitle(model.t("douyinName"))
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .confirmationAction) {
                                Button(model.t("close")) { showDouyinInfo = false }.accessibilityIdentifier("douyinPrivacyClose")
                            } }
                    }.presentationDetents([.medium, .large])
                }
                .fullScreenCover(item: $notebookEditor, onDismiss: {
                    if notebookSaved {
                        notebookSaved = false; model.showPlayer = false; model.selectedTab = 2
                        model.showRadioToast(model.t("radio.noteSaved"))
                    } else if let work = notebookPendingWork {
                        notebookPendingWork = nil; model.openNotebookWork(work)
                    }
                }) { context in
                    PlatformNotebookEditor(model: model, context: context, onSaved: { notebookSaved = true }) { notebookPendingWork = $0 }
                }
                .sheet(isPresented: $showPlatformPicker, onDismiss: finishPlatformChoice) { platformPicker }
                .sheet(item: $listeningRequest) { request in
                    if let detail = currentDetail, let provider = model.platformCatalog {
                        NetEaseListeningView(request: request, track: detail.track, locale: model.locale,
                                             provider: provider, text: model.t)
                            .presentationDetents([.large])
                    }
                }
                .sheet(item: $shareCard) { card in
                    PlatformShareCardView(model: model, card: card,
                        isCurrent: currentDetail.flatMap { PlatformShareCard.track($0, locale: model.locale) } == card)
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        OrbitIconButton(symbol: "chevron.down", label: model.t("close")) { stopClips(); model.showPlayer = false }
                            .accessibilityIdentifier("platformDetailClose")
                    }
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 3) {
                            Text(track.flatMap { model.radioFrequency(for: $0) } ?? track.map { "SC–" + $0.id.prefix(6).uppercased() } ?? "STATION CAT")
                                .radioMono(12, weight: .semibold).foregroundStyle(Palette.accent)
                            Text("STATION CAT").radioMono(9).tracking(2).foregroundStyle(Palette.muted)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if let card = currentDetail.flatMap({ PlatformShareCard.track($0, locale: model.locale) }) {
                            Button { stopClips(); shareCard = card } label: { Image(systemName: "square.and.arrow.up").frame(minWidth: 44, minHeight: 44) }
                                .accessibilityLabel(model.t("shareMusic")).accessibilityIdentifier("platformShare")
                        }
                    }
                }
                .task(id: contentKey) {
                    stopClips(); invalidateOpen()
                    if configuredContentKey != contentKey {
                        configuredContentKey = contentKey
                        section = .lyrics; expanded = false; selectedLyric = nil; selectedLyricID = nil
                        showPlatformPicker = false; pendingPickedLink = nil
                    }
                    content.configure(model.showPlayer ? currentDetail : nil, locale: model.locale, provider: model.platformCatalog)
                    consumeRequestedPlatformPicker()
                }
                .onChange(of: model.radioWantsPlatformPicker) { _, _ in consumeRequestedPlatformPicker() }
                .onChange(of: model.platformDetailFailure) { _, failed in if failed { model.radioWantsPlatformPicker = false } }
                .onChange(of: currentDetail?.track.release) { _, _ in invalidateOpen() }
                .onChange(of: section) { _, _ in stopClips(); selectedLyric = nil; selectedLyricID = nil }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { stopClips(); pendingPickedLink = nil }
                }
        }.foregroundStyle(Palette.ink).tint(Palette.accent)
            .presentationBackground(Palette.background).presentationCornerRadius(34)
            .presentationDragIndicator(.visible)
            .onDisappear { content.clear(); stopClips(); invalidateOpen(); model.radioWantsPlatformPicker = false }
    }

    private var listeningFooter: some View {
        VStack(spacing: 9) {
            if let selectedLyric, section == .lyrics {
                Button { prepareNotebook(quote: selectedLyric) } label: {
                    HStack(spacing: 12) {
                        Text("「" + selectedLyric + "」").radioSerif(15, weight: .medium).lineLimit(1)
                            .foregroundStyle(Palette.darkText).frame(maxWidth: .infinity, alignment: .leading)
                        Text(model.t("radio.quoteToNote")).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.accent)
                        Image(systemName: "arrow.right").foregroundStyle(Palette.accent)
                    }.padding(.horizontal, 16).frame(minHeight: 48)
                        .background(Palette.dark, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain).disabled(preparingNotebook || model.notebookBusy)
                    .accessibilityIdentifier("lyricQuoteToNote")
            }
            HStack(alignment: .top, spacing: 10) {
                Button { prepareNotebook() } label: {
                    Group {
                        if preparingNotebook { ProgressView() }
                        else { Image(systemName: "pencil.line").font(.system(size: 21, weight: .medium)) }
                    }.frame(width: 52, height: 52).foregroundStyle(Palette.ink)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.ink, lineWidth: 1.5))
                }.buttonStyle(.plain).disabled(currentDetail == nil || preparingNotebook || model.notebookBusy)
                    .accessibilityLabel(model.t("notebookWriteForSong")).accessibilityIdentifier("notebookWriteForSong")
                VStack(spacing: 6) {
                    listenButton
                    Text(listenHint).font(.caption2).foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(missingPreferredPlatform ? "preferredPlatformMissing" : "radioListenHint")
                }.frame(maxWidth: .infinity)
            }
            if notebookEntryFailed {
                Text(model.t(model.notebookErrorKey ?? "notebookError")).font(.caption).foregroundStyle(Palette.muted)
                    .accessibilityIdentifier("notebookEntryError")
            }
        }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
            .background(Palette.background)
            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    private var preferredLink: PlatformLink? {
        currentDetail?.track.release.flatMap { model.orderedPlatformLinks($0.platforms).first }
    }
    private var missingPreferredPlatform: Bool {
        guard let preferred = model.preferredPlatform, let release = currentDetail?.track.release else { return false }
        return !release.platforms.contains { $0.provider == preferred }
    }
    private var listenHint: String {
        guard let release = currentDetail?.track.release else { return model.t("radio.listenVerification") }
        if let preferred = model.preferredPlatform, !release.platforms.contains(where: { $0.provider == preferred }) {
            return model.t("preferredPlatformMissing")
        }
        return model.t(model.preferredPlatform == nil ? "radio.listenDefaultHint" : "radio.listenPreferredHint")
    }
    private var listenButton: some View {
        HStack(spacing: 0) {
            if let link = preferredLink {
                Button { listen(link) } label: {
                    HStack(spacing: 6) {
                        Text(model.t("listenOnPlatform").replacingOccurrences(of: "{platform}", with: model.t("platform." + link.provider.rawValue)))
                            .font(.subheadline.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                        Image(systemName: inlineListening(link) ? "globe" : "arrow.up.right").font(.caption.weight(.bold))
                    }.padding(.horizontal, 13).padding(.vertical, 13).frame(maxWidth: .infinity, minHeight: 52)
                }.buttonStyle(.plain).accessibilityIdentifier("platformLink." + link.provider.rawValue)
                Rectangle().fill(.white.opacity(0.35)).frame(width: 1).padding(.vertical, 13)
                Button(action: beginPlatformChoice) {
                    Image(systemName: "chevron.down").font(.body.weight(.semibold)).frame(width: 50, height: 52)
                }.buttonStyle(.plain).accessibilityLabel(model.t("radio.choosePlatform")).accessibilityIdentifier("platformPickerOpen")
            } else {
                Text(model.t(currentDetail?.track.release?.availability == "unreleased" ? "radio.comingSoon" : "radio.listenPending"))
                    .font(.subheadline.weight(.bold)).foregroundStyle(Palette.background)
                    .frame(maxWidth: .infinity, minHeight: 52).accessibilityIdentifier("platformLinksPending")
            }
        }.foregroundStyle(.white).background(preferredLink == nil ? Palette.muted : Palette.accent, in: RoundedRectangle(cornerRadius: 14))
            .fixedSize(horizontal: false, vertical: true)
    }
    private func prepareNotebook(quote: String? = nil) {
        guard let track = currentDetail?.track, quote.map({ $0.utf16.count <= 200 && !$0.contains("\n") && !$0.contains("\r") }) ?? true,
              !preparingNotebook, !model.notebookBusy else { return }
        stopClips(); preparingNotebook = true; notebookEntryFailed = false; notebookSaved = false
        let scope = model.scope, generation = model.platformDetailGeneration, epoch = model.notebookState?.epoch
        Task {
            await model.refreshNotebook()
            preparingNotebook = false
            guard model.scope == scope, model.platformDetailGeneration == generation,
                  model.showPlayer, currentDetail?.track.id == track.id,
                  quote == nil || (section == .lyrics && selectedLyric == quote) else { return }
            guard let state = model.notebookState, epoch == nil || epoch == state.epoch, let slug = track.release?.slug else {
                notebookEntryFailed = true; return
            }
            notebookEditor = .init(work: .init(id: track.id, slug: slug), quote: quote, state: state, scope: scope)
        }
    }
    private func identity(_ track: Track) -> some View {
        ViewThatFits(in: .horizontal) {
            if !typeSize.isAccessibilitySize {
                HStack(alignment: .center, spacing: 18) {
                    artwork(track, side: 96)
                    identityText(track).frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                }
            }
            VStack(alignment: .leading, spacing: 16) { artwork(track, side: 96); identityText(track) }
        }
    }
    private func artwork(_ track: Track, side: CGFloat) -> some View {
        OrbitArtwork(track: track, model: model).frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: Color(red: 0.16, green: 0.10, blue: 0.04).opacity(0.18), radius: 10, y: 8)
    }
    private func identityText(_ track: Track) -> some View {
        HStack(alignment: .center, spacing: 4) {
            VStack(alignment: .leading, spacing: 7) {
                Text(track.title).radioSerif(25, weight: .heavy, relativeTo: .title2)
                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                Text(track.artist).font(.subheadline).foregroundStyle(Palette.muted)
                if let album = track.release?.albums?.first {
                    Button { stopClips(); model.openRadioAlbum(id: album.id) } label: {
                        Text(album.title).font(.subheadline).underline().foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true).frame(minHeight: 44, alignment: .leading)
                    }.buttonStyle(.plain).accessibilityIdentifier("platformDetailAlbum")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            OrbitIconButton(symbol: model.favorites.contains(track.id) ? "heart.fill" : "heart",
                label: model.t("favorite") + " " + track.title, selected: model.favorites.contains(track.id)) {
                Task { await model.toggleFavorite(track) }
            }.accessibilityIdentifier("platformFavorite")
                .accessibilityValue(model.t(model.favorites.contains(track.id) ? "on" : "off"))
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
                            .foregroundStyle(section == tab ? Palette.ink : Palette.muted).contentShape(Rectangle())
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
                            .foregroundStyle(section == tab ? Palette.ink : Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Rectangle().fill(section == tab ? Palette.accent : .clear).frame(height: 2)
                    }.padding(.top, 12).frame(maxWidth: .infinity, minHeight: 52).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("contentTab." + tab.rawValue)
                    .accessibilityAddTraits(section == tab ? .isSelected : [])
            }
        }.overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 0.5) } }
    }
    @ViewBuilder private func sectionBody(_ detail: PlatformTrackDetail) -> some View {
        switch section {
        case .lyrics: lyricReader
        case .clips:
            VStack(alignment: .leading, spacing: 14) {
                Text(model.t("radio.clipPrivacy")).font(.caption).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.muted, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                clipList(detail)
            }
        case .story:
            if detail.story.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                empty("storyEmpty", icon: "text.book.closed")
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text(model.t("radio.creativeNotes")).radioMono(10, weight: .semibold).tracking(2).foregroundStyle(Palette.muted)
                    Text(detail.story).radioSerif(17, weight: .medium).lineSpacing(13).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("contentStoryText")
                }
            }
        }
    }
    @ViewBuilder private var lyricReader: some View {
        switch content.lyricsPhase {
        case .loading: loading
        case .empty:
            VStack(alignment: .leading, spacing: 10) {
                Text(model.t("radio.lyricsOnTheWay")).radioSerif(20)
                Text(model.t("radio.lyricsEmptyHint")).font(.subheadline).foregroundStyle(Palette.muted)
            }.padding(.vertical, 24).accessibilityIdentifier("lyricsEmpty")
        case .failed: retry(content.lyricsFailureKey, id: "lyricsRetry") { content.retryLyrics() }
        case .loaded:
            if let lyrics = content.lyrics {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text(model.t("radio.tapLyric")).font(.caption).foregroundStyle(Palette.muted)
                        Spacer()
                        Menu {
                            ForEach([18, 21, 24], id: \.self) { size in
                                Button { lyricSize = size } label: {
                                    Label(model.t("lyricSize.\(size)"), systemImage: lyricSize == size ? "checkmark" : "textformat.size")
                                }
                            }
                        } label: { Text("Aa").radioSerif(18).frame(minWidth: 44, minHeight: 44) }
                            .accessibilityLabel(model.t("lyricTextSize")).accessibilityIdentifier("lyricTextSize")
                    }
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(Array(lyrics.stanzas.prefix(expanded ? lyrics.stanzas.count : 2).enumerated()), id: \.offset) { index, stanza in
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(stanza.components(separatedBy: "\n").enumerated()), id: \.offset) { lineIndex, line in
                                    lyricLine(line, stanza: index, index: lineIndex)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityElement(children: .contain).accessibilityIdentifier("lyricStanza.\(index)")
                        }
                    }
                    if lyrics.stanzas.count > 2 {
                        Button { expanded.toggle(); selectedLyric = nil; selectedLyricID = nil } label: {
                            Label(model.t(expanded ? "lyricsCollapse" : "lyricsExpand"), systemImage: expanded ? "chevron.up" : "chevron.down")
                                .font(.subheadline).frame(minHeight: 44)
                        }.accessibilityIdentifier("lyricsExpand")
                    }
                }
            }
        }
    }
    private func lyricLine(_ line: String, stanza: Int, index: Int) -> some View {
        let lineID = "\(stanza).\(index)"
        return Button {
            if selectedLyricID == lineID { selectedLyric = nil; selectedLyricID = nil }
            else { selectedLyric = line; selectedLyricID = lineID }
        } label: {
            Text(line).font(Font(RadioTypography.serif(size: CGFloat([18, 21, 24].contains(lyricSize) ? lyricSize : 18) * textScale, weight: .medium)))
                .lineSpacing(10).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 5).padding(.vertical, 7).frame(minHeight: 44, alignment: .leading)
                .foregroundStyle(selectedLyricID == lineID ? .white : selectedLyric == nil ? Palette.ink : Palette.muted)
                .background(selectedLyricID == lineID ? Palette.accent : .clear, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).disabled(line.utf16.count > 200)
            .accessibilityIdentifier("lyricLine.\(stanza).\(index)")
            .accessibilityAddTraits(selectedLyricID == lineID ? .isSelected : [])
            .accessibilityHint(model.t(line.utf16.count > 200 ? "radio.quoteTooLong" : "radio.tapLyric"))
            .accessibilityAction(named: model.t("radio.quoteToNote")) {
                if line.utf16.count <= 200 { selectedLyric = line; selectedLyricID = lineID; prepareNotebook(quote: line) }
            }
    }
    @ViewBuilder private func clipList(_ detail: PlatformTrackDetail) -> some View {
        switch content.clipsPhase {
        case .loading: loading
        case .empty: empty("clipsEmpty", icon: "film")
        case .failed: retry(content.clipsFailureKey, id: "clipsRetry") { content.retryClips() }
        case .loaded:
            VStack(alignment: .leading, spacing: 14) {
                (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())) {
                    Text(model.t("selectedClips")).font(.headline)
                    if !typeSize.isAccessibilitySize { Spacer() }
                    if content.clips.contains(where: { $0.douyin != nil }) {
                        Button { stopClips(); showDouyinInfo = true } label: {
                            Label(model.t("douyinName"), systemImage: "info.circle").font(.caption.weight(.semibold))
                        }.frame(minHeight: 44).accessibilityLabel(model.t("douyinPrivacyInfo"))
                            .accessibilityIdentifier("douyinPrivacyInfo")
                    }
                    if content.clips.contains(where: { $0.youtube != nil }) {
                        Button { stopClips(); showYouTubeInfo = true } label: {
                            Label("YouTube", systemImage: "info.circle").font(.caption.weight(.semibold))
                        }.frame(minHeight: 44).accessibilityLabel(model.t("youtubePrivacyInfo"))
                            .accessibilityIdentifier("youtubePrivacyInfo")
                    }
                }
                ForEach(content.clips) { clip in
                    VStack(alignment: .leading, spacing: 12) {
                        if clip.douyin != nil {
                            douyinCard(clip, detail: detail)
                        } else if clip.youtube != nil {
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
                        if clip.youtube == nil && clip.douyin == nil { clipDescription(clip) }
                        if video.selectedID == clip.id, video.loading { loading }
                        if video.selectedID == clip.id, video.failed {
                            retry("clipPlayFailure", id: "clipRetry") { start(clip, detail: detail) }
                        }
                    }
                }
                if content.clips.contains(where: { $0.mediaURL != nil }) {
                    Text(model.t("clipMutedHint")).font(.caption).foregroundStyle(Palette.muted)
                }
            }
        }
    }
    private func stopClips() { video.stop(); youtube.stop(); douyin.stop() }
    private func startYouTube(_ clip: PlatformClip, detail: PlatformTrackDetail, externalOnly: Bool = false) {
        guard scenePhase == .active, model.showPlayer, let provider = model.platformCatalog else { return }
        video.stop(); douyin.stop()
        youtube.start(clip, track: detail.track, locale: model.locale, provider: provider, externalOnly: externalOnly) { url in open(url) }
    }
    @ViewBuilder private func youtubeCard(_ clip: PlatformClip, detail: PlatformTrackDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if youtube.selectedID == clip.id, let view = youtube.webView {
                // Preserve the complete official portrait viewport without overlays on controls or ads.
                OfficialClipWebView(view: view).frame(width: 220, height: 330).frame(maxWidth: .infinity)
            } else {
                clipPreview(clip, track: detail.track, provider: "YOUTUBE", loadKey: "youtubeLoad") { startYouTube(clip, detail: detail) }
            }
            clipDescription(clip)
            if youtube.selectedID == clip.id, [.checking, .loading].contains(youtube.phase) {
                ProgressView(model.t("contentLoading")).accessibilityIdentifier("youtubeLoading")
            }
            if youtube.selectedID == clip.id, youtube.phase == .failed {
                retry(youtube.failureKey, id: "youtubeRetry") { startYouTube(clip, detail: detail) }
            }
            HStack {
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
    private func startDouyin(_ clip: PlatformClip, detail: PlatformTrackDetail, externalOnly: Bool = false) {
        guard scenePhase == .active, model.showPlayer, let provider = model.platformCatalog else { return }
        video.stop(); youtube.stop()
        douyin.start(clip, track: detail.track, locale: model.locale, provider: provider, externalOnly: externalOnly) { url in open(url) }
    }
    @ViewBuilder private func douyinCard(_ clip: PlatformClip, detail: PlatformTrackDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if douyin.selectedID == clip.id, let view = douyin.webView {
                // Preserve the complete official portrait viewport without overlays on controls or ads.
                OfficialClipWebView(view: view).frame(width: 220, height: 330).frame(maxWidth: .infinity)
            } else {
                clipPreview(clip, track: detail.track, provider: model.t("douyinName"), loadKey: "douyinLoad") { startDouyin(clip, detail: detail) }
            }
            clipDescription(clip)
            if douyin.selectedID == clip.id, [.checking, .loading].contains(douyin.phase) {
                ProgressView(model.t("contentLoading")).accessibilityIdentifier("douyinLoading")
            }
            if douyin.selectedID == clip.id, douyin.phase == .failed {
                retry(douyin.failureKey, id: "douyinRetry") { startDouyin(clip, detail: detail) }
            }
            if douyin.selectedID == clip.id, douyin.phase == .loaded {
                Text(model.t("douyinPlayerHint")).font(.caption).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("douyinPlayerHint")
            }
            HStack {
                Button { startDouyin(clip, detail: detail, externalOnly: true) } label: {
                    Label(model.t("douyinOpen"), systemImage: "arrow.up.right").fixedSize(horizontal: false, vertical: true)
                }.frame(minHeight: 44).accessibilityIdentifier("douyinOpen." + clip.id)
                Spacer(minLength: 8)
                if douyin.selectedID == clip.id, douyin.phase != .failed {
                    Button(model.t("clipStop")) { douyin.stop() }.frame(minHeight: 44).accessibilityIdentifier("douyinStop")
                }
            }.font(.subheadline)
        }
    }
    private func clipPreview(_ clip: PlatformClip, track: Track, provider: String, loadKey: String, load: @escaping () -> Void) -> some View {
        Button(action: load) {
            ZStack {
                OrbitArtwork(track: track, model: model).blur(radius: 6)
                Color.black.opacity(0.45)
                Image(systemName: "play.circle.fill").font(.system(size: 54)).foregroundStyle(.white)
                VStack {
                    HStack {
                        Text(provider).radioMono(10, weight: .semibold).padding(.horizontal, 9).padding(.vertical, 5)
                            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 5))
                        Spacer()
                    }
                    Spacer()
                    HStack { Spacer(); Text(model.t("radio.tapToLoad")).font(.caption.weight(.semibold)) }
                }.foregroundStyle(.white).padding(12)
            }.aspectRatio(16.0 / 9, contentMode: .fit).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(model.t(loadKey) + " · " + clip.title)
            .accessibilityIdentifier(loadKey + "." + clip.id)
    }
    private func clipDescription(_ clip: PlatformClip) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(clip.title).radioSerif(17).fixedSize(horizontal: false, vertical: true)
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
        youtube.stop(); douyin.stop()
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
    private func consumeRequestedPlatformPicker() {
        guard model.radioWantsPlatformPicker, currentDetail != nil, model.showPlayer else { return }
        model.radioWantsPlatformPicker = false; beginPlatformChoice()
    }
    private var pickerProviders: [PlatformProvider] {
        let available = currentDetail?.track.release.map { model.orderedPlatformLinks($0.platforms).map(\.provider) } ?? []
        let ordered = available + PlatformProvider.allCases.filter { !available.contains($0) }
        return ordered.reduce(into: []) { result, provider in if !result.contains(provider) { result.append(provider) } }
    }
    private func beginPlatformChoice() {
        guard currentDetail != nil else { return }
        stopClips(); pickerGeneration = model.platformDetailGeneration; pickerScope = model.scope
        pickedLinkID = preferredLink?.id; rememberPlatform = true; pendingPickedLink = nil; showPlatformPicker = true
    }
    private var platformPicker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.t("radio.whereListen")).radioSerif(23, weight: .heavy)
                        if let track { Text("《" + track.title + "》").font(.subheadline).foregroundStyle(Palette.muted) }
                    }
                    Spacer()
                    Button { showPlatformPicker = false } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel(model.t("close")).accessibilityIdentifier("platformPickerClose")
                }
                VStack(spacing: 3) {
                    ForEach(pickerProviders, id: \.self) { provider in platformChoice(provider) }
                }
                if let release = currentDetail?.track.release, release.previewAvailable {
                    Button { showPlatformPicker = false; open(release.webURL) } label: {
                        Label(model.t("platformPreviewWebsite"), systemImage: "safari").frame(minHeight: 44)
                    }.accessibilityIdentifier("platformPreviewWebsite")
                }
                Button { rememberPlatform.toggle() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: rememberPlatform ? "checkmark.square.fill" : "square")
                            .font(.system(size: 23)).foregroundStyle(Palette.ink)
                        Text(model.t("radio.rememberPlatform")).font(.subheadline).foregroundStyle(Palette.ink)
                    }.frame(minHeight: 44)
                }.buttonStyle(.plain).accessibilityIdentifier("platformPickerRemember")
                    .accessibilityValue(model.t(rememberPlatform ? "on" : "off"))
                if model.personalError { Text(model.t("personalSaveError")).font(.caption).foregroundStyle(Palette.muted) }
                Button(action: applyPlatformChoice) {
                    HStack(spacing: 8) {
                        if applyingPlatform { ProgressView().tint(.white) }
                        Text(pickedLink.map { model.t("listenOnPlatform").replacingOccurrences(of: "{platform}", with: model.t("platform." + $0.provider.rawValue)) } ?? model.t("radio.choosePlatform"))
                            .font(.body.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "arrow.up.right")
                    }.foregroundStyle(.white).padding(.horizontal, 15).padding(.vertical, 14)
                        .frame(maxWidth: .infinity, minHeight: 52).background(Palette.accent, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain).disabled(pickedLink == nil || applyingPlatform || scenePhase != .active)
                    .opacity(pickedLink == nil ? 0.45 : 1).accessibilityIdentifier("platformPickerConfirm")
            }.padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 20)
        }.background(Palette.background).foregroundStyle(Palette.ink)
            .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(610), .large])
            .presentationDragIndicator(.visible).presentationCornerRadius(30)
            .accessibilityIdentifier("platformPicker")
    }
    private var pickedLink: PlatformLink? { currentDetail?.track.release?.platforms.first { $0.id == pickedLinkID } }
    private func platformChoice(_ provider: PlatformProvider) -> some View {
        let link = currentDetail?.track.release?.platforms.first { $0.provider == provider }
        let selected = link != nil && link?.id == pickedLinkID
        return Button { pickedLinkID = link?.id } label: {
            HStack(spacing: 12) {
                RadioDetailPlatformIcon(provider: provider).opacity(link == nil ? 0.4 : 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.t("platform." + provider.rawValue)).font(.body.weight(.medium))
                    Text(model.t(link == nil ? "radio.platformNotListed" : model.preferredPlatform == provider ? "radio.platformAvailablePreferred" : "radio.platformAvailable"))
                        .font(.caption).foregroundStyle(Palette.muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(link == nil ? Palette.muted : Palette.ink)
                Image(systemName: selected ? "record.circle" : "circle").font(.system(size: 23))
                    .foregroundStyle(selected ? Palette.accent : Palette.line)
            }.padding(.horizontal, 12).padding(.vertical, 10).frame(minHeight: 60)
                .background(selected ? Palette.panel : .clear, in: RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(link == nil || applyingPlatform)
            .accessibilityIdentifier("platformPicker." + provider.rawValue)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func applyPlatformChoice() {
        guard let link = pickedLink, !applyingPlatform, pickerGeneration == model.platformDetailGeneration,
              pickerScope == model.scope, model.showPlayer, scenePhase == .active else { return }
        applyingPlatform = true
        let generation = pickerGeneration, scope = pickerScope
        Task {
            if rememberPlatform { await model.setPreferredPlatform(link.provider) }
            applyingPlatform = false
            guard model.showPlayer, scenePhase == .active, scope == model.scope,
                  generation == model.platformDetailGeneration,
                  currentDetail?.track.release?.platforms.contains(link) == true else { return }
            pendingPickedLink = link; showPlatformPicker = false
        }
    }
    private func finishPlatformChoice() {
        guard let link = pendingPickedLink else { return }
        pendingPickedLink = nil
        guard model.showPlayer, scenePhase == .active, pickerScope == model.scope,
              pickerGeneration == model.platformDetailGeneration,
              currentDetail?.track.release?.platforms.contains(link) == true else { return }
        listen(link)
    }
    private func inlineListening(_ link: PlatformLink) -> Bool {
        guard ExperimentalListeningConfiguration.enabledForCurrentEnvironment(), let track = currentDetail?.track else { return false }
        return NetEaseListeningRequest(link: link, track: track) != nil
    }
    private func listen(_ link: PlatformLink) {
        if inlineListening(link), let track = currentDetail?.track,
           let request = NetEaseListeningRequest(link: link, track: track) {
            stopClips(); invalidateOpen(); listeningRequest = request
        } else { open(link.url) }
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
    private func invalidateOpen() { openOperation += 1; failedURL = nil; copied = false; listeningRequest = nil }
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

private struct OfficialClipWebView: UIViewRepresentable {
    let view: WKWebView
    func makeUIView(context: Context) -> WKWebView { view }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

private struct RadioDetailPlatformIcon: View {
    let provider: PlatformProvider
    private var symbol: String {
        switch provider {
        case .netease: "music.note"
        case .qishui: "waveform"
        case .appleMusic: "apple.logo"
        case .youtube: "play.rectangle.fill"
        case .spotify: "dot.radiowaves.left.and.right"
        }
    }
    private var color: Color {
        switch provider {
        case .netease: Color(red: 0.76, green: 0.05, blue: 0.05)
        case .qishui: Color(red: 0.13, green: 0.54, blue: 0.38)
        case .appleMusic: Color(red: 0.91, green: 0.20, blue: 0.29)
        case .youtube: Color(red: 0.85, green: 0.11, blue: 0.11)
        case .spotify: Color(red: 0.09, green: 0.56, blue: 0.29)
        }
    }
    var body: some View {
        Image(systemName: symbol).font(.system(size: 19, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 34, height: 34).background(color, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
    }
}
