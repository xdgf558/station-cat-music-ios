import SwiftUI

struct CachedArtwork: View {
    let url: URL
    let host: String
    let loader: ArtworkLoader
    let fill: Bool
    @State private var image: CGImage?
    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: fill ? .fill : .fit)
            } else { Image(systemName: "music.note").foregroundStyle(Palette.muted) }
        }.task(id: url) {
            image = nil
            let result = try? await loader.load(url, allowedHost: host)
            guard !Task.isCancelled else { return }
            image = result
        }
    }
}
