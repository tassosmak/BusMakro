import BusMakroKit
import CoreLocation
import MapKit
import Foundation
import Observation
import SwiftUI
import Network

/// The app's state, mirroring the Mac app: home (nearby stops / favourites) → a stop's lines.
@MainActor @Observable
final class Model: NSObject, CLLocationManagerDelegate {
    enum Screen: Equatable { case home, stop(Stop), line(String, Stop?), station(String) }
    enum LineTab: Hashable { case arrivals, route, nearby, timetable }
    enum HomeTab: Hashable { case nearby, favourites }

    var screen: Screen = .home
    var homeTab: HomeTab = .nearby
    var stops: [Stop] = []
    var lines: [LineSummary] = []
    var stopLines: [StopLine]?
    var favourites: [Stop] = Model.loadStops("favorites")
    var recents: [Stop] = Model.loadStops("recents")
    /// Favourite lines (ids such as "040"), in the order you added them.
    var favouriteLines: [String] = UserDefaults.standard.stringArray(forKey: "favoriteLines") ?? []
    var userLocation: CLLocationCoordinate2D?
    var error: String?
    var searchText = ""
    /// The search field is open (focused or holding text): results drop down under it, the panel hides.
    var searchActive = false
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
    var showTrip = false
    @ObservationIgnored var cachedPlanner: TripPlanner?
    var watchTask: Task<Void, Never>?
    private var lineCodes: [String: [(code: String, name: String, nameEnglish: String)]]?
    private var masterCodes: [String: String]?
    var timetableDays: [OASAClient.ScheduleDay] = []
    var timetableDay: String?
    var timetableWeekday = 1
    // follow a bus (the map keeps it centred), buses heading to the open stop, favourites' live times
    var pinned: String?
    var pendingPin: String?
    var stopBuses: [(vehicle: Vehicle, line: String)] = []
    var favLines: [String: [StopLine]] = [:]
    var chosenVariant: String?
    private var stopTask: Task<Void, Never>?
    // offline: no connection at all, or the bus service didn't answer
    var online = true
    var serviceDown = false
    private let pathMonitor = NWPathMonitor()

    private let oasa = OASAClient(), transit = TransitClient()
    private let location = CLLocationManager()

    override init() {
        super.init()
        location.delegate = self
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let was = self.online
                self.online = path.status == .satisfied
                if self.online && !was { await self.retry() }  // back online: catch up at once
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "net"))
    }

    /// Whatever is on screen, fetched again (after an error, or the network coming back).
    func retry() async {
        serviceDown = false
        if lines.isEmpty { lines = (try? await transit.lines()) ?? [] }
        switch screen {
        case .home:
            if let c = userLocation ?? stopsOrigin { await loadStops(near: c, force: true) }
            if homeTab == .favourites { await loadFavourites() }
        case .stop(let s): await loadStopLines(s)
        case .line(let id, _): await refreshLine(id)
        case .station: break  // timetable only, nothing to fetch
        }
    }

    /// The next live arrivals at every favourite stop (no timetable lookups: kept light).
    func loadFavourites() async {
        await withTaskGroup(of: (String, [StopLine]?).self) { group in
            for f in favourites { group.addTask { [oasa] in (f.id, try? await oasa.stopLines(stopID: f.id)) } }
            for await (id, l) in group { if let l { favLines[id] = l } }
        }
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
            error = nil; serviceDown = false
        } catch { failed(error) }
    }

    /// Zoomed out further than this (about 3 km top to bottom), the map shows no stop pins.
    static let stopsMaxSpan = 0.03

    /// The stops inside a map region, nearest its centre first, at most 150 (from the stop index,
    /// so the whole screen is covered, not just the 12 OASA returns around the centre).
    func stops(in region: MKCoordinateRegion) -> [Stop] {
        guard let index = stopIndex, region.span.latitudeDelta <= Self.stopsMaxSpan else { return [] }
        let c = region.center, dLat = region.span.latitudeDelta / 2, dLon = region.span.longitudeDelta / 2
        var found: [(Stop, Double)] = []
        for (id, e) in index.stops where abs(e.lat - c.latitude) <= dLat && abs(e.lon - c.longitude) <= dLon {
            found.append((Stop(id: id, name: e.name, nameEnglish: "", street: "", latitude: e.lat, longitude: e.lon),
                          Geo.distance(c.latitude, c.longitude, e.lat, e.lon)))
        }
        return found.sorted { $0.1 < $1.1 }.prefix(150).map(\.0)
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
        stopBuses = []
        stopTask?.cancel()
        stopTask = Task { [weak self] in  // refresh every 15 s while the stop is open, like the Mac app
            while let self, !Task.isCancelled, case .stop(let s) = self.screen, s.id == stop.id {
                await self.loadStopLines(stop)
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    /// A request failed: offline (no connection) or the service (it didn't answer properly).
    func failed(_ e: Error) {
        // a request cancelled because you moved on is not a failure (it showed a false "couldn't reach" banner)
        if e is CancellationError || (e as? URLError)?.code == .cancelled { return }
        error = e.localizedDescription
        if (e as? URLError)?.code != .notConnectedToInternet { serviceDown = true }
    }

    func loadStopLines(_ stop: Stop) async {
        do {
            let fresh = try await oasa.stopLines(stopID: stop.id)
            guard case .stop(let s) = screen, s.id == stop.id else { return }
            // keep the timetable estimates already found (they don't change every 15 s)
            let known = Dictionary((stopLines ?? []).compactMap { l in l.scheduled.map { (l.line, $0) } }, uniquingKeysWith: { a, _ in a })
            stopLines = fresh.map { var l = $0; if l.arrivalsMinutes.isEmpty { l.scheduled = known[l.line] }; return l }
            serviceDown = false
            Task { [oasa] in await oasa.observe(stop: stop.id, lines: fresh) }  // learn (History)
            await loadStopBuses(fresh)
            if known.isEmpty { await addSchedules(stop: stop.id) }
        } catch {
            failed(error)
            if stopLines == nil { stopLines = [] }  // don't stay on "Loading…"
        }
    }

    /// The buses heading to the open stop, with their line (shown on the map, labelled).
    private func loadStopBuses(_ lines: [StopLine]) async {
        var out: [(vehicle: Vehicle, line: String)] = []
        await withTaskGroup(of: [(vehicle: Vehicle, line: String)].self) { group in
            for l in lines where !l.vehicles.isEmpty {
                group.addTask { [transit] in
                    let live = (try? await transit.live(line: l.line))?.vehicles ?? []
                    return live.filter { l.vehicles.contains($0.id) }.map { ($0, l.line) }
                }
            }
            for await found in group { out += found }
        }
        if case .stop = screen {
            stopBuses = out
            renewRoutes()  // every refresh: the new fixes' roads (old ones pulled buses back to their old road)
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
        stopTask?.cancel()
        lineStop = stop?.id
        chosenVariant = nil
        pinned = nil
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
        do {
            let live = try await transit.live(line: id)
            vehicles = live.vehicles
            serviceDown = false
            checkWatches(line: id, vehicles: live.vehicles)
            if let p = pendingPin, live.vehicles.contains(where: { $0.id == p }) { pinned = p; pendingPin = nil }
            if let p = pinned, !live.vehicles.contains(where: { $0.id == p }) { pinned = nil }  // gone
        } catch { failed(error) }
        if let s = lineStop { official = await oasa.predictions(stopID: s) }
    }

    /// Today, 1 Monday … 7 Sunday (in Athens).
    static var weekdayToday: Int {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = OASAClient.athens
        return (cal.component(.weekday, from: Date()) + 5) % 7 + 1
    }

    /// The open line's timetable for a day of the week (today at first; fetched once per line).
    /// Each weekday gets the kind of day OASA files it under: most lines have one for Monday to
    /// Friday, Saturday and Sunday; some have their own Friday, Wednesday, Monday to Thursday…
    func loadTimetable(weekday: Int? = nil) async {
        guard case .line(let id, _) = screen, weekday != nil || timetable?.line != id else { return }
        timetableWeekday = weekday ?? Self.weekdayToday
        let day: String? = weekday == nil ? nil : OASAClient.day(for: weekday!, in: timetableDays)?.code
        if lineCodes == nil { lineCodes = try? await oasa.lineCodes() }
        if masterCodes == nil { masterCodes = try? await oasa.masterCodes() }
        let variants = lineCodes?[id] ?? []
        if day == nil {
            timetableDays = []
            timetableDay = nil
            if let first = variants.first, let days = try? await oasa.scheduleDays(code: first.code), !days.isEmpty {
                timetableDays = days
                timetableDay = (OASAClient.day(for: Self.weekdayToday, in: days) ?? days[0]).code
            }
        } else {
            if day == timetableDay { return }  // another weekday with the same timetable
            timetableDay = day
            timetable = nil
        }
        // that kind of day's timetable; without one (or the master code), OASA's "today"
        var out: [Timetable] = []
        if let kind = timetableDay, let master = masterCodes?[id] {
            for v in variants {
                if let d = try? await oasa.schedule(master: master, dayKind: kind, code: v.code), !(d.go.isEmpty && d.come.isEmpty) {
                    out.append(Timetable(code: v.code, name: v.name, nameEnglish: v.nameEnglish, go: d.go, come: d.come))
                }
            }
            out.sort { $0.go.count + $0.come.count > $1.go.count + $1.come.count }
        } else {
            out = await oasa.timetable(line: id, codes: lineCodes ?? [:])
        }
        if case .line(id, _) = screen, timetableDay == (day ?? timetableDay) { timetable = (id, out) }
    }

    /// Whether the chosen day is today (only then is there a "next" departure).
    var timetableIsToday: Bool { timetableWeekday == Self.weekdayToday }

    /// The line's stops nearest you (or the map's centre without a fix): (stop id, info, metres).
    func nearestOnLine(from c: CLLocationCoordinate2D?, limit: Int = 6) -> [(String, LineDetail.StopInfo, Double)] {
        guard let d = lineDetail, let c = c ?? userLocation else { return [] }
        return d.stops.map { ($0.key, $0.value, Geo.distance(c.latitude, c.longitude, $0.value.lat, $0.value.lon)) }
            .sorted { $0.2 < $1.2 }.prefix(limit).map { $0 }
    }

    func closeLine() {
        lineTask?.cancel()
        pinned = nil
        if case .line(_, let stop?) = screen { open(stop) } else { screen = .home }
    }

    /// A fresh fix: new road to drive, and hold the marker if the bus fell a little behind it.
    private func renewRoutes() {
        var r: [String: Movement.Route] = [:], h: [String: Double] = [:]
        for v in vehicles {
            let route = Movement.route(for: v)
            r[v.id] = route
            if let d = drawn[v.id] { h[v.id] = Movement.hold(drawn: (d.latitude, d.longitude), on: route) }
        }
        for b in stopBuses {
            let route = Movement.route(for: b.vehicle)
            r[b.vehicle.id] = route
            if let d = drawn[b.vehicle.id] { h[b.vehicle.id] = Movement.hold(drawn: (d.latitude, d.longitude), on: route) }
        }
        routes = r; holds = h
        drawn = drawn.filter { id, _ in vehicles.contains { $0.id == id } || stopBuses.contains { $0.vehicle.id == id } }
        if moveTask == nil {
            moveTask = Task { [weak self] in
                while !Task.isCancelled {
                    self?.tickBuses()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }

    /// Counts the once-a-second moves (the map follows a pinned bus on each).
    var tick = 0
    var pinnedPosition: CLLocationCoordinate2D? { pinned.flatMap { drawn[$0] } }

    private func tickBuses() {
        let now = Date()
        var next: [String: CLLocationCoordinate2D] = [:]
        for v in vehicles + stopBuses.map(\.vehicle) {
            let p = Movement.position(v, route: routes[v.id], hold: holds[v.id] ?? 0, now: now)
            next[v.id] = CLLocationCoordinate2D(latitude: p.0, longitude: p.1)
        }
        withAnimation(.linear(duration: 1)) { drawn = next }  // glide between the once-a-second positions
        tick += 1
    }

    /// The route variant on screen: the one serving the selected stop with the most buses.
    var variantID: String? {
        if let c = chosenVariant, lineDetail?.variants[c] != nil { return c }  // picked in the Route tab
        return lineDetail.flatMap { LineMath.variant(for: $0, stop: lineStop, live: vehicles) }
    }

    var approaching: [Approaching] {
        guard let d = lineDetail, let s = lineStop else { return [] }
        return LineMath.approaching(s, detail: d, live: vehicles, official: official)
    }

    func clearRecents() {
        recents = []
        Model.saveStops([], "recents")
    }

    func isFavouriteLine(_ id: String) -> Bool { favouriteLines.contains(id) }

    func toggleFavouriteLine(_ id: String) {
        if isFavouriteLine(id) { favouriteLines.removeAll { $0 == id } } else { favouriteLines.append(id) }
        UserDefaults.standard.set(favouriteLines, forKey: "favoriteLines")
    }

    func isFavourite(_ s: Stop) -> Bool { favourites.contains { $0.id == s.id } }

    func toggleFavourite(_ s: Stop) {
        if isFavourite(s) { favourites.removeAll { $0.id == s.id } } else { favourites.append(s) }
        Model.saveStops(favourites, "favorites")
    }

    // MARK: Location
    /// Location, fast: the last known fix at once, then live updates (requestLocation alone waits
    /// for one accurate fix, which can take many seconds).
    func askLocation() {
        location.desiredAccuracy = kCLLocationAccuracyHundredMeters
        location.distanceFilter = 25
        location.requestWhenInUseAuthorization()
        if let c = location.location?.coordinate { userLocation = c }
        location.startUpdatingLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        if s != .notDetermined && s != .denied && s != .restricted { manager.startUpdatingLocation() }  // (no "when in use" on Mac)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        Task { @MainActor in self.userLocation = c }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    // MARK: Saved stops (same fields as the Mac app's favourites)
    static func loadStops(_ key: String) -> [Stop] {
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
