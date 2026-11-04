import SwiftUI

enum PlatformLibraryDestination { case privacy, preferences, help, legacy }

/// Local personal data remains separate from disposable artwork and remote works.
struct PlatformLibraryHome<Favorites: View, Settings: View>: View {
    @Bindable var model: AppModel
    @ViewBuilder var favorites: () -> Favorites
    @ViewBuilder var settings: (PlatformLibraryDestination) -> Settings
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("radioAppearance") private var appearance = "system"
    private let providers: [PlatformProvider] = [.netease, .qishui, .appleMusic, .spotify, .youtube]
    private var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return version + " (" + build + ")"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("LISTENER").radioMono(10, weight: .semibold).tracking(2).foregroundStyle(Palette.muted)
                    Text(model.t("library")).radioSerif(34, weight: .black, relativeTo: .largeTitle)
                        .padding(.vertical, -5).accessibilityAddTraits(.isHeader)
                }
                listenerCard
                favoritesShelf(model.platformFavorites)
                recentReceipt(model.platformVisits)
                preferredPlatforms
                settingsRows
                if model.personalError { PlatformPersonalError(model: model) }
            }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 28)
        }.background(Palette.background).foregroundStyle(Palette.ink)
            .navigationTitle("").toolbar(.hidden, for: .navigationBar).accessibilityIdentifier("libraryHome")
            .task { await model.refreshPersonal(); await model.refreshNotebook(); await model.refreshOffline() }
    }
    private var listenerCard: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 18) { listenerIdentity; statistics }
            } else {
                HStack(spacing: 18) {
                    listenerIdentity.frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(.clear).frame(width: 1)
                        .overlay { Path { path in path.move(to: .zero); path.addLine(to: CGPoint(x: 0, y: 88)) }.stroke(Palette.darkMuted.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4])) }
                        .frame(height: 88)
                    statistics.frame(minWidth: 62)
                }
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.dark, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityIdentifier("radioListenerCard")
    }
    private var listenerIdentity: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 12) {
                Image("OrbitBrand").resizable().scaledToFit().frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.t("radio.listenerCard")).radioSerif(17).foregroundStyle(Palette.darkText)
                    Text(model.t("radio.listenerLocal")).radioMono(10).foregroundStyle(Palette.darkMuted)
                }
            }
            Text(model.t("radio.listenerPrivacy")).font(.caption).lineSpacing(5).foregroundStyle(Palette.darkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var statistics: some View {
        VStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(model.favoriteCount.formatted()).radioSerif(24, weight: .black)
                    .padding(.vertical, -5).foregroundStyle(Palette.darkText)
                Text(model.t("favorites")).font(.caption).foregroundStyle(Palette.darkMuted)
            }
            Button { model.selectedTab = 2 } label: {
                VStack(spacing: 2) {
                    Text(model.notebookState.map { $0.notes.count.formatted() } ?? "—")
                        .radioSerif(24, weight: .black).padding(.vertical, -5).foregroundStyle(Palette.darkText)
                    Text(model.t("radio.notesCount")).font(.caption).foregroundStyle(Palette.darkMuted)
                }.frame(minWidth: 44, minHeight: 44)
            }.buttonStyle(.plain).accessibilityIdentifier("notebookEntry")
                .accessibilityLabel(model.t("notebookTitle"))
        }
    }
    private func favoritesShelf(_ rows: [PlatformFavoriteRow]) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(model.t("favorites")).radioSerif(22).accessibilityAddTraits(.isHeader)
                Spacer()
                NavigationLink(destination: favorites) {
                    Image(systemName: "arrow.right").frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(model.t("viewFavorites")).accessibilityIdentifier("favoritesEntry")
            }
            if rows.isEmpty {
                Text(model.t("radio.favoriteEmpty")).font(.subheadline).foregroundStyle(Palette.muted)
                    .padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(Array(rows.prefix(12))) { row in
                            Button { model.openPlatformFavorite(row) } label: {
                                VStack(alignment: .leading, spacing: 9) {
                                    Group {
                                        if let track = row.track { OrbitArtwork(track: track, model: model, thumbnail: true) }
                                        else {
                                            Rectangle().fill(Palette.panel).overlay { Image(systemName: "music.note").font(.title2).foregroundStyle(Palette.muted) }
                                        }
                                    }.frame(width: 112, height: 112).clipShape(RoundedRectangle(cornerRadius: 4))
                                        .shadow(color: Color(red: 0.16, green: 0.10, blue: 0.04).opacity(0.13), radius: 8, y: 6)
                                    Text(row.track?.title ?? row.bookmark?.title ?? model.t("favoritePlaceholder"))
                                        .radioSerif(15).foregroundStyle(Palette.ink).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                                    if row.track == nil {
                                        Text(model.t("favoriteAwaitingUpdate")).font(.caption2).foregroundStyle(Palette.muted)
                                    }
                                }.frame(width: 112, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("radio.favorite." + row.id)
                        }
                    }.padding(.bottom, 9)
                }
            }
        }
    }
    private func recentReceipt(_ rows: [PlatformVisitRow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.t("radio.recentReceipt")).radioSerif(20).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                NavigationLink { PlatformVisitsPage(model: model) } label: {
                    Text("RECENT").radioMono(10).foregroundStyle(Palette.muted).frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(.plain).accessibilityLabel(model.t("viewAll")).accessibilityIdentifier("viewedEntry")
            }
            PaperDash().stroke(Palette.muted, style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1)
            if rows.isEmpty {
                Text(model.t(model.personalState?.historyEnabled == false ? "viewingHistoryOff" : "noViewed"))
                    .font(.subheadline).foregroundStyle(Palette.muted).padding(.vertical, 12)
            } else {
                ForEach(Array(rows.prefix(3).enumerated()), id: \.element.id) { index, row in
                    Button { model.openPlatformVisit(row) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(row.track?.title ?? row.bookmark?.title ?? model.t("viewedPlaceholder"))
                                .radioSerif(15, weight: .medium).foregroundStyle(Palette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                            Text(receiptDate(row.visit.viewedAt)).radioMono(11).foregroundStyle(Palette.muted)
                        }.frame(minHeight: 48).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("viewed.track." + row.id)
                    if index < min(3, rows.count) - 1 {
                        PaperDash().stroke(Palette.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1)
                    }
                }
            }
        }.padding(18).background(Palette.panel, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Palette.line, lineWidth: 1))
    }
    private func receiptDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(.dateTime.hour().minute().locale(Locale(identifier: model.locale)))
        if calendar.isDateInToday(date) { return model.t("viewedToday") + " " + time }
        if calendar.isDateInYesterday(date) { return model.t("viewedYesterday") + " " + time }
        return date.formatted(.dateTime.month().day().locale(Locale(identifier: model.locale)))
    }
    private var preferredPlatforms: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.t("preferredPlatform")).radioSerif(22).accessibilityAddTraits(.isHeader)
            Text(model.t("radio.platformPreferenceIntro")).font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(4)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 230 : 145), alignment: .leading)], alignment: .leading, spacing: 8) {
                platformChip(nil)
                ForEach(providers, id: \.self) { platformChip($0) }
            }
        }
    }
    private func platformChip(_ provider: PlatformProvider?) -> some View {
        let selected = model.personalState != nil && model.preferredPlatform == provider
        return Button {
            let scope = model.scope
            Task {
                await model.setPreferredPlatform(provider)
                if model.scope == scope, model.personalState != nil, model.preferredPlatform == provider, !model.personalError {
                    model.showRadioToast(model.t("radio.platformPreferenceSaved"))
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: provider == nil ? "list.bullet" : "music.note")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 28, height: 28).background(providerColor(provider), in: Circle()).accessibilityHidden(true)
                Text(model.t(provider.map { "platform." + $0.rawValue } ?? "platformDefault"))
                    .font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.horizontal, 8).padding(.vertical, 5).frame(minHeight: 44)
                .background(selected ? Palette.panel : .clear, in: Capsule())
                .overlay(Capsule().stroke(selected ? Palette.ink : Palette.line, lineWidth: selected ? 1.5 : 1))
        }.buttonStyle(.plain).disabled(model.personalBusy || model.personalState == nil)
            .accessibilityValue(model.t(selected ? "on" : "off"))
            .accessibilityIdentifier("platformPreference." + (provider?.rawValue ?? "default"))
    }
    private func providerColor(_ provider: PlatformProvider?) -> Color {
        switch provider {
        case .netease: Color(red: 0.76, green: 0.05, blue: 0.05)
        case .qishui: Color(red: 0.18, green: 0.38, blue: 0.35)
        case .appleMusic: Color(red: 0.91, green: 0.20, blue: 0.30)
        case .spotify: Color(red: 0.09, green: 0.56, blue: 0.29)
        case .youtube: Color(red: 0.85, green: 0.11, blue: 0.11)
        case nil: Palette.muted
        }
    }
    private var settingsRows: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.ink).frame(height: 2)
            HStack {
                Text(model.t("radio.appearance"))
                Spacer()
                Picker(model.t("radio.appearance"), selection: $appearance) {
                    Text(model.t("radio.appearanceSystem")).tag("system")
                    Text(model.t("radio.appearancePaper")).tag("paper")
                    Text(model.t("radio.appearanceNight")).tag("night")
                }.labelsHidden().tint(Palette.muted).accessibilityIdentifier("radioAppearance")
            }.frame(minHeight: 56)
            Divider().overlay(Palette.line)
            Toggle(model.t("radio.saveViewingReceipt"), isOn: Binding(get: { model.personalState?.historyEnabled ?? false }, set: { value in Task { await model.setBrowsingHistory(value) } }))
                .disabled(model.personalBusy || model.personalState == nil).frame(minHeight: 56).tint(Palette.accent).accessibilityIdentifier("saveViewed")
            Divider().overlay(Palette.line)
            NavigationLink { settings(.preferences) } label: {
                settingLabel(model.t("language"), detail: languageName)
            }.accessibilityIdentifier("preferencesEntry")
            Divider().overlay(Palette.line)
            NavigationLink { settings(.privacy) } label: {
                settingLabel(model.t("radio.privacyLocalData"))
            }.accessibilityIdentifier("privacyEntry")
            Divider().overlay(Palette.line)
            NavigationLink { settings(.help) } label: {
                settingLabel(model.t("radio.aboutStationCat"), detail: version)
            }.accessibilityIdentifier("helpEntry")
            if model.hasLegacyPlatformData {
                Divider().overlay(Palette.line)
                NavigationLink { settings(.legacy) } label: { settingLabel(model.t("legacyData")) }
                    .accessibilityIdentifier("legacyDataEntry")
            }
        }.buttonStyle(.plain).font(.subheadline).foregroundStyle(Palette.ink)
    }
    private func settingLabel(_ title: String, detail: String? = nil) -> some View {
        HStack(spacing: 12) {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
            if let detail { Text(detail).font(.caption).foregroundStyle(Palette.muted).multilineTextAlignment(.trailing) }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
        }.frame(minHeight: 56).contentShape(Rectangle())
    }
    private var languageName: String {
        switch model.locale { case "zh-Hans": "简体中文"; case "zh-Hant": "繁體中文"; case "ja": "日本語"; default: "English" }
    }
}

private struct PaperDash: Shape {
    func path(in rect: CGRect) -> Path { Path { $0.move(to: CGPoint(x: rect.minX, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) } }
}

struct PlatformVisitButton: View {
    @Bindable var model: AppModel
    let row: PlatformVisitRow
    @Environment(\.dynamicTypeSize) private var typeSize
    private var date: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(row.visit.viewedAt) { return model.t("viewedToday") }
        if calendar.isDateInYesterday(row.visit.viewedAt) { return model.t("viewedYesterday") }
        return row.visit.viewedAt.formatted(.dateTime.month().day().locale(Locale(identifier: model.locale)))
    }
    var body: some View {
        Button { model.openPlatformVisit(row) } label: {
            HStack(spacing: 14) {
                if let track = row.track {
                    OrbitArtwork(track: track, model: model, thumbnail: true).frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                } else {
                    Image(systemName: "music.note").font(.title2).foregroundStyle(Palette.accent)
                        .frame(width: 52, height: 52).background(Palette.panel, in: RoundedRectangle(cornerRadius: 13))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(row.track?.title ?? row.bookmark?.title ?? model.t("viewedPlaceholder")).font(.headline).foregroundStyle(.primary)
                    Text(row.track?.artist ?? row.bookmark?.artist ?? model.t("viewedAwaitingUpdate"))
                        .font(.caption).foregroundStyle(Palette.muted)
                    if typeSize.isAccessibilitySize { Text(date).font(.caption).foregroundStyle(Palette.muted) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if !typeSize.isAccessibilitySize { Text(date).font(.caption).foregroundStyle(Palette.muted).fixedSize() }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
            }.padding(.vertical, 6).frame(minHeight: 64).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("viewed.track." + row.id)
    }
}

struct PlatformVisitsPage: View {
    @Bindable var model: AppModel
    @State private var confirmClear = false
    var body: some View {
        Form {
            Section {
                if model.platformVisits.isEmpty {
                    Label(model.t(model.personalState?.historyEnabled == false ? "viewingHistoryOff" : "noViewed"), systemImage: "clock")
                        .foregroundStyle(Palette.muted)
                }
                ForEach(model.platformVisits) { row in PlatformVisitButton(model: model, row: row) }
            }.listRowBackground(Palette.panel)
            Section {
                Toggle(model.t("saveViewed"), isOn: Binding(get: { model.personalState?.historyEnabled ?? false }, set: { value in Task { await model.setBrowsingHistory(value) } }))
                    .disabled(model.personalBusy || model.personalState == nil).accessibilityIdentifier("saveViewed")
                Button(model.t("clearViewed"), role: .destructive) { confirmClear = true }
                    .disabled(model.personalBusy || model.platformVisits.isEmpty).accessibilityIdentifier("clearViewed")
            } footer: { Text(model.t("viewingPrivacy")) }.listRowBackground(Palette.panel)
            if model.personalError { Section { PlatformPersonalError(model: model) }.listRowBackground(Palette.panel) }
        }.scrollContentBackground(.hidden).background { OrbitBackground() }
            .navigationTitle(model.t("recentlyViewed")).navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).accessibilityIdentifier("viewedPage")
            .alert(model.t("clearViewedConfirm"), isPresented: $confirmClear) {
                Button(model.t("clearViewed"), role: .destructive) { Task { await model.clearBrowsingHistory() } }
                Button(model.t("cancel"), role: .cancel) {}
            }
    }
}

struct PlatformPreferencePage: View {
    @Bindable var model: AppModel
    private let providers: [PlatformProvider] = [.netease, .qishui, .appleMusic, .spotify, .youtube]
    var body: some View {
        Form {
            Section {
                choice(nil)
                ForEach(providers, id: \.self) { choice($0) }
            } footer: { Text(model.t("platformPreferenceDetail")) }.listRowBackground(Palette.panel)
            if model.personalError { Section { PlatformPersonalError(model: model) }.listRowBackground(Palette.panel) }
        }.scrollContentBackground(.hidden).background { OrbitBackground() }
            .navigationTitle(model.t("preferredPlatform")).navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).accessibilityIdentifier("platformPreferencePage")
    }
    private func choice(_ provider: PlatformProvider?) -> some View {
        Button { Task { await model.setPreferredPlatform(provider) } } label: {
            HStack(spacing: 12) {
                Text(model.t(provider.map { "platform." + $0.rawValue } ?? "platformDefault")).foregroundStyle(.primary)
                Spacer()
                if model.personalState != nil, model.preferredPlatform == provider { Image(systemName: "checkmark").foregroundStyle(Palette.accent) }
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.disabled(model.personalBusy || model.personalState == nil)
            .accessibilityValue(model.t(model.personalState != nil && model.preferredPlatform == provider ? "on" : "off"))
            .accessibilityIdentifier("platformPreference." + (provider?.rawValue ?? "default"))
    }
}

struct PlatformPersonalError: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.t("personalSaveError"), systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(Palette.muted)
            Button(model.t("retry")) { Task { await model.refreshPersonal() } }.frame(minHeight: 44)
        }
    }
}
