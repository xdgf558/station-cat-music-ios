import SwiftUI

private enum Palette {
    static let background = Color(red: 0.035, green: 0.07, blue: 0.085)
    static let panel = Color(red: 0.075, green: 0.12, blue: 0.14)
    static let gold = Color(red: 0.96, green: 0.76, blue: 0.44)
    static let muted = Color(red: 0.68, green: 0.74, blue: 0.75)
}
struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showDeletion = false
    @State private var confirmDeletion = false
    @State private var deletionPassword = ""
    @State private var deletionTotp = ""
    var body: some View {
        TabView(selection: $model.selectedTab) {
            NavigationStack { discover.safeAreaInset(edge: .bottom) { miniPlayer } }.tabItem { Label(model.t("discover"), systemImage: "sparkles") }.tag(0)
            NavigationStack { catalog.safeAreaInset(edge: .bottom) { miniPlayer } }.tabItem { Label(model.t("catalog"), systemImage: "music.note.list") }.tag(1)
            NavigationStack { library.safeAreaInset(edge: .bottom) { miniPlayer } }.tabItem { Label(model.t("library"), systemImage: "person.crop.circle") }.tag(2)
        }
        .tint(Palette.gold)
        .onOpenURL { url in Task { await model.openMusicLink(url) } }
        .alert(model.t("linkUnavailable"), isPresented: $model.linkUnavailable) { Button(model.t("close"), role: .cancel) {} }
        .sheet(isPresented: $model.showPlayer) { player }
        .task { await model.load(); await model.account.restore() }
        .onChange(of: model.playback.state) { _, state in
            if state == .verificationRequired && model.nativeMusic != nil { Task { await model.load() } }
        }
        .onChange(of: model.locale) { _, _ in if model.nativeMusic != nil { Task { await model.load() } } }
        .onChange(of: model.account.scope) { _, scope in Task { await model.changeScope(scope); await model.load() } }
        .sheet(isPresented: $showDeletion) { deletionSheet }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.playback.becameActive() } }
        .environment(\.locale, Locale(identifier: model.locale))
    }
    @ViewBuilder private var miniPlayer: some View {
            if let track = model.playback.selectedTrack {
                Button { model.showPlayer = true } label: {
                    HStack { Image(systemName: "music.note"); VStack(alignment: .leading) { Text(track.title).font(.headline); Text(model.t(model.playback.state == .playing ? "playing" : "notPlaying")).font(.caption).foregroundStyle(Palette.muted) }; Spacer(); Image(systemName: "chevron.up") }
                    .padding().background(Palette.panel, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal)
                }.buttonStyle(.plain).accessibilityIdentifier("miniPlayer")
            }
        }
    private var header: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout())
        return layout {
            HStack(spacing: 10) { Image(systemName: "cat.fill").font(.system(size: 24)).accessibilityHidden(true); Text("Station Cat").font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true) }.foregroundStyle(Palette.gold)
            if !typeSize.isAccessibilitySize { Spacer() }
            Text(model.t(model.nativeMusic == nil ? "mockBadge" : "isolatedMusic")).font(.caption).padding(.horizontal, 10).padding(.vertical, 7).background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var discover: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                VStack(alignment: .leading, spacing: 14) {
                    Text("GOOD MUSIC, A SLOWER DAY").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(Palette.gold)
                    Text(model.t("heroTitle")).font(.system(.largeTitle, design: .serif, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(model.t("heroSubtitle")).foregroundStyle(Palette.muted)
                    HStack {
                        Spacer(); Image(systemName: "moon.stars.fill").font(.system(size: 76)).foregroundStyle(Palette.gold.opacity(0.65)).accessibilityHidden(true)
                        Image(systemName: "cat.fill").font(.system(size: 90)).foregroundStyle(Palette.gold).accessibilityHidden(true)
                    }.padding(.vertical, 10)
                    Button { model.selectedTab = 1 } label: { Label(model.t("explore"), systemImage: "arrow.right").font(.headline).padding(.horizontal, 24).frame(minHeight: 48) }.buttonStyle(.borderedProminent).foregroundStyle(Palette.background)
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(LinearGradient(colors: [Palette.panel, Palette.background], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
                VStack(alignment: .leading, spacing: 6) { Text(model.t("tonight")).font(.title2.bold()); Text(model.t(model.nativeMusic == nil ? "mockOnly" : "isolatedMusic")).font(.caption).foregroundStyle(Palette.muted) }
                trackContent(phase: model.discoveryPhase, tracks: model.discoveryTracks, search: false)
            }.padding(20)
        }.background(Palette.background).toolbar(.hidden, for: .navigationBar)
    }
    private var catalog: some View {
        ScrollView { VStack(alignment: .leading, spacing: 20) {
            Text(model.t(model.nativeMusic == nil ? "mockExplanation" : "isolatedMusic")).font(.footnote).foregroundStyle(Palette.muted)
            if !model.collections.isEmpty {
                Menu {
                    Button(model.t("allTracks")) { model.activeCollection = nil }
                    ForEach(model.collections) { collection in Button(collection.title) { Task { await model.selectCollection(collection) } } }
                } label: { Label(model.activeCollection?.title ?? model.t("albums"), systemImage: "square.stack").frame(minHeight: 44) }
            }
            if let url = model.collectionShareURL { ShareLink(item: url) { Label(model.t("shareMusic"), systemImage: "square.and.arrow.up").frame(minHeight: 44) } }
            stateContent
        }.padding(20) }.background(Palette.background)
        .accessibilityIdentifier("catalogScreen")
        .navigationTitle(model.t("catalog")).searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(model.t("search")))
    }
    private var stateContent: some View { trackContent(phase: model.phase, tracks: model.results, search: true) }
    @ViewBuilder private func trackContent(phase: AppModel.Phase, tracks: [Track], search: Bool) -> some View {
        switch phase {
        case .loading: ProgressView(model.t("loading")).frame(maxWidth: .infinity, minHeight: 120).accessibilityIdentifier("loading")
        case .unavailable:
            ContentUnavailableView { Label(model.t("unavailable"), systemImage: "wifi.slash") } description: { Text(model.t("unavailableDetail")) } actions: { Button(model.t("retry")) { Task { await model.load() } }.frame(minHeight: 44) }
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
        HStack(spacing: 14) {
            Button { model.select(track, from: list) } label: {
                HStack(spacing: 14) {
                    if let url = track.coverUrl, url.scheme == "https", url.host == model.nativeMusic?.configuration.origin.host {
                        AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Image(systemName: "music.note") }.frame(width: 52, height: 60).clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
                    } else {
                    Image(systemName: "moon.stars").font(.title2).frame(width: 52, height: 60).background(Palette.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(Palette.gold).accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 5) { Text(track.title).font(.headline); Text(track.artist).font(.subheadline).foregroundStyle(Palette.muted); Text(model.t(model.nativeMusic == nil ? "sampleTrack" : "access." + track.access.rawValue)).font(.caption2).foregroundStyle(Palette.gold) }
                    Spacer(minLength: 0)
                }
            }.buttonStyle(.plain).accessibilityIdentifier("track.\(track.id)")
            Button { Task { await model.toggleFavorite(track) } } label: { Image(systemName: model.favorites.contains(track.id) ? "heart.fill" : "heart").frame(minWidth: 44, minHeight: 44) }.buttonStyle(.plain).foregroundStyle(Palette.gold).accessibilityLabel(model.t("favorite") + " " + track.title)
        }.padding(14).background(Palette.panel, in: RoundedRectangle(cornerRadius: 18))
    }
    private var library: some View {
        Form {
            Section {
                Label(model.t(model.account.scope.accountID == nil ? "guest" : "signedIn"), systemImage: "person.crop.circle").font(.headline)
                if model.account.enabled {
                    Text(model.t("isolatedAuth")).font(.footnote).foregroundStyle(Palette.muted)
                    if model.account.scope.accountID == nil {
                        Button(model.t("signIn")) { Task { await model.account.signIn(locale: model.locale) } }.disabled(model.account.busy)
                    } else {
                        Button(model.t("signOut")) { Task { await model.account.signOut() } }.disabled(model.account.busy)
                        Button(model.t("deleteAccount"), role: .destructive) { showDeletion = true }.disabled(model.account.busy)
                    }
                    Button(model.t("queryDeletion")) { Task { await model.account.queryDeletion() } }.disabled(model.account.busy)
                    if !model.account.deletionStatus.isEmpty { Text(model.t("deletion." + model.account.deletionStatus)).font(.footnote) }
                    if !model.account.messageKey.isEmpty { Text(model.t(model.account.messageKey)).font(.footnote).accessibilityIdentifier("authMessage") }
                } else {
                    Text(model.t("authNotReady")).font(.footnote).foregroundStyle(Palette.muted)
                }
            }
            Section(model.t("favorites")) {
                if model.favorites.isEmpty { Text(model.t("noFavorites")).foregroundStyle(Palette.muted) }
                let favoriteTracks = model.favoriteTracks
                ForEach(favoriteTracks) { track in Button(track.title) { model.select(track, from: favoriteTracks) }.frame(minHeight: 44) }
                Text(model.t("localSession")).font(.caption).foregroundStyle(Palette.muted)
            }
            Section(model.t("settings")) {
                Picker(model.t("language"), selection: $model.locale) { Text("简体中文").tag("zh-Hans"); Text("繁體中文").tag("zh-Hant"); Text("English").tag("en"); Text("日本語").tag("ja") }
                Text(model.t("mockExplanation")).font(.footnote)
            }
        }.scrollContentBackground(.hidden).background(Palette.background).navigationTitle(model.t("library"))
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
    private var player: some View {
        NavigationStack {
            ScrollView { VStack(spacing: 28) {
                Image(systemName: "opticaldisc.fill").font(.system(size: 150)).foregroundStyle(Palette.gold.opacity(0.8)).padding(.top, 28).accessibilityHidden(true)
                if let track = model.playback.selectedTrack { Text(track.title).font(.largeTitle.bold()).multilineTextAlignment(.center); Text(track.artist).foregroundStyle(Palette.muted) }
                if model.nativeMusic == nil {
                    Text(model.t("notPlaying")).font(.subheadline)
                    Text(model.t("playbackNotReady")).multilineTextAlignment(.center).foregroundStyle(Palette.muted).accessibilityIdentifier("playbackUnavailable")
                } else {
                    if let detail = model.detail {
                        if let url = detail.coverUrl, url.scheme == "https", url.host == model.nativeMusic?.configuration.origin.host {
                            AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() }.frame(maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                        Text(detail.summary).font(.footnote).foregroundStyle(Palette.muted)
                    }
                    if model.playback.state == .verificationRequired { Text(model.t("playbackDenied")).foregroundStyle(Palette.gold) }
                    if model.playback.state == .authorizing { ProgressView(model.t("loading")) }
                    HStack(spacing: 20) {
                        Button { model.adjacent(-1) } label: { Image(systemName: "backward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel(model.t("previous"))
                        Button {
                            model.playback.handle(.toggle)
                        } label: { Label(model.t(model.playback.state == .playing ? "pause" : "play"), systemImage: model.playback.state == .playing ? "pause.fill" : "play.fill").padding(12) }.buttonStyle(.borderedProminent).foregroundStyle(Palette.background)
                        Button { model.adjacent(1) } label: { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel(model.t("next"))
                    }
                    if let url = model.trackShareURL { ShareLink(item: url) { Label(model.t("shareMusic"), systemImage: "square.and.arrow.up").frame(minHeight: 44) } }
                    if let key = model.playback.noticeKey { Text(model.t(key)).font(.footnote).foregroundStyle(Palette.gold) }
                    let optionsLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout())
                    optionsLayout {
                        Button { model.playback.setShuffle(!model.playback.queue.shuffled) } label: { Image(systemName: "shuffle").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel(model.t("shuffle")).accessibilityValue(model.t(model.playback.queue.shuffled ? "on" : "off"))
                        Picker(model.t("repeat"), selection: Binding(get: { model.playback.queue.repeatMode }, set: { model.playback.setRepeat($0) })) {
                            ForEach(PlaybackQueue.RepeatMode.allCases, id: \.self) { Text(model.t("repeat." + $0.rawValue)).tag($0) }
                        }.pickerStyle(.menu)
                        Menu {
                            ForEach([15, 30, 60], id: \.self) { minutes in Button("\(minutes) " + model.t("minutes")) { model.playback.setSleepTimer(seconds: Double(minutes * 60)) } }
                            Button(model.t("off")) { model.playback.setSleepTimer(seconds: nil) }
                        } label: { Label(model.t("sleepTimer"), systemImage: model.playback.sleepDeadline == nil ? "moon" : "moon.fill").frame(minHeight: 44) }
                    }
                    DisclosureGroup(model.t("queue")) {
                        ForEach(model.playback.queue.orderedEntries) { entry in
                            HStack {
                                Button { model.playback.chooseQueueEntry(entry.id) } label: { Label(entry.track.title, systemImage: entry.id == model.playback.queue.currentID ? "speaker.wave.2" : "music.note").frame(minHeight: 44) }
                                Spacer()
                                if entry.id != model.playback.queue.currentID { Button { model.playback.removeQueueEntry(entry.id) } label: { Image(systemName: "minus.circle").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel(model.t("remove") + " " + entry.track.title) }
                            }
                        }
                        Button(model.t("clearQueue")) { model.playback.clear() }.frame(minHeight: 44)
                    }
                    if model.detail?.previewAvailable == true { Button(model.t("preview")) { model.playback.requestPlay(variant: "preview") }.frame(minHeight: 44) }
                    Slider(value: Binding(get: { model.playback.position }, set: { model.playback.seek(to: $0) }), in: 0...max(1, model.playback.duration)).disabled(![.playing, .paused, .completed].contains(model.playback.state)).accessibilityLabel(model.t("seek"))
                    if let lyrics = model.detail?.lyrics, lyrics.kind != "none" {
                        if lyrics.kind == "timed" {
                            ScrollViewReader { reader in
                                ScrollView { VStack(spacing: 20) {
                                    ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                                        Text(line.text).font(.title3).foregroundStyle(index == lyrics.current(at: model.playback.position + model.playback.previewOffset) ? Palette.gold : Palette.muted).id(index)
                                    }
                                }.frame(maxWidth: .infinity).padding(.vertical) }.frame(height: 240)
                                .onChange(of: lyrics.current(at: model.playback.position + model.playback.previewOffset)) { _, index in if let index { reader.scrollTo(index, anchor: .center) } }
                            }
                        } else { Text(lyrics.text).frame(maxWidth: .infinity, alignment: .leading) }
                    }
                }
            }.frame(maxWidth: .infinity).padding(24) }.background(Palette.background)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button { model.showPlayer = false } label: { Image(systemName: "chevron.down").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel(model.t("close")) }; ToolbarItem(placement: .principal) { Text("STATION CAT").font(.caption).tracking(3) } }
        }.preferredColorScheme(.dark)
    }
}
