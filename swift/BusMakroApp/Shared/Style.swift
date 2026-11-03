import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The Mac app's look, as SwiftUI: the same sizes, radii, fonts and colours (oasa/config.py, widgets.py).
enum Style {
    static let barHeight: CGFloat = 40        // PILL_H: search capsule and round buttons
    static let roundButton: CGFloat = 40      // FLOAT_BTN
    static let sheetRadius: CGFloat = 22
    /// The panel hugs the phone's rounded corners: its bottom corners are concentric with the
    /// screen's (about 47 pt on current iPhones) at the panel's inset from the edges.
    static let screenRadius: CGFloat = 47
    static let panelInset: CGFloat = 8
    static var panelShape: UnevenRoundedRectangle {
        let bottom = screenRadius - panelInset
        return UnevenRoundedRectangle(topLeadingRadius: sheetRadius, bottomLeadingRadius: bottom,
                                      bottomTrailingRadius: bottom, topTrailingRadius: sheetRadius, style: .continuous)
    }
    static let gap: CGFloat = 13              // SHEET_GAP: one inset for everything in the panel
    static let lineMenuHeight: CGFloat = 22   // LINE_MENU_H
    static let cardRadius: CGFloat = 14
    static let chipHeight: CGFloat = 26       // CHIP_H
    /// Favourite stops on the map, until you pick another colour in Settings (a warm pink).
    static let favouriteColor = "#E8467C"

    /// SF Pro Rounded with fixed-width digits, for times and distances.
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .scaled(size, weight, design: .rounded).monospacedDigit()
    }
}

/// Frosted pane on the glass: a faint fill and a hairline edge (card_base in widgets.py).
extension ShapeStyle where Self == Color {
    /// Second lines on cards: .secondary turned nearly invisible on the panel's glass in dark mode.
    static var subtle: Color { Color.primary.opacity(0.62) }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.background.opacity(0.32), in: RoundedRectangle(cornerRadius: Style.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Style.cardRadius).strokeBorder(.primary.opacity(0.10), lineWidth: 0.5))
    }
}

/// The panel's glass: a material (it animates smoothly while the panel resizes; Liquid Glass
/// flashed dark on every frame of the minimize animation).
struct PanelGlass<S: Shape>: ViewModifier {
    let shape: S
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(.separator, lineWidth: 0.5))
    }
}

/// The app's glass (glass() in widgets.py): thin material, rounded, with a separator-coloured hairline.
struct Glass<S: Shape>: ViewModifier {
    let shape: S
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(.separator, lineWidth: 0.5))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
    func glass<S: Shape>(_ shape: S) -> some View { modifier(Glass(shape: shape)) }
    func panelGlass<S: Shape>(_ shape: S) -> some View { modifier(PanelGlass(shape: shape)) }
}

/// A round glass button with an SF Symbol (float_button in widgets.py).
struct RoundButton: View {
    let symbol: String
    var help: LocalizedStringKey = ""
    /// Turns round and round (a refresh at work).
    var spinning = false
    let action: () -> Void
    @State private var turns = 0.0
    /// The live value for the spin loop (its completion saw a stale copy of `spinning`, always true,
    /// so the button span forever).
    @State private var active = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.scaled(15, .medium))
                .rotationEffect(.degrees(turns * 360))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Style.roundButton, height: Style.roundButton)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glass(Circle())
        .help(help)
        .accessibilityLabel(help)  // VoiceOver reads the name, not the symbol
        .onChange(of: spinning) { active = spinning; if spinning { spin() } }
    }

    /// One whole turn at a time, so it never stops half-way round.
    private func spin() {
        withAnimation(.linear(duration: 0.7)) { turns += 1 } completion: { if active { spin() } }
    }
}

/// A line number on a blue rounded badge.
struct LineBadge: View {
    let line: String
    var width: CGFloat = 58
    var body: some View {
        Text(line)
            .font(.scaled(15, .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: width, height: 28)
            .background(.blue, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Low Power Mode: the phone halves the frame rate and slows the CPU, so the decorative motion
/// (pulses, ripples, staggered rows, gliding buses) stutters. With it on, those stay still.
@Observable final class LowPower {
    static let shared = LowPower()
    private(set) var on = ProcessInfo.processInfo.isLowPowerModeEnabled
    private init() {
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.on = ProcessInfo.processInfo.isLowPowerModeEnabled }
        }
    }
}

extension Font {
    /// The app's type sizes, following the system text size (Dynamic Type): each size is the text
    /// style it equals at the default setting (13 = footnote, 17 = body…), so it grows and shrinks
    /// with Settings → Display & Brightness → Text Size; the in-between sizes scale like the nearest style.
    static func scaled(_ size: CGFloat, _ weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        let styles: [(CGFloat, Font.TextStyle)] = [(11, .caption2), (12, .caption), (13, .footnote), (15, .subheadline),
                                                   (16, .callout), (17, .body), (20, .title3), (22, .title2), (28, .title), (34, .largeTitle)]
        let nearest = styles.min { abs($0.0 - size) < abs($1.0 - size) }!
        if nearest.0 == size { return .system(nearest.1, design: design, weight: weight) }
        #if canImport(UIKit)
        let uiStyle: [Font.TextStyle: UIFont.TextStyle] = [.caption2: .caption2, .caption: .caption1, .footnote: .footnote,
            .subheadline: .subheadline, .callout: .callout, .body: .body, .title3: .title3, .title2: .title2, .title: .title1, .largeTitle: .largeTitle]
        let scaled = UIFontMetrics(forTextStyle: uiStyle[nearest.1]!).scaledValue(for: size)
        return .system(size: scaled, weight: weight, design: design)
        #else
        return .system(size: size, weight: weight, design: design)
        #endif
    }
}
