import SwiftUI

enum Palette {
    static let background = Color(red: 0.025, green: 0.04, blue: 0.085)
    static let panel = Color(red: 0.065, green: 0.085, blue: 0.15)
    static let accent = Color(red: 0.68, green: 0.64, blue: 1)
    static let gold = accent
    static let muted = Color(red: 0.65, green: 0.69, blue: 0.79)
    static let line = Color.white.opacity(0.10)
}

struct OrbitBackground: View {
    var body: some View {
        GeometryReader { geometry in
            Image("OrbitBackground").resizable().scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                .clipped()
        }.background(Palette.background).ignoresSafeArea().accessibilityHidden(true)
    }
}

struct OrbitArtwork: View {
    let track: Track?
    let model: AppModel
    var body: some View {
        GeometryReader { geometry in
            Group {
                if let url = track?.coverUrl, url.scheme == "https",
                   let host = model.nativeMusic?.configuration.origin.host, url.host == host {
                    CachedArtwork(url: url, host: host, loader: model.artwork, fill: true)
                } else {
                    Image("OrbitCover").resizable().scaledToFill()
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.accessibilityHidden(true)
    }
}

struct OrbitRecord: View {
    let track: Track?
    let model: AppModel
    var body: some View {
        GeometryReader { geometry in
            let side = geometry.size.width
            ZStack(alignment: .topLeading) {
                Image("OrbitRecord").resizable().scaledToFit()
                    .mask {
                        LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.08), .init(color: .black, location: 0.92), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.08), .init(color: .black, location: 0.92), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
                    }
                OrbitArtwork(track: track, model: model)
                    .frame(width: side * 0.49, height: side * 0.49).clipShape(Circle())
                    .position(x: side * 0.488, y: side * 0.492)
            }
        }.aspectRatio(1, contentMode: .fit).accessibilityHidden(true)
    }
}

struct OrbitIconButton: View {
    let symbol: String
    let label: String
    var selected = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 20, weight: .medium))
                .frame(minWidth: 44, minHeight: 44)
                .foregroundStyle(selected ? Palette.accent : .white)
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}

struct OrbitPlayButton: View {
    let playing: Bool
    let loading: Bool
    let label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Palette.panel)
                Circle().strokeBorder(Palette.accent.opacity(0.8), lineWidth: 1.5)
                if loading { ProgressView().tint(.white) }
                else {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 25, weight: .semibold))
                        .offset(x: playing ? 0 : 2).foregroundStyle(.white)
                }
            }.frame(width: 64, height: 64)
                .shadow(color: Palette.accent.opacity(0.22), radius: 12)
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}

struct OrbitLyrics: View {
    let lyrics: MusicLyrics
    let position: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if lyrics.kind == "timed" {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                            Text(line.text).font(.title3.weight(index == lyrics.current(at: position) ? .bold : .medium))
                                .foregroundStyle(index == lyrics.current(at: position) ? .white : Palette.muted.opacity(0.72))
                                .frame(maxWidth: .infinity, alignment: .leading).id(index)
                        }
                    }.padding(.vertical, 20)
                }.frame(height: 220)
                    .onAppear { if let index = lyrics.current(at: position) { reader.scrollTo(index, anchor: .center) } }
                    .onChange(of: lyrics.current(at: position)) { _, index in
                        guard let index else { return }
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { reader.scrollTo(index, anchor: .center) }
                    }
            }
        } else {
            Text(lyrics.text).font(.body).lineSpacing(8).foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
