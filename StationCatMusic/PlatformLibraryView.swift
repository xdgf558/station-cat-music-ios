import SwiftUI

/// The platform product's personal hub. All destinations remain native second-level pages.
struct PlatformLibraryHome<Favorites: View, Settings: View>: View {
    @Bindable var model: AppModel
    @ViewBuilder var favorites: () -> Favorites
    @ViewBuilder var settings: () -> Settings
    @Environment(\.dynamicTypeSize) private var typeSize
    private var covers: [Track] { Array(model.platformFavorites.compactMap(\.track).prefix(2)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image("OrbitBrand").resizable().scaledToFit().frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
                        Text("Station Cat Music").font(.subheadline).tracking(2).foregroundStyle(Palette.accent)
                    }
                    Text(model.t("library")).font(.largeTitle.weight(.bold)).accessibilityAddTraits(.isHeader)
                    Text(model.t("personalIntro")).font(.subheadline).foregroundStyle(Palette.muted)
                }
                NavigationLink(destination: favorites) { favoriteCard }
                    .buttonStyle(.plain).accessibilityIdentifier("favoritesEntry")
                    .accessibilityLabel(model.t("favorites") + ", " + model.albumTrackCount(model.favoriteCount))
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(model.t("recentlyViewed")).font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 8)
                        NavigationLink { PlatformVisitsPage(model: model) } label: {
                            HStack(spacing: 6) { Text(model.t("viewAll")); Image(systemName: "chevron.right") }
                                .font(.subheadline).frame(minHeight: 44)
                        }.accessibilityIdentifier("viewedEntry")
                    }
                    if model.platformVisits.isEmpty {
                        Label(model.t(model.personalState?.historyEnabled == false ? "viewingHistoryOff" : "noViewed"), systemImage: "clock")
                            .font(.subheadline).foregroundStyle(Palette.muted).padding(.vertical, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(Array(model.platformVisits.prefix(2).enumerated()), id: \.element.id) { index, row in
                            PlatformVisitButton(model: model, row: row)
                            if index == 0 && model.platformVisits.count > 1 { Divider().overlay(Palette.line).padding(.leading, 74) }
                        }
                    }
                }
                VStack(spacing: 0) {
                    NavigationLink { PlatformPreferencePage(model: model) } label: {
                        destinationRow("preferredPlatform", subtitle: model.preferredPlatform.map { "platform." + $0.rawValue } ?? "platformDefault", symbol: "music.note")
                    }.accessibilityIdentifier("platformPreferenceEntry")
                    Divider().overlay(Palette.line).padding(.leading, 62)
                    NavigationLink(destination: settings) {
                        destinationRow("settingsHelp", symbol: "gearshape")
                    }.accessibilityIdentifier("settingsHelpEntry")
                }.buttonStyle(.plain).background(Palette.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.line, lineWidth: 1))
                if model.personalError { PlatformPersonalError(model: model) }
            }.padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 28)
        }.background { OrbitBackground() }.navigationTitle("").toolbar(.hidden, for: .navigationBar)
            .accessibilityIdentifier("libraryHome")
            .task { await model.refreshPersonal(); await model.refreshOffline() }
    }
    private var favoriteCard: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "heart.fill").font(.system(size: 32)).foregroundStyle(Palette.accent)
                    .frame(width: 60, height: 60).background(Palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.t("favorites")).font(.title.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                    Text(model.albumTrackCount(model.favoriteCount)).font(.subheadline).foregroundStyle(Palette.muted)
                }
                HStack(spacing: 16) {
                    Text(model.t("viewFavorites")).font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }.foregroundStyle(Palette.accent).padding(.horizontal, 16).frame(minHeight: 44)
                    .background(Palette.accent.opacity(0.15), in: Capsule())
            }.frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1)
            if !typeSize.isAccessibilitySize, !covers.isEmpty {
                ZStack {
                    OrbitArtwork(track: covers.first, model: model, thumbnail: true)
                        .frame(width: 106, height: 128).clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.accent.opacity(0.4)))
                        .rotationEffect(.degrees(-7)).offset(x: covers.count > 1 ? -17 : 0, y: -23)
                    if covers.count > 1 {
                        OrbitArtwork(track: covers[1], model: model, thumbnail: true)
                            .frame(width: 96, height: 108).clipShape(RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.accent.opacity(0.4)))
                            .rotationEffect(.degrees(5)).offset(x: 18, y: 40)
                    }
                }.frame(width: 134, height: 172).accessibilityHidden(true)
            }
        }.padding(18).frame(maxWidth: .infinity, minHeight: 208, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 22).fill(Palette.panel)
                    .overlay {
                        RadialGradient(colors: [Palette.accent.opacity(0.32), .clear], center: .topTrailing, startRadius: 0, endRadius: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 22))
                    }
            }
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.accent.opacity(0.28), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 22))
    }
    private func destinationRow(_ title: String, subtitle: String? = nil, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(Palette.accent).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.t(title)).font(.headline)
                if let subtitle { Text(model.t(subtitle)).font(.caption).foregroundStyle(Palette.muted) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
        }.padding(16).frame(minHeight: 66).contentShape(Rectangle())
    }
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
