import Foundation

/// A to B with buses, trolleys, metro and tram: walk to a stop, ride, at most one change, walk on.
///
/// Built on the routes every line takes (from the stop index) and STASY's stations. Ride times are
/// estimated from the distance between stops (buses) or stations (trains); waits are typical ones
/// here, and the app swaps the first wait for the real next arrival (OASA's live times, or the
/// train timetable) before showing the trips.
public struct TripPlanner: Sendable {
    public enum Mode: String, Sendable, Hashable { case walk, bus, metro, tram }

    public struct Place: Sendable, Hashable {
        public let id: String       // a stop or station id ("" for a point that isn't one)
        public let name: String
        public let lat: Double
        public let lon: Double
        public init(id: String = "", name: String, lat: Double, lon: Double) {
            self.id = id; self.name = name; self.lat = lat; self.lon = lon
        }
    }

    public struct Leg: Sendable, Hashable {
        public let mode: Mode
        public let line: String        // "" for walking
        public let headsign: String
        public let from: Place
        public let to: Place
        public let stops: Int          // stops ridden (0 for walking)
        public let minutes: Int        // walking or riding
        public var wait: Int           // before boarding (0 for walking)
        public var waitIsLive = false  // a real arrival time, not a typical wait
        public let direction: String   // a train's direction ("0"/"1"), for its timetable
    }

    public struct Trip: Sendable, Hashable, Identifiable {
        public var id: String { legs.map { $0.mode == .walk ? "w" : $0.line + "@" + $0.from.id }.joined(separator: ">") }
        public var legs: [Leg]
        public var minutes: Int { legs.reduce(0) { $0 + $1.minutes + $1.wait } }
        public var walking: Int { legs.filter { $0.mode == .walk }.reduce(0) { $0 + $1.minutes } }
        public var rides: [Leg] { legs.filter { $0.mode != .walk } }
    }

    /// One way of one line, with the minutes from its first stop to each stop.
    struct Pattern {
        let line: String, mode: Mode, headsign: String, direction: String
        let stops: [String]
        let cumulative: [Double]
    }

    static let walkPerMinute = 75.0      // metres, in a straight line (streets add the rest)
    static let busPerMinute = 270.0      // ~16 km/h along the road, between stops
    static let maxWalk = 750.0           // to the first stop / from the last one
    static let maxTransferWalk = 300.0
    static let changePenalty = 3.0       // a change feels longer than its minutes

    let patterns: [Pattern]
    let places: [String: Place]
    let at: [String: [(pattern: Int, index: Int)]]
    let grid: [Int: [String]]            // ~300 m cells → stops, for nearby lookups

    public init(index: StopIndex, rail: Rail?) {
        var places: [String: Place] = [:]
        for (id, e) in index.stops { places[id] = Place(id: id, name: e.name, lat: e.lat, lon: e.lon) }
        var patterns: [Pattern] = []
        for r in index.routes {
            let pts = r.stops.compactMap { places[$0] }
            guard pts.count == r.stops.count, pts.count > 1 else { continue }
            var cum = [0.0]
            for (a, b) in zip(pts, pts.dropFirst()) {
                cum.append(cum.last! + Geo.distance(a.lat, a.lon, b.lat, b.lon) * 1.2 / Self.busPerMinute + 0.25)  // + the stop itself
            }
            patterns.append(Pattern(line: r.line, mode: .bus, headsign: r.headsign, direction: "", stops: r.stops, cumulative: cum))
        }
        if let rail {
            for (id, s) in rail.stations { places[id] = Place(id: id, name: s.name, lat: s.lat, lon: s.lon) }
            for l in rail.lines {
                for d in l.dirs {
                    let per = l.kind == "tram" ? 2.5 : 2.0
                    patterns.append(Pattern(line: l.id, mode: l.kind == "tram" ? .tram : .metro, headsign: d.to, direction: d.d,
                                            stops: d.stations, cumulative: d.stations.indices.map { Double($0) * per }))
                }
            }
        }
        var at: [String: [(Int, Int)]] = [:]
        for (p, pat) in patterns.enumerated() { for (i, s) in pat.stops.enumerated() { at[s, default: []].append((p, i)) } }
        var grid: [Int: [String]] = [:]
        for (id, p) in places { grid[Self.cell(p.lat, p.lon), default: []].append(id) }
        self.patterns = patterns; self.places = places; self.at = at; self.grid = grid
    }

    static func cell(_ lat: Double, _ lon: Double) -> Int { Int((lat * 370).rounded(.down)) * 100_000 + Int((lon * 290).rounded(.down)) }

    func near(_ lat: Double, _ lon: Double, within m: Double) -> [(id: String, metres: Double)] {
        let c = Self.cell(lat, lon), r = Int(ceil(m / 300))
        var out: [(String, Double)] = []
        for dy in -r...r { for dx in -r...r {
            for id in grid[c + dy * 100_000 + dx] ?? [] {
                guard let p = places[id] else { continue }
                let d = Geo.distance(lat, lon, p.lat, p.lon)
                if d <= m { out.append((id, d)) }
            }
        } }
        return out
    }

    static func walkMinutes(_ metres: Double) -> Double { metres / walkPerMinute }

    /// A typical wait before boarding (replaced by the real one for the first ride).
    static func typicalWait(_ mode: Mode) -> Double { mode == .metro ? 3 : mode == .tram ? 5 : 7 }

    /// The best few trips, fastest first, each with a different set of lines.
    public func plan(from a: Place, to b: Place, limit: Int = 5) -> [Trip] {
        // stations a little further than stops: worth the walk for a train
        let origins = near(a.lat, a.lon, within: Self.maxWalk * 1.4).filter { $0.id.hasPrefix("R") || $0.metres <= Self.maxWalk }
        let dests = Dictionary(near(b.lat, b.lon, within: Self.maxWalk * 1.4)
            .filter { $0.id.hasPrefix("R") || $0.metres <= Self.maxWalk }.map { ($0.id, $0.metres) }, uniquingKeysWith: min)
        // every pattern's stops that are near B
        var destHits: [Int: [(index: Int, metres: Double)]] = [:]
        for (id, m) in dests { for (p, i) in at[id] ?? [] { destHits[p, default: []].append((i, m)) } }

        struct Arrival { var minutes: Double; var pattern: Int; var board: Int; var alight: Int; var walk0: Double; var origin: String }
        var first: [String: Arrival] = [:]   // best arrival at every stop with one ride
        var found: [String: (Double, [Leg])] = [:]

        func leg(_ p: Int, _ i: Int, _ k: Int) -> Leg {
            let pat = patterns[p]
            return Leg(mode: pat.mode, line: pat.line, headsign: pat.headsign, from: places[pat.stops[i]]!, to: places[pat.stops[k]]!,
                       stops: k - i, minutes: Int((pat.cumulative[k] - pat.cumulative[i]).rounded()),
                       wait: Int(Self.typicalWait(pat.mode).rounded()), direction: pat.direction)
        }
        func walk(_ from: Place, _ to: Place, _ metres: Double) -> Leg {
            Leg(mode: .walk, line: "", headsign: "", from: from, to: to, stops: 0, minutes: max(1, Int(Self.walkMinutes(metres).rounded())),
                wait: 0, direction: "")
        }
        func keep(_ total: Double, _ legs: [Leg]) {
            let key = legs.filter { $0.mode != .walk }.map(\.line).joined(separator: ">")
            if found[key].map({ total < $0.0 }) ?? true { found[key] = (total, legs) }
        }

        for (o, m0) in origins {
            for (p, i) in at[o] ?? [] {
                let pat = patterns[p]
                let start = Self.walkMinutes(m0) + Self.typicalWait(pat.mode)
                // a bus for a single stop is never worth its wait: walk instead
                for k in stride(from: i + (pat.mode == .bus ? 2 : 1), to: pat.stops.count, by: 1) {
                    let t = start + pat.cumulative[k] - pat.cumulative[i]
                    let s = pat.stops[k]
                    if first[s].map({ t < $0.minutes }) ?? true {
                        first[s] = Arrival(minutes: t, pattern: p, board: i, alight: k, walk0: m0, origin: o)
                    }
                    if let m = dests[s] {  // straight there
                        keep(t + Self.walkMinutes(m), [walk(a, places[o]!, m0), leg(p, i, k), walk(places[s]!, b, m)])
                    }
                }
            }
        }
        // one change: from any stop reached, walk a little to another line that goes near B
        for (s, arr) in first {
            guard let sp = places[s] else { continue }
            for (s2, m) in near(sp.lat, sp.lon, within: Self.maxTransferWalk) {
                for (q, j) in at[s2] ?? [] where patterns[q].line != patterns[arr.pattern].line {
                    guard let hits = destHits[q] else { continue }
                    let pat = patterns[q]
                    for (k, md) in hits where k > j + (pat.mode == .bus ? 1 : 0) {
                        let t = arr.minutes + Self.walkMinutes(m) + Self.changePenalty + Self.typicalWait(pat.mode)
                            + pat.cumulative[k] - pat.cumulative[j] + Self.walkMinutes(md)
                        var legs = [walk(a, places[arr.origin]!, arr.walk0), leg(arr.pattern, arr.board, arr.alight)]
                        if s2 != s { legs.append(walk(sp, places[s2]!, m)) }
                        legs += [leg(q, j, k), walk(places[pat.stops[k]]!, b, md)]
                        keep(t, legs)
                    }
                }
            }
        }
        var trips = found.values.sorted { $0.0 < $1.0 }.map { Trip(legs: $0.1.filter { $0.mode != .walk || $0.minutes > 0 }) }
        // walking can be the best way
        let direct = Geo.distance(a.lat, a.lon, b.lat, b.lon)
        if direct < 2500 {
            let w = Trip(legs: [walk(a, b, direct * 1.25)])
            trips.insert(w, at: trips.firstIndex { $0.minutes > w.minutes } ?? trips.count)
        }
        // not ten variations of the same ride: one trip per first line, and none far slower than the best
        let best = trips.first?.minutes ?? 0
        var seen = Set<String>(), out: [Trip] = []
        for t in trips where t.minutes <= best + 40 && seen.insert(t.rides.first.map { $0.line } ?? "walk").inserted {
            out.append(t)
            if out.count == limit { break }
        }
        return out.sorted { $0.minutes < $1.minutes }
    }
}
