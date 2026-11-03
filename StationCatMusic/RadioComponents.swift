import SwiftUI
import CoreText
import UIKit

/// Reject vertical movement before recognition so the surrounding page can scroll.
struct RadioDialDrag: UIGestureRecognizerRepresentable {
    let enabled: Bool
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }
    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        pan.isEnabled = enabled
        return pan
    }
    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) { recognizer.isEnabled = enabled }
    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed: onChanged(recognizer.translation(in: recognizer.view).x)
        case .ended, .cancelled: onEnded()
        default: break
        }
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}

enum RadioTypography {
    // Select the actual variable-font axis: its registered default is ExtraLight.
    static func serif(size: CGFloat, weight: Font.Weight) -> CTFont {
        let value: Double
        switch weight {
        case .black: value = 900
        case .heavy: value = 800
        case .bold: value = 700
        case .semibold: value = 600
        case .medium: value = 500
        case .light: value = 300
        case .thin, .ultraLight: value = 200
        default: value = 400
        }
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontNameAttribute: "NotoSerifSC-ExtraLight",
            kCTFontVariationAttribute: [NSNumber(value: 0x77676874): NSNumber(value: value)]
        ] as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }
}

private struct RadioFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: relativeTo)
        self.weight = weight; self.design = design
    }
    func body(content: Content) -> some View {
        if design == .serif {
            content.font(Font(RadioTypography.serif(size: size, weight: weight)))
        } else {
            content.font(.system(size: size, weight: weight, design: design))
        }
    }
}

extension View {
    func radioSerif(_ size: CGFloat, weight: Font.Weight = .bold, relativeTo: Font.TextStyle = .body) -> some View {
        modifier(RadioFont(size: size, weight: weight, design: .serif, relativeTo: relativeTo))
    }
    func radioMono(_ size: CGFloat, weight: Font.Weight = .regular, relativeTo: Font.TextStyle = .body) -> some View {
        modifier(RadioFont(size: size, weight: weight, design: .monospaced, relativeTo: relativeTo))
    }
}

struct RadioEyebrow: View {
    let title: String
    var body: some View {
        Text(title).radioMono(10, weight: .semibold, relativeTo: .caption).tracking(2)
            .foregroundStyle(Palette.muted)
    }
}

struct RadioSectionHeader: View {
    let title: String
    var trailing: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).radioSerif(21, relativeTo: .title3).padding(.vertical, -3).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let trailing {
                    if let action {
                        Button(trailing, action: action).font(.caption).foregroundStyle(Palette.accent)
                            .frame(minHeight: 44)
                    } else { Text(trailing).radioMono(10, relativeTo: .caption).foregroundStyle(Palette.muted) }
                }
            }
            Rectangle().fill(Palette.ink).frame(height: 2)
        }
    }
}

/// Decorative sleeve furniture; it has no playback state or audio lifecycle.
struct RadioVinyl: View {
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle().fill(Color(red: 0.055, green: 0.045, blue: 0.035))
                ForEach(0..<38) { index in
                    Circle().stroke(Color(red: 0.16, green: 0.135, blue: 0.11), lineWidth: index.isMultiple(of: 3) ? 1.2 : 0.6)
                        .padding(CGFloat(index) * size / 112 + size * 0.025)
                }
                Circle().fill(Palette.accent).frame(width: size * 0.31, height: size * 0.31)
                Circle().fill(Color(red: 0.12, green: 0.10, blue: 0.08)).frame(width: size * 0.055, height: size * 0.055)
            }.frame(width: size, height: size)
        }.aspectRatio(1, contentMode: .fit).accessibilityHidden(true)
    }
}

struct RadioTabBar: View {
    @Bindable var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    private let tabs = [("radio.tabRadio", "RADIO", "radio"), ("radio.tabShelf", "SHELF", "shelf"),
                        ("radio.tabNotes", "NOTES", "notes"), ("library", "ME", "me")]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { index in
                let tab = tabs[index]
                let selected = model.selectedTab == index
                Button {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    model.selectedTab = index
                } label: {
                    VStack(spacing: 4) {
                        Circle().fill(selected ? Palette.accent : Palette.darkMuted.opacity(0.35))
                            .frame(width: 6, height: 6)
                            .shadow(color: selected ? Palette.accent.opacity(0.65) : .clear, radius: 5)
                            .accessibilityHidden(true)
                        Text(model.t(tab.0)).font(.subheadline.weight(.bold))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge).lineLimit(1).minimumScaleFactor(0.8)
                        if !typeSize.isAccessibilitySize {
                            Text(tab.1).font(.system(size: 8, design: .monospaced)).tracking(1.5).opacity(0.7)
                        }
                    }.foregroundStyle(selected ? Palette.darkText : Palette.darkMuted)
                        .padding(.vertical, 10).frame(maxWidth: .infinity, minHeight: 64)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("tab." + tab.2)
                    .accessibilityLabel(model.t(tab.0)).accessibilityAddTraits(selected ? .isSelected : [])
            }
        }.background(Palette.dark, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: Color(red: 0.08, green: 0.05, blue: 0.02).opacity(0.25), radius: 12, y: 5)
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)
            .background(Palette.background.opacity(0.96))
            .accessibilityElement(children: .contain).accessibilityIdentifier("radioTabBar")
    }
}
