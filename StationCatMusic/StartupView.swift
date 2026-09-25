import SwiftUI

/// App-owned startup presentation. The artwork is bundled; it never adds a
/// network request, artificial minimum duration, or playback authorization.
struct StartupView: View {
    @Bindable var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var brandSize = 36.0
    @ScaledMetric(relativeTo: .body) private var taglineSize = 18.0
    private var failed: Bool { model.startupPhase == .unavailable }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if typeSize.isAccessibilitySize || geometry.size.height < 650 {
                    ScrollView {
                        VStack(spacing: 28) {
                            artwork(size: geometry.size)
                                .frame(height: geometry.size.height * 0.57, alignment: .top).clipped()
                            branding.padding(.horizontal, 28)
                            tagline.padding(.horizontal, 28)
                            status.padding(.horizontal, 28)
                        }.padding(.bottom, max(32, geometry.safeAreaInsets.bottom))
                    }
                } else {
                    artwork(size: geometry.size)
                    branding.frame(width: geometry.size.width - 40)
                        .position(x: geometry.size.width / 2, y: geometry.size.height * 0.625)
                    tagline.frame(width: geometry.size.width - 40)
                        .position(x: geometry.size.width / 2, y: geometry.size.height * 0.71)
                    VStack {
                        status
                        Spacer(minLength: 0)
                    }.frame(width: geometry.size.width - 48, height: geometry.size.height * (failed ? 0.23 : 0.155))
                        .position(x: geometry.size.width / 2, y: geometry.size.height * (failed ? 0.875 : 0.9175))
                }
            }.background(Palette.background)
        }.ignoresSafeArea()
    }
    private func artwork(size: CGSize) -> some View {
        Image("StartupBackground").resizable().scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped().accessibilityHidden(true)
    }
    private var branding: some View {
        VStack(spacing: 3) {
            Text("Station Cat").font(.system(size: brandSize, weight: .bold))
                .foregroundStyle(.white).accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
            Text("MUSIC").font(.system(.subheadline, design: .default).weight(.medium))
                .tracking(10).padding(.leading, 10).foregroundStyle(Palette.accent)
        }.multilineTextAlignment(.center)
    }
    private var tagline: some View {
        Text(model.t("startupTagline")).font(.system(size: taglineSize))
            .tracking(model.locale.hasPrefix("zh") ? 2 : 0)
            .foregroundStyle(.white.opacity(0.92)).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
    @ViewBuilder private var status: some View {
        if failed {
            VStack(spacing: 10) {
                Text(model.t(model.startupFailureKey)).font(.subheadline)
                    .foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button { Task { await model.retryStartup() } } label: {
                    Text(model.t("retry")).font(.body.weight(.semibold))
                        .padding(.horizontal, 22).padding(.vertical, 6)
                        .frame(minWidth: 150, minHeight: 44)
                        .foregroundStyle(Palette.background)
                        .background(Palette.accent, in: Capsule())
                }.buttonStyle(.plain).accessibilityIdentifier("startupRetry")
                Button { model.continueAfterStartupFailure() } label: {
                    Text(model.t("startupContinue")).font(.subheadline).foregroundStyle(Palette.accent)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("startupContinue")
            }
        } else {
            VStack(spacing: 16) {
                if reduceMotion {
                    loadingDots(active: 1)
                } else {
                    TimelineView(.periodic(from: .now, by: 0.55)) { context in
                        loadingDots(active: Int(context.date.timeIntervalSinceReferenceDate / 0.55) % 3)
                    }.accessibilityHidden(true)
                }
                Text(model.t("startupLoading")).font(.subheadline)
                    .foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                    .accessibilityIdentifier("startupLoading")
            }
        }
    }
    private func loadingDots(active: Int) -> some View {
        HStack(spacing: 10) {
            ForEach(0..<3) { index in
                Circle().fill(Palette.accent.opacity(index == active ? 1 : 0.6))
                    .frame(width: index == active ? 8 : 6, height: index == active ? 8 : 6)
                    .frame(width: 8, height: 8)
            }
        }.frame(height: 12).accessibilityHidden(true)
    }
}
