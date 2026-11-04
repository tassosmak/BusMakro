// Smoke test of BusMakroKit against the live services: nearby stops, the lines at the nearest,
// and the buses of the first line. `swift run busmakro-check [lat lon]`.
import BusMakroKit
import Foundation

// `swift run busmakro-check plan path/to/Rail.json`: a few trips across Athens (downloads every line)
if CommandLine.arguments.dropFirst().first == "approach", CommandLine.arguments.count > 2 {
    // busmakro-check approach 814: buses heading to each stop of the line
    let line = CommandLine.arguments[2], t = TransitClient()
    let detail = try await t.detail(line: line), live = try await t.live(line: line)
    print("\(live.vehicles.count) buses, \(live.vehicles.filter { $0.nextStopID == nil }.count) without a next stop")
    for vid in detail.variants.keys.sorted() {
        let counts = detail.variants[vid]!.stops.map { LineMath.approaching($0, detail: detail, live: live.vehicles, official: [:]).count }
        print(vid, counts.map(String.init).joined(separator: " "))
    }
    // one stop late on the route: each bus's distance and time, nearest first
    if let vid = detail.variants.keys.sorted().first, let stops = detail.variants[vid]?.stops, stops.count > 10 {
        let stop = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : stops[stops.count - 5]  // or: approach 040 10341
        let official = await OASAClient().predictions(stopID: stop)
        for a in LineMath.approaching(stop, detail: detail, live: live.vehicles, official: official) {
            let age = a.vehicle.positionAt.map { Int(Date().timeIntervalSince($0)) } ?? -1
            print(stop, a.vehicle.id, a.stopsAway, "stops", Int(a.metres), "m", Int(a.seconds / 60), "min", a.official ? "OASA" : "est", a.waiting ? "WAITING" : "",
                  "speed", a.vehicle.speed ?? -1, "fix", age, "s old", "next", a.vehicle.nextStopID ?? "-", "var", a.vehicle.variant ?? "-")
        }
    }
    exit(0)
}
if CommandLine.arguments.dropFirst().first == "timetable", CommandLine.arguments.count > 2 {
    // `timetable 040`: today's departures from each end, as the Timetable tab shows them
    let line = CommandLine.arguments[2], o = OASAClient()
    let codes = (try? await o.lineCodes()) ?? [:]
    print("line codes: \(codes.count) lines; \(line): \(codes[line]?.map(\.code) ?? [])")
    for t in await o.timetable(line: line, codes: codes) {
        print("  \(t.name): \(t.go.count) from one end, \(t.come.count) from the other; first \(t.go.first.map { "\($0)" } ?? "-")")
    }
    exit(0)
}

if CommandLine.arguments.dropFirst().first == "oasa", CommandLine.arguments.count > 2 {
    // busmakro-check oasa Χ25: a line and its buses from OASA alone (the backup)
    let line = CommandLine.arguments[2], o = OASAClient()
    let d = try await o.lineDetail(line: line), buses = try await o.buses(line: line)
    for (k, v) in d.variants { print(k, v.headsign, v.stops.count, "stops", v.shape.count, "shape points") }
    for b in buses { print(b.id, b.latitude, b.longitude, b.bearing ?? -1, b.positionAt.map { Int(Date().timeIntervalSince($0)) } ?? -1, "s old", b.variant ?? "") }
    if let s = d.variants.values.first?.stops.last {
        for a in LineMath.approaching(s, detail: d, live: buses, official: [:]) { print("→", s, a.vehicle.id, a.stopsAway, "stops", Int(a.seconds / 60), "min") }
    }
    print((try await TransitClient().lines()).filter { Translit.lineKey($0.id) == Translit.lineKey("x25") }.map(\.id))
    exit(0)
}
if CommandLine.arguments.dropFirst().first == "plan" {
    let lines = try await TransitClient().lines()
    let index = try await StopIndex.load(lines: lines.map(\.id))
    let rail = CommandLine.arguments.count > 2 ? try? Rail.load(Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))) : nil
    let t0 = Date()
    let planner = TripPlanner(index: index, rail: rail)
    print("planner ready in \(String(format: "%.2f", Date().timeIntervalSince(t0))) s, \(index.routes.count) routes")
    let places = [("Syntagma", 37.9755, 23.7348), ("Kifisia", 38.0739, 23.8083), ("Glyfada", 37.8627, 23.7531),
                  ("Piraeus", 37.9480, 23.6430), ("Peristeri", 38.0136, 23.6914), ("Zografou", 37.9775, 23.7700)]
    for (i, a) in places.enumerated() {
        let b = places[(i + 2) % places.count]
        let t1 = Date()
        let trips = planner.plan(from: .init(name: a.0, lat: a.1, lon: a.2), to: .init(name: b.0, lat: b.1, lon: b.2))
        print("\n\(a.0) → \(b.0) (\(String(format: "%.2f", Date().timeIntervalSince(t1))) s)")
        for t in trips {
            print("  \(t.minutes) min: " + t.legs.map { $0.mode == .walk ? "walk \($0.minutes)" : "\($0.line) \($0.from.name)→\($0.to.name) (\($0.stops) st, \($0.minutes)+\($0.wait))" }.joined(separator: " · "))
        }
    }
    exit(0)
}

let args = CommandLine.arguments.dropFirst().compactMap(Double.init)
let (lat, lon) = args.count == 2 ? (args[0], args[1]) : (37.9755, 23.7348)  // Syntagma
let oasa = OASAClient(), transit = TransitClient()

let all = try await transit.lines()
print("lines: \(all.count)")
let stops = try await oasa.closestStops(latitude: lat, longitude: lon, limit: 5)
for s in stops {
    print("stop \(s.id) \(s.nameEnglish.isEmpty ? s.name : s.nameEnglish) · \(Geo.format(metres: Geo.distance(lat, lon, s.latitude, s.longitude)))")
}
guard let first = stops.first else { exit(1) }
let lines = try await oasa.stopLines(stopID: first.id)
for l in lines.prefix(6) {
    let times = l.arrivalsMinutes.prefix(3).map { "\($0) min" }.joined(separator: ", ")
    print("  \(l.line) \(l.nameEnglish.isEmpty ? l.name : l.nameEnglish): \(times.isEmpty ? "no live bus" : times)")
}
if let l = lines.first {
    let live = try await transit.live(line: l.line)
    print("line \(l.line): \(live.vehicles.count) buses live; first \(live.vehicles.first.map { "\($0.id) at \($0.latitude), \($0.longitude), speed \($0.speed.map { String($0) } ?? "?")" } ?? "-")")
}

// The line view's data: route variants, and the buses heading to a stop on it.
let lineID = "040"
let detail = try await transit.detail(line: lineID)
let live040 = try await transit.live(line: lineID)
if let vid = LineMath.variant(for: detail, stop: nil, live: live040.vehicles), let v = detail.variants[vid] {
    let stop = v.stops[v.stops.count * 2 / 3]
    let official = await oasa.predictions(stopID: stop)
    let coming = LineMath.approaching(stop, detail: detail, live: live040.vehicles, official: official)
    print("line \(lineID): \(detail.variants.count) variants; \(v.headsign): \(v.stops.count) stops, shape \(v.shape.count) points")
    print("  to \(detail.stops[stop]?.name ?? stop): " + coming.prefix(3).map {
        "bus \($0.vehicle.id) \($0.stopsAway) stops, \(Int($0.seconds / 60)) min\($0.official ? "" : " (est.)")" }.joined(separator: "; "))
}

// Timetable
let codes = try await oasa.lineCodes()
let tt = await oasa.timetable(line: "040", codes: codes)
let f = DateFormatter(); f.dateFormat = "HH:mm"; f.timeZone = OASAClient.athens
for v in tt {
    print("timetable 040 [\(v.code)] \(v.name): go \(v.go.count) (first \(v.go.first.map(f.string) ?? "-")), come \(v.come.count)")
}

// Search
print("translit:", Translit.latin("Πλατεία Ελευθερίας"), "·", Translit.latin("ΜΠΟΥΜΠΟΥΛΙΝΑΣ"), "·", Translit.latin("Ευαγγελισμός"))
let t0 = Date()
let index = try await StopIndex.load(lines: all.map(\.id))
print("stop index: \(index.stops.count) stops in \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")
for q in ["syntagma", "ΣΥΝΤΑΓΜΑ", "evangel"] {
    print("  \(q): " + index.search(q, limit: 3).map { "\($0.entry.name) [\($0.id)] lines \($0.entry.lines.prefix(4).joined(separator: ","))" }.joined(separator: "; "))
}

// Alerts
let alerts = await Alerts.fetch(known: Set(all.map(\.id)))
print("alerts: \(alerts.count); network: \(alerts.filter { $0.lines.isEmpty }.count)")
for a in alerts.prefix(3) { print("  \(a.strike ? "STRIKE " : "")\(a.lines.sorted().joined(separator: ",")): \(a.title.prefix(70))") }

// Movement: where each moving bus is drawn now and over the next 10 s (from the real live feed)
let l550 = try await transit.live(line: "550")
let now = Date()
for v in l550.vehicles where (v.speed ?? 0) > 0 {
    let r = Movement.route(for: v)
    let a = Movement.position(v, route: r, hold: 0, now: now), b = Movement.position(v, route: r, hold: 0, now: now.addingTimeInterval(10))
    print("bus \(v.id): fix \(Int(now.timeIntervalSince(v.positionAt ?? now)))s old, road \(Int(r?.total ?? 0)) m, moves \(Int(Geo.distance(a.0, a.1, b.0, b.1))) m in the next 10 s")
}
