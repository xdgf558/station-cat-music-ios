import SwiftUI

/// A radio-shaped catalog navigator, with no native audio or broadcast schedule.
struct PlatformMusicScreen: View {
    @Bindable var model: AppModel
    let discovery: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frequency = RadioDial.frequencies[0]
    @State private var dragStart: Double?
    private var stations: [Track] { model.radioTracks }
    private var index: Int { RadioDial.nearest(frequency, count: stations.count) ?? 0 }
    private var track: Track? { stations.indices.contains(index) ? stations[index] : nil }

    var body: some View {
        if discovery { radio }
        else { PlatformCatalogScreen(model: model) }
    }
    private var radio: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                Text(model.t("radio.headline")).radioSerif(34, weight: .black, relativeTo: .largeTitle)
                    .lineSpacing(-5).padding(.vertical, -5)
                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                if model.discoveryPhase != .unavailable, let failure = model.discoveryFailure { refreshFailure(failure) }
                if let track {
                    sleeve(track)
                    identity(track)
                    dial.padding(.horizontal, -20)
                    listening(track)
                    program
                } else { emptyState }
                albums
                if let note = model.notebookState?.notes.first {
                    VStack(spacing: 16) {
                        RadioSectionHeader(title: model.t("radio.inNotebook"), trailing: model.t("radio.allNotes")) { model.selectedTab = 2 }
                        Button { model.radioNoteID = note.id; model.selectedTab = 2 } label: {
                            PlatformNotebookRow(model: model, note: note)
                        }.buttonStyle(.plain).accessibilityIdentifier("radioLatestNote")
                    }
                }
                if let notice = model.catalogNoticeKey { Text(model.t(notice)).font(.caption).foregroundStyle(Palette.muted) }
            }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 28)
                .frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
        }.background { OrbitBackground() }.toolbar(.hidden, for: .navigationBar)
            .refreshable { await model.load() }.accessibilityIdentifier("discoverScreen")
            .onChange(of: stations.map(\.id)) { _, _ in
                dragStart = nil
                frequency = RadioDial.frequencies[min(index, max(0, stations.count - 1))]
            }
    }
    private var header: some View {
        HStack(spacing: 12) {
            Image("OrbitBrand").resizable().scaledToFit().frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                RadioEyebrow(title: "STATION CAT · FM")
                Text(Date.now.formatted(.dateTime.month().day().weekday(.abbreviated).locale(Locale(identifier: model.locale))))
                    .font(.subheadline.weight(.medium))
            }
            Spacer(minLength: 4)
            OrbitIconButton(symbol: "magnifyingglass", label: model.t("search")) {
                model.radioSearchRequest += 1; model.selectedTab = 1
            }.overlay(Circle().stroke(Palette.line, lineWidth: 1)).accessibilityIdentifier("radioSearch")
        }
    }
    private func sleeve(_ track: Track) -> some View {
        GeometryReader { geometry in
            let side = min(typeSize.isAccessibilitySize ? 240.0 : 280.0, max(160, geometry.size.width - 64))
            ZStack(alignment: .leading) {
                RadioVinyl().frame(width: side * 0.9, height: side * 0.9)
                    .rotationEffect(.degrees(reduceMotion ? 0 : frequency * 8))
                    .offset(x: dragStart != nil && !reduceMotion ? 22 : side * 0.26)
                Button { model.selectPlatformTrack(track) } label: {
                    OrbitArtwork(track: track, model: model).frame(width: side, height: side)
                        .grayscale(dragStart == nil ? 0 : 0.8).blur(radius: dragStart != nil && !reduceMotion ? 2 : 0)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(color: Color(red: 0.16, green: 0.10, blue: 0.04).opacity(0.25), radius: 15, y: 10)
                }.buttonStyle(.plain).accessibilityLabel(track.title + ", " + track.artist).accessibilityIdentifier("track." + track.id)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }.frame(height: typeSize.isAccessibilitySize ? 240 : 280)
            .animation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.6), value: dragStart == nil)
    }
    private func identity(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(String(format: "FM %.1f", frequency)).radioMono(13, weight: .semibold, relativeTo: .caption)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(Palette.accent).fixedSize()
                if !typeSize.isAccessibilitySize {
                    Text(model.t(dragStart == nil ? "radio.selectedWork" : "radio.tuning")).font(.caption).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
                dialStep(-1); dialStep(1)
            }
            if typeSize.isAccessibilitySize {
                Text(model.t(dragStart == nil ? "radio.selectedWork" : "radio.tuning")).font(.caption).foregroundStyle(Palette.muted)
            }
            Button { model.selectPlatformTrack(track) } label: {
                Text(track.title).radioSerif(30, weight: .black, relativeTo: .title).foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }.buttonStyle(.plain)
            Text(track.release.flatMap { $0.summary.isEmpty ? nil : $0.summary } ?? track.artist)
                .font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func dialStep(_ direction: Int) -> some View {
        Button { tune(by: direction) } label: {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right").font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 44).overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1))
        }.buttonStyle(.plain).disabled(stations.count < 2).opacity(stations.count < 2 ? 0.4 : 1)
            .accessibilityLabel(model.t(direction < 0 ? "radio.previous" : "radio.next"))
            .accessibilityIdentifier(direction < 0 ? "radioPrevious" : "radioNext")
    }
    private var dial: some View {
        VStack(spacing: 10) {
            RadioScale(frequency: frequency, stations: Array(RadioDial.frequencies.prefix(stations.count)))
                .frame(height: 92).background(Palette.panel)
                .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
                .contentShape(Rectangle()).gesture(RadioDialDrag(enabled: stations.count > 1, onChanged: { translation in
                    if dragStart == nil { dragStart = frequency }
                    frequency = RadioDial.dragged(from: dragStart ?? frequency, translation: translation)
                }, onEnded: {
                    guard dragStart != nil else { return }
                    let next = index; dragStart = nil; setStation(next)
                }))
                .accessibilityElement(children: .ignore).accessibilityLabel(model.t("radio.dial"))
                .accessibilityValue(String(format: "FM %.1f", frequency) + ", " + (track?.title ?? ""))
                .accessibilityAdjustableAction { action in
                    switch action { case .increment: tune(by: 1); case .decrement: tune(by: -1); @unknown default: break }
                }.accessibilityIdentifier("radioDial").sensoryFeedback(.selection, trigger: index)
            Text(model.t("radio.dragHint")).radioMono(10, relativeTo: .caption).tracking(1).foregroundStyle(Palette.muted)
        }
    }
    private func setStation(_ next: Int) {
        withAnimation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.45)) { frequency = RadioDial.frequencies[next] }
    }
    private func tune(by delta: Int) {
        if let next = RadioDial.adjacent(index, by: delta, count: stations.count) { setStation(next) }
    }
    private func listening(_ track: Track) -> some View {
        VStack(spacing: 10) {
            Button { model.selectPlatformTrack(track, showPlatforms: true) } label: {
                HStack {
                    Text(model.t("radio.chooseListening")); Spacer(); Image(systemName: "arrow.up.right")
                    Rectangle().fill(.white.opacity(0.35)).frame(width: 1, height: 24).padding(.horizontal, 8)
                    Image(systemName: "chevron.down")
                }.font(.subheadline.weight(.bold)).foregroundStyle(.white).padding(.horizontal, 18)
                    .frame(minHeight: 54).background(Palette.accent, in: RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain).accessibilityIdentifier("platformFeaturedOpen")
            Text(model.t("radio.listeningHint")).font(.caption).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
        }
    }
    private var program: some View {
        VStack(spacing: 0) {
            RadioSectionHeader(title: model.t("radio.program"), trailing: "PROGRAM")
            ForEach(Array(stations.enumerated()), id: \.element.id) { position, song in
                Button { setStation(position) } label: {
                    (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 14))) {
                        Text(String(format: "%02d", position + 1)).radioMono(13, weight: .semibold, relativeTo: .caption)
                            .foregroundStyle(position == index ? Palette.accent : Palette.muted).frame(width: 32)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(song.title).radioSerif(17).foregroundStyle(Palette.ink)
                            Text(song.artist).font(.caption).foregroundStyle(Palette.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Circle().fill(position == index ? Palette.accent : Palette.line).frame(width: 6, height: 6)
                        Text(String(format: "%.1f", RadioDial.frequencies[position])).radioMono(11, relativeTo: .caption).foregroundStyle(Palette.muted)
                    }.padding(.vertical, 14).frame(minHeight: 64).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("radioStation." + song.id)
                    .accessibilityAddTraits(position == index ? .isSelected : [])
                    .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
            }
            Text(model.t("radio.visualFrequency")).font(.caption).foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
        }
    }
    @ViewBuilder private var albums: some View {
        if !model.platformAlbums.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                RadioSectionHeader(title: model.t("radio.newRecords"), trailing: model.t("radio.toShelf")) {
                    model.catalogCategory = .albums; model.selectedTab = 1
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 20) {
                        ForEach(model.platformAlbums) { album in
                            Button { model.openRadioAlbum(id: album.id) } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    PlatformAlbumArtwork(album: album, model: model).frame(width: 136, height: 136).clipShape(RoundedRectangle(cornerRadius: 4))
                                    Text(album.title).radioSerif(15).foregroundStyle(Palette.ink).lineLimit(2)
                                    Text(model.albumTrackCount(album.tracks.count)).radioMono(10, relativeTo: .caption).foregroundStyle(Palette.muted)
                                }.frame(width: 136, alignment: .leading)
                            }.buttonStyle(.plain).accessibilityIdentifier("radioAlbum." + album.id)
                        }
                    }
                }
            }.padding(.top, 8)
        }
    }
    private func refreshFailure(_ failure: CatalogFailure) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.t("refreshRetained")).font(.subheadline.weight(.semibold))
            Text(model.t(failure.messageKey)).font(.caption).foregroundStyle(Palette.muted)
            Button(model.t("retry")) { Task { await model.load() } }.frame(minHeight: 44).accessibilityIdentifier("discoveryRefreshFailure.retry")
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14)).accessibilityIdentifier("discoveryRefreshFailure")
    }
    @ViewBuilder private var emptyState: some View {
        if model.discoveryPhase == .loading { ProgressView(model.t("loading")).frame(maxWidth: .infinity, minHeight: 180) }
        else if model.discoveryPhase == .unavailable {
            ContentUnavailableView { Label(model.t("unavailable"), systemImage: "wifi.slash") }
                description: { Text(model.t(model.discoveryFailure?.messageKey ?? "startupFailure")) }
                actions: { Button(model.t("retry")) { Task { await model.load() } }.frame(minHeight: 44) }
        } else { ContentUnavailableView(model.t("empty"), systemImage: "music.note") }
    }
}

private struct RadioScale: View {
    let frequency: Double
    let stations: [Double]
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                for tick in 875...1080 {
                    let x = size.width / 2 + (Double(tick) / 10 - frequency) * 70
                    guard x >= -8, x <= size.width + 8 else { continue }
                    let height: Double = tick.isMultiple(of: 10) ? 26 : tick.isMultiple(of: 5) ? 16 : 9
                    var line = Path(); line.move(to: CGPoint(x: x, y: size.height - 12)); line.addLine(to: CGPoint(x: x, y: size.height - 12 - height))
                    context.stroke(line, with: .color(Palette.muted.opacity(tick.isMultiple(of: 10) ? 0.8 : 0.35)), lineWidth: 1)
                    if tick.isMultiple(of: 20) {
                        context.draw(Text(String(tick / 10)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted), at: CGPoint(x: x, y: 14))
                    }
                }
                for station in stations {
                    let x = size.width / 2 + (station - frequency) * 70
                    context.fill(Path(ellipseIn: CGRect(x: x - 3.5, y: 30, width: 7, height: 7)), with: .color(Palette.accent))
                }
            }
            Rectangle().fill(Palette.accent).frame(width: 2).position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            Image(systemName: "arrowtriangle.down.fill").font(.system(size: 10)).foregroundStyle(Palette.accent)
                .position(x: geometry.size.width / 2, y: 4)
        }
    }
}
