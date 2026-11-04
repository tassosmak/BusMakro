import Foundation
import SwiftUI

/// What VoiceOver says: whole words, not the screen's short forms ("3 min", "~", "→", "·" read as
/// "min", "tilde", "right arrow", "middle dot").
enum Speak {
    static func minutes(_ n: Int) -> String {
        n == 1 ? String(localized: "1 minute") : String(localized: "\(n) minutes")
    }

    static func stops(_ n: Int) -> String {
        n == 0 ? String(localized: "at the next stop") : n == 1 ? String(localized: "1 stop away") : String(localized: "\(n) stops away")
    }

    /// "70 metres", "1.2 kilometres" in the app's language.
    static func distance(_ metres: Double) -> String {
        let f = MeasurementFormatter()
        f.locale = Locale(identifier: Names.greek ? "el" : "en_GB")
        f.unitStyle = .long
        f.unitOptions = .providedUnit
        f.numberFormatter.maximumFractionDigits = 1
        let m: Measurement<UnitLength> = metres < 1000 ? Measurement(value: (metres / 10).rounded() * 10, unit: .meters)
                                                        : Measurement(value: metres / 1000, unit: .kilometers)
        return f.string(from: m)
    }

    /// "20:35" as a time VoiceOver reads naturally ("8:35 PM" / "20:35").
    static func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }

    /// Parts joined into one spoken sentence (commas make VoiceOver pause).
    static func join(_ parts: [String?]) -> String { parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ") }
}

extension View {
    /// A section title VoiceOver users can jump between (the Headings rotor).
    func heading() -> some View { accessibilityAddTraits(.isHeader) }
}
