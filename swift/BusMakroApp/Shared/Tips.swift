import SwiftUI
import TipKit

/// Shown once, above the first approaching bus: what the two round buttons do (the app's best
/// features, and the least obvious). Gone for good after it's closed or either button is used.
struct BusButtonsTip: Tip {
    var title: Text { Text("Never miss your bus") }
    var message: Text? {
        Text("Tap the bell to be notified when this bus is a few stops from you, even with the phone locked. Tap the target to follow it on the map. On the bus? Tap the waves to be woken before your stop.")
    }
    var image: Image? { Image(systemName: "bell.badge") }
}

/// The App Store's "Enjoying BusMakro?" prompt: only after BusMakro was opened on 3 different days,
/// at most once per version, and never in the middle of a trip (iOS also limits it to 3 a year).
enum RatingPrompt {
    private static let daysKey = "usedDays", askedKey = "ratingAskedVersion"

    /// Counts today as a day the app was used.
    static func noteUse() {
        let d = UserDefaults.standard
        let today = Date().formatted(.iso8601.year().month().day())
        var days = Set(d.stringArray(forKey: daysKey) ?? [])
        guard !days.contains(today) else { return }
        days.insert(today)
        d.set(Array(days.sorted().suffix(30)), forKey: daysKey)
    }

    static var due: Bool {
        let d = UserDefaults.standard
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return (d.stringArray(forKey: daysKey)?.count ?? 0) >= 3 && d.string(forKey: askedKey) != version
    }

    static func asked() {
        UserDefaults.standard.set(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, forKey: askedKey)
    }
}
