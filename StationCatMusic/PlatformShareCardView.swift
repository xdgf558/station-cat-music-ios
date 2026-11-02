import SwiftUI

/// Editorial postcard preview. Social apps receive the URL, not this bitmap;
/// their own handling determines whether they display a link preview.
struct PlatformShareCardView: View {
    @Bindable var model: AppModel
    let card: PlatformShareCard
    let isCurrent: Bool
    @Environment(\.dismiss) private var dismiss
    private let ink = Color(red: 0.09, green: 0.11, blue: 0.20)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    postcard
                    Text(model.t("shareCardHint"))
                        .font(.footnote).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isCurrent {
                        ShareLink(item: card.url) {
                            Label(model.t("shareMusic"), systemImage: "square.and.arrow.up")
                                .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                        }.buttonStyle(.borderedProminent).tint(Palette.accent)
                            .accessibilityIdentifier("platformShareCardConfirm")
                    } else {
                        Text(model.t("shareCardUnavailable"))
                            .font(.footnote).foregroundStyle(Palette.muted)
                            .accessibilityIdentifier("platformShareCardUnavailable")
                    }
                }.padding(22).frame(maxWidth: 480)
                    .frame(maxWidth: .infinity)
            }
            .background(Palette.background)
            .navigationTitle(model.t("shareCardTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(model.t("close")) { dismiss() }.accessibilityIdentifier("platformShareCardClose")
            } }
        }.preferredColorScheme(.dark)
    }

    private var postcard: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geometry in
                let side = geometry.size.width * 0.62
                artwork.frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: ink.opacity(0.20), radius: 12, y: 8)
            }.aspectRatio(1 / 0.62, contentMode: .fit)
            HStack(spacing: 12) {
                Text(model.t(card.kind == .track ? "shareCardSingle" : "shareCardAlbum"))
                    .font(.caption.weight(.semibold)).tracking(1)
                Rectangle().fill(ink.opacity(0.35)).frame(height: 0.5)
            }.padding(.top, 26)
            Text(card.title).font(.title.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader).padding(.top, 8)
            if !card.artist.isEmpty {
                Text(card.artist).font(.subheadline).tracking(1)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 5)
            }
            if !card.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(card.summary).font(.subheadline).lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 24)
                    .accessibilityIdentifier("platformShareCardSummary")
            }
            Rectangle().fill(ink.opacity(0.18)).frame(height: 0.5).padding(.vertical, 22)
            HStack(spacing: 10) {
                Image("OrbitBrand").resizable().scaledToFill()
                    .frame(width: 30, height: 30).clipShape(RoundedRectangle(cornerRadius: 7))
                    .accessibilityHidden(true)
                Text("Station Cat Music").font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                Text(model.t("shareCardOpen")).font(.caption.weight(.medium))
                    .multilineTextAlignment(.trailing)
            }
        }
        .foregroundStyle(ink).padding(24)
        .background(
            LinearGradient(colors: [Color(red: 0.98, green: 0.97, blue: 0.97),
                                    Color(red: 0.91, green: 0.90, blue: 0.95)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("platformShareCardPreview")
    }

    @ViewBuilder private var artwork: some View {
        if model.scope.environment != .mock, let url = card.albumArtworkURL,
           let host = model.artworkHost, url.host == host {
            CachedArtwork(url: url, host: host, loader: model.artwork, fill: true,
                          retryGeneration: model.artworkRetryGeneration)
                .accessibilityHidden(true)
        } else if let track = card.artwork {
            OrbitArtwork(track: track, model: model)
        } else {
            Image("OrbitBrand").resizable().scaledToFill().accessibilityHidden(true)
        }
    }
}
