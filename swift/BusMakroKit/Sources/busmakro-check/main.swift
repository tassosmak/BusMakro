// Smoke test of BusMakroKit against the live services: nearby stops, the lines at the nearest,
// and the buses of the first line. `swift run busmakro-check [lat lon]`.
import BusMakroKit
import Foundation

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
