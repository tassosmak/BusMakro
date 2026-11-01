import Foundation

public enum Geo {
    /// Great-circle distance in metres.
    public static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6_371_000.0
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = (lat2 - lat1) * .pi / 180, dl = (lon2 - lon1) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }

    /// "120 m" / "1.4 km", as the Mac app shows them.
    public static func format(metres: Double) -> String {
        metres < 1000 ? "\(Int((metres / 10).rounded()) * 10) m" : String(format: "%.1f km", metres / 1000)
    }
}
