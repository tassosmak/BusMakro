import Foundation

/// Greek → Latin (ELOT 743), keeping each letter's case, as the Mac app's i18n.transliterate.
public enum Translit {
    static let pairs: [String: String] = ["ΟΥ": "OU", "ΓΓ": "NG", "ΓΧ": "NCH", "ΓΞ": "NX"]
    static let voiceless = Set("ΘΚΞΠΣΤΦΧΨ")  // αυ/ευ become AF/EF before these (and at the end)
    static let one: [Character: String] = {
        var d = Dictionary(uniqueKeysWithValues: zip("ΑΒΓΔΕΖΗΙΚΛΜΝΞΟΠΡΣΤΥΦΩ", "AVGDEZIIKLMNXOPRSTYFO".map(String.init)))
        d["Θ"] = "TH"; d["Χ"] = "CH"; d["Ψ"] = "PS"; d["Σ"] = "S"
        return d
    }()

    public static func latin(_ text: String) -> String {
        let src = Array(text.folding(options: .diacriticInsensitive, locale: nil).replacingOccurrences(of: "ς", with: "σ"))
        let up = src.map { Character($0.uppercased()) }
        var out = "", i = 0
        while i < src.count {
            let two = i + 1 < up.count ? String([up[i], up[i + 1]]) : ""
            let wordStart = i == 0 || !up[i - 1].isLetter
            var piece: String, n = 1
            if two == "ΑΥ" || two == "ΕΥ" {
                let next: Character? = i + 2 < up.count ? up[i + 2] : nil
                piece = (two.first == "Α" ? "A" : "E") + ((next == nil || !next!.isLetter || voiceless.contains(next!)) ? "F" : "V")
                n = 2
            } else if let p = pairs[two] {
                piece = p; n = 2
            } else if two == "ΜΠ" {
                piece = wordStart ? "B" : "MP"; n = 2
            } else {
                piece = one[up[i]] ?? String(src[i])
            }
            if src[i].isLowercase {
                piece = piece.lowercased()
            } else if piece.count > 1, i + n < src.count, src[i + n].isLowercase || (n == 1 && src[i + 1].isLowercase) {
                piece = piece.capitalized  // Θέμα → Thema, not THema
            }
            out += piece
            i += n
        }
        return out
    }

    /// Lower-case Latin letters and digits only: "Πλ. Ελευθερίας" and "pl eleftherias" match.
    public static func normalize(_ text: String) -> String {
        latin(text).lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// A line number to compare by how it looks: OASA writes Χ95, Β2, Α15 with Greek letters, while
    /// people type X95, B2, A15 (as Greek, Χ became "ch" and Β "v", so "x95" found nothing).
    public static func lineKey(_ text: String) -> String {
        let looks: [Character: Character] = ["Α": "A", "Β": "B", "Ε": "E", "Ζ": "Z", "Η": "H", "Ι": "I", "Κ": "K", "Μ": "M",
                                             "Ν": "N", "Ο": "O", "Ρ": "P", "Τ": "T", "Υ": "Y", "Χ": "X"]
        return String(text.uppercased().map { looks[$0] ?? $0 }).lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
    }
}
