import BusMakroKit
import CoreLocation
import Foundation
import Observation

/// The app's state, mirroring the Mac app: home (nearby stops / favourites) → a stop's lines.
@MainActor @Observable
final class Model: NSObject, CLLocationManagerDelegate {
    enum Screen: Equatable { case home, stop(Stop), line(String, Stop?) }
    enum LineTab: Hashable { case arrivals, route, nearby, timetable }
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
    // line view
    var lineTab: LineTab = .arrivals
    var lineDetail: LineDetail?
    var vehicles: [Vehicle] = []
    var official: [String: Int] = [:]
    var lineStop: String?          // the stop the line was opened at (selected)
    private var lineTask: Task<Void, Never>?
    var timetable: (line: String, variants: [Timetable])?
    private var lineCodes: [String: [(code: String, name: String, nameEnglish: String)]]?

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
        do { stopLines = try await oasa.stopLines(stopID: stop.id) } catch {
            self.error = error.localizedDescription
            stopLines = []  // don't stay on "Loading…"
        }
    }

    // MARK: Line view
    /// Open a line, with `stop` selected (from the stop screen). Its buses refresh every 15 s.
    func openLine(_ id: String, at stop: Stop?) {
        screen = .line(id, stop)
        lineStop = stop?.id
        lineDetail = nil; vehicles = []; official = [:]
        lineTab = .arrivals
        lineTask?.cancel()
        lineTask = Task { [weak self] in
            guard let self else { return }
            self.lineDetail = try? await self.transit.detail(line: id)
            while !Task.isCancelled, case .line(id, _) = self.screen {
                await self.refreshLine(id)
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    func refreshLine(_ id: String) async {
        if let live = try? await transit.live(line: id) { vehicles = live.vehicles }
        if let s = lineStop { official = await oasa.predictions(stopID: s) }
    }

    /// Today's timetable of the open line (fetched once per line).
    func loadTimetable() async {
        guard case .line(let id, _) = screen, timetable?.line != id else { return }
        if lineCodes == nil { lineCodes = try? await oasa.lineCodes() }
        let variants = await oasa.timetable(line: id, codes: lineCodes ?? [:])
        if case .line(id, _) = screen { timetable = (id, variants) }
    }

    /// The line's stops nearest you (or the map's centre without a fix): (stop id, info, metres).
    func nearestOnLine(from c: CLLocationCoordinate2D?, limit: Int = 6) -> [(String, LineDetail.StopInfo, Double)] {
        guard let d = lineDetail, let c = c ?? userLocation else { return [] }
        return d.stops.map { ($0.key, $0.value, Geo.distance(c.latitude, c.longitude, $0.value.lat, $0.value.lon)) }
            .sorted { $0.2 < $1.2 }.prefix(limit).map { $0 }
    }

    func closeLine() {
        lineTask?.cancel()
        if case .line(_, let stop?) = screen { screen = .stop(stop) } else { screen = .home }
    }

    /// The route variant on screen: the one serving the selected stop with the most buses.
    var variantID: String? {
        lineDetail.flatMap { LineMath.variant(for: $0, stop: lineStop, live: vehicles) }
    }

    var approaching: [Approaching] {
        guard let d = lineDetail, let s = lineStop else { return [] }
        return LineMath.approaching(s, detail: d, live: vehicles, official: official)
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
