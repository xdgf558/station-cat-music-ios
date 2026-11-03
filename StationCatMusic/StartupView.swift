import SwiftUI

/// Bundled branding only; the scale never delays or cancels real initialization.
struct StartupView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = Date()
    private let paper = Color(red: 241 / 255, green: 231 / 255, blue: 212 / 255)
    private let muted = Color(red: 167 / 255, green: 152 / 255, blue: 127 / 255)
    private let pointer = Color(red: 224 / 255, green: 102 / 255, blue: 63 / 255)
    private var failed: Bool { model.startupPhase == .unavailable }
    var body: some View {
        ZStack {
            Color(red: 21 / 255, green: 17 / 255, blue: 13 / 255).ignoresSafeArea()
            GeometryReader { geometry in
            ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 48)
                VStack(spacing: 18) {
                    Image("OrbitBrand").resizable().scaledToFit().frame(width: 92, height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 24)).accessibilityHidden(true)
                    Text(model.t("radio.brand")).radioSerif(28, weight: .black, relativeTo: .largeTitle)
                        .foregroundStyle(paper).multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                    Text("QUIET NIGHT RADIO").radioMono(10, relativeTo: .caption).tracking(3).foregroundStyle(muted)
                }
                if reduceMotion { scale(progress: 1) }
                else {
                    TimelineView(.periodic(from: started, by: 0.1)) { context in
                        scale(progress: min(1, max(0, context.date.timeIntervalSince(started).truncatingRemainder(dividingBy: 2) / 1.5)))
                    }.accessibilityHidden(true)
                }
                status
                Spacer(minLength: 48)
                if !failed && model.platformMode {
                    Button { model.skipRadioStartup() } label: {
                        Text(model.t("radio.skip")).radioMono(11, relativeTo: .caption).foregroundStyle(muted).frame(minWidth: 100, minHeight: 44)
                    }.buttonStyle(.plain).accessibilityIdentifier("startupSkip")
                }
            }.padding(.horizontal, 28).padding(.bottom, 24)
                .padding(.top, geometry.size.height > 700 ? 100 : 20)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }.scrollIndicators(.hidden)
            }
        }
    }
    private func scale(progress: Double) -> some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(0..<21) { index in
                        Rectangle().fill(paper.opacity(0.25)).frame(width: 1, height: index.isMultiple(of: 5) ? 36 : 27)
                        if index < 20 { Spacer(minLength: 0) }
                    }
                }.frame(maxHeight: .infinity, alignment: .bottom)
                Rectangle().fill(pointer).frame(width: 2).shadow(color: pointer.opacity(0.7), radius: 6)
                    .offset(x: max(0, geometry.size.width - 2) * progress)
            }.frame(width: 240, height: 40).overlay(Rectangle().stroke(paper.opacity(0.2), lineWidth: 1))
            Text(model.t("radio.startupTuning") + " " + String(format: "FM %.1f", 87.5 + progress * 1.1))
                .radioMono(13, weight: .semibold, relativeTo: .caption).foregroundStyle(pointer)
        }.padding(.top, 12)
    }
    @ViewBuilder private var status: some View {
        if failed {
            VStack(spacing: 12) {
                Text(model.t(model.startupFailureKey)).font(.subheadline).foregroundStyle(muted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Button { Task { await model.retryStartup() } } label: {
                    Text(model.t("retry")).font(.body.weight(.bold)).foregroundStyle(.white).padding(.horizontal, 30).frame(minHeight: 48)
                        .background(Palette.accent, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain).accessibilityIdentifier("startupRetry")
                Button { model.continueAfterStartupFailure() } label: {
                    Text(model.t("startupContinue")).font(.subheadline).foregroundStyle(paper).frame(minHeight: 44)
                }.buttonStyle(.plain).accessibilityIdentifier("startupContinue")
            }
        } else {
            Text(model.t("startupLoading")).font(.caption).foregroundStyle(muted).multilineTextAlignment(.center).accessibilityIdentifier("startupLoading")
        }
    }
}
