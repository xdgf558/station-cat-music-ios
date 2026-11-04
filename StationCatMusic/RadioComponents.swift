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
    private enum Region: String {
        case simplified, traditional, japanese

        init(locale: Locale) {
            let language = locale.language.languageCode?.identifier
            let script = locale.language.script?.identifier
            if language == "ja" { self = .japanese }
            else if language == "zh", script == "Hant" || (script == nil && ["TW", "HK", "MO"].contains(locale.region?.identifier ?? "")) {
                self = .traditional
            } else { self = .simplified }
        }
    }

    // Font objects are immutable. Serialize cache misses as well as lookup so
    // concurrent views do not create the same CoreText descriptor repeatedly.
    final class Cache: @unchecked Sendable {
        private final class Entry: NSObject {
            let font: CTFont
            init(_ font: CTFont) { self.font = font }
        }
        private let lock = NSLock()
        private let entries = NSCache<NSString, Entry>()

        init() { entries.countLimit = 96 }

        func font(for key: String, create: () -> CTFont) -> CTFont {
            lock.withLock {
                if let entry = entries.object(forKey: key as NSString) { return entry.font }
                let font = create()
                entries.setObject(Entry(font), forKey: key as NSString)
                return font
            }
        }
    }
    private static let cache = Cache()

    static func serif(size: CGFloat, weight: Font.Weight, locale: Locale) -> CTFont {
        let value = variationWeight(weight)
        let region = Region(locale: locale)
        // Include the actual Dynamic Type size, with no lossy rounding, and the
        // resolved regional family. Locale variants sharing a family may reuse it.
        let key = "\(region.rawValue):\(Double(size).bitPattern):\(Int(value))"
        return cache.font(for: key) {
            if region != .simplified { return regionalSerif(size: size, weight: value, region: region) }
            // Select the actual variable-font axis: its registered default is 200.
            let descriptor = CTFontDescriptorCreateWithAttributes([
                kCTFontNameAttribute: "NotoSerifSC-ExtraLight",
                kCTFontVariationAttribute: [NSNumber(value: 0x77676874): NSNumber(value: value)]
            ] as CFDictionary)
            return CTFontCreateWithFontDescriptor(descriptor, size, nil)
        }
    }

    private static func variationWeight(_ weight: Font.Weight) -> Double {
        switch weight {
        case .black: 900
        case .heavy: 800
        case .bold: 700
        case .semibold: 600
        case .medium: 500
        case .light: 300
        case .thin, .ultraLight: 200
        default: 400
        }
    }

    private static func regionalSerif(size: CGFloat, weight: Double, region: Region) -> CTFont {
        let names: [String]
        let language: String
        if region == .traditional {
            let face = weight <= 300 ? "Light" : weight >= 600 ? "Bold" : "Regular"
            names = ["SongtiTC-" + face, "STSongti-TC-" + face]
            language = "zh-Hant"
        } else {
            names = [weight >= 600 ? "HiraMinProN-W6" : "HiraMinProN-W3"]
            language = "ja"
        }
        for name in names {
            if let font = UIFont(name: name, size: size) { return font as CTFont }
        }
        // Never silently substitute the bundled SC face for regional glyphs if
        // an OS lacks the named serif. Let its language-aware native cascade win.
        return nativeRegionalFallback(size: size, weight: weight, language: language)
    }

    static func nativeRegionalFallback(size: CGFloat, weight: Double, language: String) -> CTFont {
        let system = UIFont.systemFont(ofSize: size, weight: weight >= 600 ? .bold : .regular)
        let descriptor = system.fontDescriptor.withDesign(.serif) ?? system.fontDescriptor
        let base = UIFont(descriptor: descriptor, size: size)
        return CTFontCreateForStringWithLanguage(base as CTFont, "骨" as CFString,
            CFRange(location: 0, length: 1), language as CFString)
    }
}

private struct RadioFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    @Environment(\.locale) private var locale
    let weight: Font.Weight
    let design: Font.Design
    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: relativeTo)
        self.weight = weight; self.design = design
    }
    func body(content: Content) -> some View {
        if design == .serif {
            content.font(Font(RadioTypography.serif(size: size, weight: weight, locale: locale)))
        } else {
            content.font(.system(size: size, weight: weight, design: design))
        }
    }
}

extension View {
    func radioToast(model: AppModel, identifier: String = "radioToast") -> some View {
        modifier(RadioToast(model: model, identifier: identifier))
    }
    func radioSerif(_ size: CGFloat, weight: Font.Weight = .bold, relativeTo: Font.TextStyle = .body) -> some View {
        modifier(RadioFont(size: size, weight: weight, design: .serif, relativeTo: relativeTo))
    }
    func radioMono(_ size: CGFloat, weight: Font.Weight = .regular, relativeTo: Font.TextStyle = .body) -> some View {
        modifier(RadioFont(size: size, weight: weight, design: .monospaced, relativeTo: relativeTo))
    }
}

/// Root and presented editors share presentation; AppModel owns timing and announcements.
private struct RadioToast: ViewModifier {
    let model: AppModel
    let identifier: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let text = model.radioToast {
                Text(text).font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.background).multilineTextAlignment(.center)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(Palette.ink, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20).padding(.top, 12)
                    .accessibilityIdentifier(identifier).allowsHitTesting(false)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }.animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.radioToast)
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
