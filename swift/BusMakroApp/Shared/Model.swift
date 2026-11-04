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
    enum LineTab: Hashable { case arrivals, route, timetable }
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
    var nicknames: [String: String] = Nicknames.all
    var userLocation: CLLocationCoordinate2D?
    var error: String?
    var searchText = ""
    /// The search field is open (focused or holding text): results drop down under it, the panel hides.
    var searchActive = false
    private(set) var stopsOrigin: CLLocationCoordinate2D?
    var centredOnUser = false
    // line view
    var lineTab: LineTab = .arrivals
    /// The open line's first buses and times aren't in yet (a spinner, not "no bus").
    var lineLoading = false
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
    /// The open line has no route anywhere (not running: Χ80 outside the summer), not "loading".
    var lineMissing = false
    var stopIndex: StopIndex? {
        // the nearby list came first: now drop the stops no line serves
        didSet { if let ix = stopIndex { stops = stops.filter { !(ix.stops[$0.id]?.lines.isEmpty ?? true) } } }
    }
    var alerts: [ServiceAlert] = []
    var watches: [String: BusWatch] = [:]
    var showWelcome = !UserDefaults.standard.bool(forKey: "onboarded")
    var showSettings = false
    var showTrip = false
    /// Your saved Home and Work, for "Take Me Home" / "Take Me to Work"; asked once after the welcome,
    /// set in Settings, or the first time you ask to go there.
    var home: TripPlanner.Place? = Model.loadPlace(.home) { didSet { Model.savePlace(home, .home) } }
    var work: TripPlanner.Place? = Model.loadPlace(.work) { didSet { Model.savePlace(work, .work) } }
    /// Where the trip planner should go when it opens, and which saved place it should first ask for.
    var tripTo: TripPlanner.Place?
    var pickingPlace: SavedPlace?
    @ObservationIgnored var cachedPlanner: TripPlanner?
    var watchTask: Task<Void, Never>?
    private var lineCodes: [String: [(code: String, name: String, nameEnglish: String)]]?
    private var masterCodes: [String: String]?
    var timetableDays: [OASAClient.ScheduleDay] = []
    var timetableDay: String?
    var timetableWeekday = 1
    // follow a bus (the map keeps it centred), buses heading to the open stop, favourites' live times
    var pinned: String? { didSet { if pinned != oldValue { followChanged(from: oldValue, to: pinned) } } }
    var pendingPin: String?
    var stopBuses: [(vehicle: Vehicle, line: String)] = []
    var favLines: [String: [StopLine]] = [:]
    var chosenVariant: String?
    private var stopTask: Task<Void, Never>?
    // offline: no connection at all, or the bus service didn't answer
    var online = true
    var serviceDown = false
    /// When live data last arrived (shown while offline, so you know how old what you see is).
    var lastUpdated: Date?
    /// The open stop's times are the saved ones from then (offline), not live.
    var stopLinesSaved: Date?
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
            for await (id, l) in group {
                if let l { favLines[id] = l; ArrivalCache.save(stop: id, l) }
                else if favLines[id] == nil, let saved = ArrivalCache.load(stop: id) { favLines[id] = saved.lines }
            }
        }
    }

    func start() async {
        if !showWelcome { askLocation() }  // during the welcome, Continue asks (not over it)
        Task.detached { await Rail.refresh() }  // a newer metro/tram timetable, weekly
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
        let q = Translit.normalize(searchText), k = Translit.lineKey(searchText)
        guard !q.isEmpty else { return [] }
        let hits = lines.filter {
            (!k.isEmpty && Translit.lineKey($0.id).hasPrefix(k)) || (q.count > 2 && Translit.normalize($0.name).contains(q))
        }
        return Array(hits.sorted { (Translit.lineKey($0.id) == k ? 0 : 1) < (Translit.lineKey($1.id) == k ? 0 : 1) }.prefix(8))
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
            // a newer request (your fix, the map moved) went out meanwhile: its stops win
            guard let o = stopsOrigin, o.latitude == c.latitude, o.longitude == c.longitude else { return }
            let ref = userLocation ?? c
            let sorted = found.sorted {
                Geo.distance(ref.latitude, ref.longitude, $0.latitude, $0.longitude) < Geo.distance(ref.latitude, ref.longitude, $1.latitude, $1.longitude)
            }
            // stops no line serves any more (OASA still lists some, like Pl. Syntagmatos 60003)
            let served = sorted.filter { s in stopIndex.map { !($0.stops[s.id]?.lines.isEmpty ?? true) } ?? true }
            if served.map(\.id) != stops.map(\.id) { stops = served }
            error = nil; serviceDown = false; lastUpdated = .now
        } catch { failed(error) }
    }

    /// Zoomed out further than this (about 3 km top to bottom), the map shows no stop pins.
    static let stopsMaxSpan = 0.03

    /// The stops inside a map region, nearest its centre first, at most 80 (from the stop index,
    /// so the whole screen is covered, not just the 12 OASA returns around the centre).
    func stops(in region: MKCoordinateRegion) -> [Stop] {
        guard let index = stopIndex, region.span.latitudeDelta <= Self.stopsMaxSpan else { return [] }
        let c = region.center, dLat = region.span.latitudeDelta / 2, dLon = region.span.longitudeDelta / 2
        var found: [(Stop, Double)] = []
        for (id, e) in index.stops where abs(e.lat - c.latitude) <= dLat && abs(e.lon - c.longitude) <= dLon {
            found.append((Stop(id: id, name: e.name, nameEnglish: "", street: "", latitude: e.lat, longitude: e.lon),
                          Geo.distance(c.latitude, c.longitude, e.lat, e.lon)))
        }
        return found.sorted { $0.1 < $1.1 }.prefix(80).map(\.0)
    }

    /// Metres from you (or nil without a fix).
    func distance(to s: Stop) -> Double? {
        userLocation.map { Geo.distance($0.latitude, $0.longitude, s.latitude, s.longitude) }
    }

    /// Show a stop at once (the tap must feel instant), then load its lines.
    func open(_ stop: Stop) {
        screen = .stop(stop)
        stopLines = nil; stopLinesSaved = nil
        // the last times seen here (if recent) show at once, marked, until live ones arrive
        if let saved = ArrivalCache.load(stop: stop.id), saved.at.timeIntervalSinceNow > -600 {
            stopLines = saved.lines; stopLinesSaved = saved.at
        }
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
            serviceDown = false; lastUpdated = .now; stopLinesSaved = nil
            ArrivalCache.save(stop: stop.id, fresh)
            Task { [oasa] in await oasa.observe(stop: stop.id, lines: fresh) }  // learn (History)
            async let buses: Void = loadStopBuses(fresh)
            if known.isEmpty { await addSchedules(stop: stop.id) }
            await buses
        } catch {
            failed(error)
            guard case .stop(let s) = screen, s.id == stop.id else { return }
            // offline: what was last seen here, with when (only until live times come back)
            if stopLines?.isEmpty ?? true || stopLinesSaved != nil, let saved = ArrivalCache.load(stop: stop.id) {
                stopLines = saved.lines; stopLinesSaved = saved.at
            }
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
        // "X95" from a link or Siri is the line filed as "Χ95"
        let id = lines.first { Translit.lineKey($0.id) == Translit.lineKey(id) }?.id ?? id
        screen = .line(id, stop)
        stopTask?.cancel()
        lineStop = stop?.id
        chosenVariant = nil
        pinned = nil
        // the buses already on the map from the stop stay put (they vanished and came back)
        vehicles = stopBuses.filter { $0.line == id }.map(\.vehicle)
        lineDetail = nil; lineMissing = false; official = [:]; lineLoading = true
        lineTab = .arrivals
        lineTask?.cancel()
        lineTask = Task { [weak self] in
            guard let self else { return }
            // the route and the first live buses side by side (one after the other was twice as slow)
            async let live = try? self.transit.live(line: id)
            self.lineDetail = try? await self.transit.detail(line: id)
            self.lineMissing = self.lineDetail == nil
            var first = await live
            while !Task.isCancelled, case .line(id, _) = self.screen {
                await self.refreshLine(id, live: first?.vehicles)
                first = nil
                self.lineLoading = false
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    /// Opened without a stop: of the line's stops near you (within 1.5 km), the nearest one buses
    /// are heading to (the nearest was sometimes a stop where they only drop off), instead of
    /// "choose a stop".
    private func pickStopNearYou() {
        guard let d = lineDetail else { return }
        let near = nearestOnLine(from: nil, limit: 8).filter { $0.2 < 1500 }
        lineStop = (near.first { !LineMath.approaching($0.0, detail: d, live: vehicles, official: [:]).isEmpty } ?? near.first)?.0
    }

    /// A missed bus is kept for one refresh: the feed sometimes skips one (it blinked out and back).
    @ObservationIgnored private var missedOnce: Set<String> = []

    private func take(_ live: [Vehicle], line id: String) {
        let ids = Set(live.map(\.id))
        let missed = vehicles.filter { !ids.contains($0.id) && !missedOnce.contains($0.id) }
        missedOnce = Set(missed.map(\.id))
        vehicles = live + missed
        if lineLoading {
            AccessibilityNotification.Announcement(live.isEmpty ? String(localized: "No buses on this line right now")
                                                   : live.count == 1 ? String(localized: "1 bus on this line") : String(localized: "\(live.count) buses on this line")).post()
        }
        lineLoading = false  // buses in: OASA's minutes follow (they kept the spinner up 10 s)
        serviceDown = false; lastUpdated = .now
        checkWatches(line: id, vehicles: live)
        if let p = pendingPin, vehicles.contains(where: { $0.id == p }) { pinned = p; pendingPin = nil }
        if let p = pinned, !vehicles.contains(where: { $0.id == p }) { pinned = nil }  // gone
    }

    /// `live`: buses just fetched (opening the line), not asked for again.
    func refreshLine(_ id: String, live: [Vehicle]? = nil) async {
        do {
            if let live { take(live, line: id) } else { take(try await transit.live(line: id).vehicles, line: id) }
            // opened without a stop: chosen as soon as the buses are in, so OASA's times are asked
            // for once, for that stop (picking after them waited on OASA twice: 20-30 s when slow)
            if lineStop == nil { pickStopNearYou() }
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
        // OASA ignores the master code (any value gives the same timetable); many lines (810) have none
        if let kind = timetableDay {
            let master = masterCodes?[id] ?? "0"
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
        // nothing moving: don't touch state, or the whole map redraws every second for nothing
        if vehicles.isEmpty && stopBuses.isEmpty { if !drawn.isEmpty { drawn = [:] }; return }
        let now = Date()
        var next: [String: CLLocationCoordinate2D] = [:]
        for v in vehicles + stopBuses.map(\.vehicle) {
            var p = Movement.position(v, route: routes[v.id], hold: holds[v.id] ?? 0, now: now)
            // following the bus you're on: you are the best fix there is (driven on from an old fix,
            // it ran ahead of you through stops and lights)
            if v.id == pinned, let u = userLocation, let r = routes[v.id] {
                let me = Movement.along(r, (u.latitude, u.longitude)), bus = Movement.along(r, p)
                if me.off < 35 && abs(me.d - bus.d) < 400 { p = Movement.point(r, at: me.d) }
            }
            next[v.id] = CLLocationCoordinate2D(latitude: p.0, longitude: p.1)
        }
        if next.count != drawn.count || next.contains(where: { k, v in drawn[k].map { $0.latitude != v.latitude || $0.longitude != v.longitude } ?? true }) { if LowPower.shared.on { drawn = next } else { withAnimation(.linear(duration: 1)) { drawn = next } } }  // glide between the once-a-second positions
        if pinned != nil { tick += 1 }  // only the map following a pinned bus needs it
    }

    /// The route variant on screen: the one serving the selected stop with the most buses.
    var variantID: String? {
        if let c = chosenVariant, lineDetail?.variants[c] != nil { return c }  // picked in the Route tab
        return lineDetail.flatMap { LineMath.variant(for: $0, stop: lineStop, live: vehicles) }
    }

    var approaching: [Approaching] {
        guard let d = lineDetail, let s = lineStop else { return [] }
        // from where each bus is drawn, not its last fix: a bus seen passing stops counts them down
        let now = Date()
        let here = vehicles.map { v in drawn[v.id].map { v.moved(to: $0.latitude, $0.longitude, at: now) } ?? v }
        return LineMath.approaching(s, detail: d, live: here, official: official, now: now)
    }

    /// A bus on the map, for VoiceOver: "in 3 minutes to Syntagma, 2 stops away" (or how old its position is).
    func spokenArrival(of v: Vehicle) -> String {
        var parts: [String?] = []
        if let a = approaching.first(where: { $0.vehicle.id == v.id }) {
            let stop = lineStop.flatMap { lineDetail?.stops[$0] }.map { Names.place($0.name, "") }
            parts.append(a.seconds < 20 ? String(localized: "Due now") : String(localized: "in \(Speak.minutes(Int(a.seconds) / 60))"))
            parts.append(stop.map { String(localized: "to \($0)") })
            parts.append(Speak.stops(a.stopsAway))
        }
        if let at = v.positionAt, Date().timeIntervalSince(at) > 120 {
            parts.append(String(localized: "position from \(Speak.minutes(Int(Date().timeIntervalSince(at) / 60))) ago"))
        }
        if pinned == v.id { parts.append(String(localized: "following")) }
        return Speak.join(parts)
    }

    func clearRecents() {
        recents = []
        Model.saveStops([], "recents")
    }

    /// Name (or with "" un-name) a favourite stop or line; `key` is "stop:ID" or "line:ID".
    func setNickname(_ name: String, for key: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        Nicknames.all[key] = n.isEmpty ? nil : n
        UserDefaults.standard.set(Nicknames.all, forKey: "nicknames")
        nicknames = Nicknames.all  // views that show names redraw
        if key.hasPrefix("stop:") { favourites = favourites; recents = recents }  // quick actions, Spotlight, chips
    }

    func isFavouriteLine(_ id: String) -> Bool { favouriteLines.contains(id) }

    func toggleFavouriteLine(_ id: String) {
        if isFavouriteLine(id) { favouriteLines.removeAll { $0 == id } } else { favouriteLines.append(id) }
        UserDefaults.standard.set(favouriteLines, forKey: "favoriteLines")
    }

    /// Reorder favourites: put `key` ("stop:ID" or "line:ID") where `target` is, or move it by `by` places.
    func moveFavourite(_ key: String, to target: String? = nil, by: Int = 0) {
        func move<T>(_ a: inout [T], _ id: (T) -> String, _ k: String, _ t: String?) {
            guard let from = a.firstIndex(where: { id($0) == k }) else { return }
            let to = t.flatMap { t in a.firstIndex { id($0) == t } } ?? min(max(from + by, 0), a.count - 1)
            guard to != from else { return }
            a.insert(a.remove(at: from), at: to)
        }
        let id = String(key.drop { $0 != ":" }.dropFirst()), t = target.map { String($0.drop { $0 != ":" }.dropFirst()) }
        if key.hasPrefix("stop:") {
            guard target == nil || target!.hasPrefix("stop:") else { return }
            move(&favourites, \.id, id, t); Model.saveStops(favourites, "favorites")
        } else {
            guard target == nil || target!.hasPrefix("line:") else { return }
            move(&favouriteLines, { $0 }, id, t); UserDefaults.standard.set(favouriteLines, forKey: "favoriteLines")
        }
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

    /// While a bus alert is set, keep location running in the background (the blue pill shows it), so
    /// iOS doesn't suspend the app and the alert's checks go on with the app closed or the phone locked.
    func keepRunningInBackground(_ on: Bool) {
        #if os(iOS)
        location.allowsBackgroundLocationUpdates = on
        location.showsBackgroundLocationIndicator = on
        location.pausesLocationUpdatesAutomatically = !on
        if on { location.startUpdatingLocation() }
        #endif
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
    static func loadPlace(_ k: SavedPlace) -> TripPlanner.Place? {
        guard let d = UserDefaults.standard.dictionary(forKey: k.rawValue), let lat = d["lat"] as? Double, let lon = d["lon"] as? Double
        else { return nil }
        return TripPlanner.Place(id: d["id"] as? String ?? "", name: d["name"] as? String ?? "", lat: lat, lon: lon)
    }

    static func savePlace(_ p: TripPlanner.Place?, _ k: SavedPlace) {
        if let p { UserDefaults.standard.set(["name": p.name, "lat": p.lat, "lon": p.lon, "id": p.id], forKey: k.rawValue) }
        else { UserDefaults.standard.removeObject(forKey: k.rawValue) }
    }

    subscript(place k: SavedPlace) -> TripPlanner.Place? {
        get { k == .home ? home : work }
        set { if k == .home { home = newValue } else { work = newValue } }
    }

    /// From where you are to Home or Work; without one saved, the planner first asks where it is.
    func takeMe(to k: SavedPlace) {
        searchActive = false
        if let p = self[place: k] { tripTo = p } else { pickingPlace = k }
        showTrip = true
    }

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
    /// Your nickname for it when you gave one ("Home", "Work"), else its name.
    var title: String { Nicknames.all["stop:\(id)"] ?? Names.place(name, nameEnglish) }
}

/// Your own names for favourite stops and lines (long-press one in Favourites → Rename).
/// Keys: "stop:400022", "line:040".
enum Nicknames {
    nonisolated(unsafe) static var all: [String: String] =  // changed only on the main actor (setNickname)
        UserDefaults.standard.dictionary(forKey: "nicknames") as? [String: String] ?? [:]
}

/// Place and line names in the app's language: Greek as-is, or OASA's English name, else a
/// standard (ELOT 743) transliteration (as the Mac app's i18n.name).
enum Names {
    static var greek: Bool { Bundle.main.preferredLocalizations.first == "el" }

    static func place(_ greekName: String, _ english: String?) -> String {
        if greek { return greekName.isEmpty ? (english ?? "") : greekName }
        let e = (english ?? "").trimmingCharacters(in: .whitespaces)
        if !e.isEmpty { return e }
        // OASA's notes on temporary routes, in words rather than transliterated ("PROSORINI LOGO ERGON")
        var g = greekName.replacingOccurrences(of: "(", with: " (")
        for (el, en) in notes { g = g.replacingOccurrences(of: el, with: " \(en) ") }
        return Translit.latin(g).replacingOccurrences(of: "  ", with: " ").replacingOccurrences(of: "( ", with: "(")
            .replacingOccurrences(of: " )", with: ")").trimmingCharacters(in: .whitespaces)
    }

    private static let notes: [(String, String)] = [
        ("ΠΡΟΣΩΡΙΝΗ ΛΟΓΩ ΕΡΓΩΝ", "temporary, roadworks"), ("ΠΡΟΣΩΡΙΝΗ", "temporary"), ("ΛΟΓΩ ΕΡΓΩΝ", "roadworks"),
        ("ΚΥΚΛΙΚΗ", "circular"),
    ]
}

extension LineSummary {
    var shown: String { Names.place(name, nameEnglish) }
}

/// The places you can save for one-tap trips.
enum SavedPlace: String, CaseIterable, Identifiable {
    case home, work
    var id: String { rawValue }
    var title: String { self == .home ? String(localized: "Home") : String(localized: "Work") }
    var icon: String { self == .home ? "house.fill" : "briefcase.fill" }
    var question: LocalizedStringKey { self == .home ? "Where is Home?" : "Where is Work?" }
    var action: LocalizedStringKey { self == .home ? "Take Me Home" : "Take Me to Work" }
}
