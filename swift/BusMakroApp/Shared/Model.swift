import BusMakroKit
import CoreLocation
import Foundation
import Observation

/// The app's state, mirroring the Mac app: home (nearby stops / favourites) → a stop's lines.
@MainActor @Observable
final class Model: NSObject, CLLocationManagerDelegate {
    enum Screen: Equatable { case home, stop(Stop) }
    enum HomeTab: Hashable { case nearby, favourites }

    var screen: Screen = .home
    var homeTab: HomeTab = .nearby
    var stops: [Stop] = []
    var lines: [LineSummary] = []
    var stopLines: [StopLine]?
    var favourites: [Stop] = Model.loadStops("favorites")
    var recents: [Stop] = Model.loadStops("recents")
    var userLocation: CLLocationCoordinate2D?
    var error: String?
    var searchText = ""

    private let oasa = OASAClient(), transit = TransitClient()
    private let location = CLLocationManager()

    override init() {
        super.init()
        location.delegate = self
    }

    func start() async {
        location.requestWhenInUseAuthorization()
        location.requestLocation()
        lines = (try? await transit.lines()) ?? []
    }

    // MARK: Stops
    func loadStops(near c: CLLocationCoordinate2D) async {
        do {
            stops = try await oasa.closestStops(latitude: c.latitude, longitude: c.longitude)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    /// Metres from you (or nil without a fix).
    func distance(to s: Stop) -> Double? {
        userLocation.map { Geo.distance($0.latitude, $0.longitude, s.latitude, s.longitude) }
    }

    func open(_ stop: Stop) async {
        screen = .stop(stop)
        stopLines = nil
        recents = [stop] + recents.filter { $0.id != stop.id }
        recents = Array(recents.prefix(6))
        Model.saveStops(recents, "recents")
        do { stopLines = try await oasa.stopLines(stopID: stop.id) } catch { self.error = error.localizedDescription }
    }

    func isFavourite(_ s: Stop) -> Bool { favourites.contains { $0.id == s.id } }

    func toggleFavourite(_ s: Stop) {
        if isFavourite(s) { favourites.removeAll { $0.id == s.id } } else { favourites.append(s) }
        Model.saveStops(favourites, "favorites")
    }

    // MARK: Location
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        Task { @MainActor in self.userLocation = c }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    // MARK: Saved stops (same fields as the Mac app's favourites)
    private static func loadStops(_ key: String) -> [Stop] {
        (UserDefaults.standard.array(forKey: key) as? [[String: Any]] ?? []).compactMap { d in
            guard let id = d["id"] as? String, let lat = d["lat"] as? Double, let lon = d["lon"] as? Double else { return nil }
            return Stop(id: id, name: d["name"] as? String ?? "", nameEnglish: d["name_en"] as? String ?? "",
                        street: d["street"] as? String ?? "", latitude: lat, longitude: lon)
        }
    }

    private static func saveStops(_ stops: [Stop], _ key: String) {
        UserDefaults.standard.set(stops.map { ["id": $0.id, "name": $0.name, "name_en": $0.nameEnglish,
                                               "street": $0.street, "lat": $0.latitude, "lon": $0.longitude] }, forKey: key)
    }
}

extension Stop {
    /// English name when there is one (the Mac app also transliterates; that comes later).
    var title: String { nameEnglish.isEmpty ? name : nameEnglish }
}
