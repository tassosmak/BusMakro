import SwiftUI

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
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

/// Frosted pane on the glass: a faint fill and a hairline edge (card_base in widgets.py).
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

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .rotationEffect(.degrees(turns * 360))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Style.roundButton, height: Style.roundButton)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glass(Circle())
        .help(help)
        .accessibilityLabel(help)  // VoiceOver reads the name, not the symbol
        .onChange(of: spinning) { if spinning { spin() } }
    }

    /// One whole turn at a time, so it never stops half-way round.
    private func spin() {
        withAnimation(.linear(duration: 0.7)) { turns += 1 } completion: { if spinning { spin() } }
    }
}

/// A line number on a blue rounded badge.
struct LineBadge: View {
    let line: String
    var width: CGFloat = 58
    var body: some View {
        Text(line)
            .font(.system(size: 15, weight: .bold, design: .rounded))
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
