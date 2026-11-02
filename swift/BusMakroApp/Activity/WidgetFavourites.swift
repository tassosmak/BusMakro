import Foundation

/// The favourite stops the Home Screen widget shows, shared between the app and the widget through
/// their App Group (the app writes them whenever favourites or nicknames change).
enum WidgetFavourites {
    static let group = "group.com.tassosmak.busmakro"
    private static let key = "widgetStops"

    struct Stop: Codable, Hashable {
        let id: String
        /// The name as the app shows it: the nickname when there is one.
        let title: String
    }

    static func save(_ stops: [Stop]) {
        guard let d = UserDefaults(suiteName: group), let data = try? JSONEncoder().encode(stops) else { return }
        d.set(data, forKey: key)
    }

    static func load() -> [Stop] {
        guard let data = UserDefaults(suiteName: group)?.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Stop].self, from: data)) ?? []
    }
}
