import SwiftUI

struct CachedArtwork: View {
    let url: URL
    let host: String
    let loader: ArtworkLoader
    let fill: Bool
    var retryGeneration = 0
    @State private var image: CGImage?
    @State private var displayedURL: URL?
    private struct RequestID: Equatable { let url: URL; let retry: Int }
    var body: some View {
        Group {
            if displayedURL == url, let image {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: fill ? .fill : .fit)
            } else { Image(systemName: "music.note").foregroundStyle(Palette.muted) }
        }.task(id: RequestID(url: url, retry: retryGeneration)) {
            // Keep an already displayed image through metadata refreshes. Only
            // a failed view needs another request for the same URL.
            if displayedURL == url, image != nil { return }
            if displayedURL != url { image = nil }
            let result = try? await loader.load(url, allowedHost: host)
            guard !Task.isCancelled else { return }
            displayedURL = url; image = result
        }
    }
}
