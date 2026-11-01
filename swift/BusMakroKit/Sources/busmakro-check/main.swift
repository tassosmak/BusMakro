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
