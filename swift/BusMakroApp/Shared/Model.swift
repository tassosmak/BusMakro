import BusMakroKit
import CoreLocation
import Foundation
import Observation
import SwiftUI

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
    private var stopsOrigin: CLLocationCoordinate2D?
    var centredOnUser = false
    // line view
    var lineTab: LineTab = .arrivals
    var lineDetail: LineDetail?
    var vehicles: [Vehicle] = [] {
        didSet { renewRoutes() }
    }
    /// Where each bus is drawn now (moved along its road once a second, see Movement).
    var drawn: [String: CLLocationCoordinate2D] = [:]
    private var routes: [String: Movement.Route] = [:]
    private var holds: [String: Double] = [:]
    private var moveTask: Task<Void, Never>?
    var official: [String: Int] = [:]
    var lineStop: String?          // the stop the line was opened at (selected)
    private var lineTask: Task<Void, Never>?
    var timetable: (line: String, variants: [Timetable])?
    var stopIndex: StopIndex?
    var alerts: [ServiceAlert] = []
    var watches: [String: BusWatch] = [:]
    var showWelcome = !UserDefaults.standard.bool(forKey: "onboarded")
    var showSettings = false
    var watchTask: Task<Void, Never>?
    private var lineCodes: [String: [(code: String, name: String, nameEnglish: String)]]?

    private let oasa = OASAClient(), transit = TransitClient()
    private let location = CLLocationManager()

    override init() {
        super.init()
        location.delegate = self
    }

    func start() async {
        if !showWelcome { askLocation() }  // during the welcome, Continue asks (not over it)
        lines = (try? await transit.lines()) ?? []
        async let index = StopIndex.load(lines: lines.map(\.id))  // for search; cached for a day
        alerts = await Alerts.fetch(known: Set(lines.map(\.id)))
        stopIndex = try? await index
    }

    /// Strikes and whole-network notices (strikes first), and the alerts that name any of `lines`.
    var networkAlerts: [ServiceAlert] { alerts.filter { $0.lines.isEmpty }.sorted { $0.strike && !$1.strike } }
    func alerts(for lines: [String]) -> [ServiceAlert] { alerts.filter { !$0.lines.isDisjoint(with: lines) } }

    // MARK: Search (the bar at the top): lines by number or name, then stops by name
    var lineResults: [LineSummary] {
        let q = Translit.normalize(searchText)
        guard !q.isEmpty else { return [] }
        let hits = lines.filter {
            Translit.normalize($0.id).hasPrefix(q) || (q.count > 2 && Translit.normalize($0.name).contains(q))
        }
        return Array(hits.sorted { (Translit.normalize($0.id) == q ? 0 : 1) < (Translit.normalize($1.id) == q ? 0 : 1) }.prefix(8))
    }

    var stopResults: [(stop: Stop, lines: [String])] {
        (stopIndex?.search(searchText) ?? []).map {
            (Stop(id: $0.id, name: $0.entry.name, nameEnglish: "", street: "", latitude: $0.entry.lat, longitude: $0.entry.lon),
             $0.entry.lines)
        }
    }

    // MARK: Stops
    /// Stops near a point. Like the Mac app: only after the map moved at least 400 m (so the list
    /// doesn't change under your finger), nearest first, and left alone when nothing changed.
    func loadStops(near c: CLLocationCoordinate2D, force: Bool = false) async {
        if !force, let o = stopsOrigin, Geo.distance(o.latitude, o.longitude, c.latitude, c.longitude) < 400 { return }
        stopsOrigin = c
        do {
            let found = try await oasa.closestStops(latitude: c.latitude, longitude: c.longitude)
            let ref = userLocation ?? c
            let sorted = found.sorted {
                Geo.distance(ref.latitude, ref.longitude, $0.latitude, $0.longitude) < Geo.distance(ref.latitude, ref.longitude, $1.latitude, $1.longitude)
            }
            if sorted.map(\.id) != stops.map(\.id) { stops = sorted }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    /// Metres from you (or nil without a fix).
    func distance(to s: Stop) -> Double? {
        userLocation.map { Geo.distance($0.latitude, $0.longitude, s.latitude, s.longitude) }
    }

    /// Show a stop at once (the tap must feel instant), then load its lines.
    func open(_ stop: Stop) {
        screen = .stop(stop)
        stopLines = nil
        recents = [stop] + recents.filter { $0.id != stop.id }
        recents = Array(recents.prefix(6))
        Model.saveStops(recents, "recents")
        Task { await loadStopLines(stop) }
    }

    func loadStopLines(_ stop: Stop) async {
        do {
            stopLines = try await oasa.stopLines(stopID: stop.id)
            Task { [oasa, stopLines] in await oasa.observe(stop: stop.id, lines: stopLines ?? []) }  // learn (History)
            await addSchedules(stop: stop.id)
        } catch {
            self.error = error.localizedDescription
            stopLines = []  // don't stay on "Loading…"
        }
    }

    /// Lines with no bus on the road get the timetable's next arrival (fetched side by side).
    private func addSchedules(stop: String) async {
        guard let lines = stopLines else { return }
        let idle = lines.filter { $0.arrivalsMinutes.isEmpty && !$0.lineCode.isEmpty }
        let found = await withTaskGroup(of: (String, Scheduled?).self) { group in
            for l in idle {
                group.addTask { [oasa] in (l.line, await oasa.scheduledArrival(lineCode: l.lineCode, routeTypes: l.routeTypes, stopID: stop)) }
            }
            var out: [String: Scheduled] = [:]
            for await (id, s) in group { if let s { out[id] = s } }
            return out
        }
        guard case .stop(let s) = screen, s.id == stop else { return }
        stopLines = lines.map { var l = $0; l.scheduled = found[l.line]; return l }
            .sorted { a, b in
                let ta = a.arrivalsMinutes.first.map { Double($0) * 60 } ?? a.scheduled.map { $0.arrive.timeIntervalSinceNow } ?? .infinity
                let tb = b.arrivalsMinutes.first.map { Double($0) * 60 } ?? b.scheduled.map { $0.arrive.timeIntervalSinceNow } ?? .infinity
                return ta < tb
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
        if let live = try? await transit.live(line: id) {
            vehicles = live.vehicles
            checkWatches(line: id, vehicles: live.vehicles)
        }
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

    /// A fresh fix: new road to drive, and hold the marker if the bus fell a little behind it.
    private func renewRoutes() {
        var r: [String: Movement.Route] = [:], h: [String: Double] = [:]
        for v in vehicles {
            let route = Movement.route(for: v)
            r[v.id] = route
            if let d = drawn[v.id] { h[v.id] = Movement.hold(drawn: (d.latitude, d.longitude), on: route) }
        }
        routes = r; holds = h
        drawn = drawn.filter { id, _ in vehicles.contains { $0.id == id } }
        if moveTask == nil {
            moveTask = Task { [weak self] in
                while !Task.isCancelled {
                    self?.tickBuses()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }

    private func tickBuses() {
        let now = Date()
        var next: [String: CLLocationCoordinate2D] = [:]
        for v in vehicles {
            let p = Movement.position(v, route: routes[v.id], hold: holds[v.id] ?? 0, now: now)
            next[v.id] = CLLocationCoordinate2D(latitude: p.0, longitude: p.1)
        }
        withAnimation(.linear(duration: 1)) { drawn = next }  // glide between the once-a-second positions
    }

    /// The route variant on screen: the one serving the selected stop with the most buses.
    var variantID: String? {
        lineDetail.flatMap { LineMath.variant(for: $0, stop: lineStop, live: vehicles) }
    }

    var approaching: [Approaching] {
        guard let d = lineDetail, let s = lineStop else { return [] }
        return LineMath.approaching(s, detail: d, live: vehicles, official: official)
    }

    func clearRecents() {
        recents = []
        Model.saveStops([], "recents")
    }

    func isFavourite(_ s: Stop) -> Bool { favourites.contains { $0.id == s.id } }

    func toggleFavourite(_ s: Stop) {
        if isFavourite(s) { favourites.removeAll { $0.id == s.id } } else { favourites.append(s) }
        Model.saveStops(favourites, "favorites")
    }

    // MARK: Location
    func askLocation() {
        location.requestWhenInUseAuthorization()
        location.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        if s == .authorizedWhenInUse || s == .authorizedAlways { manager.requestLocation() }
    }

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

    static func saveStops(_ stops: [Stop], _ key: String) {
        UserDefaults.standard.set(stops.map { ["id": $0.id, "name": $0.name, "name_en": $0.nameEnglish,
                                               "street": $0.street, "lat": $0.latitude, "lon": $0.longitude] }, forKey: key)
    }
}

extension Stop {
    var title: String { Names.place(name, nameEnglish) }
}

/// Place and line names in the app's language: Greek as-is, or OASA's English name, else a
/// standard (ELOT 743) transliteration (as the Mac app's i18n.name).
enum Names {
    static var greek: Bool { Bundle.main.preferredLocalizations.first == "el" }

    static func place(_ greekName: String, _ english: String?) -> String {
        if greek { return greekName.isEmpty ? (english ?? "") : greekName }
        let e = (english ?? "").trimmingCharacters(in: .whitespaces)
        return e.isEmpty ? Translit.latin(greekName) : e
    }
}

extension LineSummary {
    var shown: String { Names.place(name, nameEnglish) }
}
