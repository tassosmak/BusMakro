import Foundation

/// A line's static data (`static/v1/lines/{id}.json`): its route variants and their stops.
public struct LineDetail: Sendable, Decodable {
    public struct Variant: Sendable, Decodable, Identifiable {
        public var id: String { "" }
        public let headsign: String
        /// The route on the roads, as [latitude, longitude] pairs.
        public let shape: [[Double]]
        /// Stop ids in order.
        public let stops: [String]
        public init(headsign: String, shape: [[Double]], stops: [String]) {
            self.headsign = headsign; self.shape = shape; self.stops = stops
        }
    }
    public struct StopInfo: Sendable, Decodable, Hashable {
        public let name: String
        public let lat: Double
        public let lon: Double
        public init(name: String, lat: Double, lon: Double) { self.name = name; self.lat = lat; self.lon = lon }
    }

    public let id: String
    public let variants: [String: Variant]
    public let stops: [String: StopInfo]
    public init(id: String, variants: [String: Variant], stops: [String: StopInfo]) {
        self.id = id; self.variants = variants; self.stops = stops
    }
}

/// A bus on its way to a stop.
public struct Approaching: Identifiable, Hashable, Sendable {
    public var id: String { vehicle.id }
    public let vehicle: Vehicle
    public let stopsAway: Int
    public let metres: Double
    /// Seconds to the stop: OASA's official prediction when there is one, else our own estimate.
    public var seconds: Double
    public let official: Bool
    /// Standing still while OASA's time is far beyond its distance: parked at a terminus until its
    /// scheduled departure (so a bus fewer stops away can come later than one further back).
    public var waiting: Bool {
        official && (vehicle.speed ?? 0) <= 0.5 && seconds > metres / LineMath.defaultSpeed * 1.5 + 600
    }
}

public enum LineMath {
    public static let defaultSpeed = 4.5  // m/s, a typical Athens bus pace incl. stops and lights

    /// The variant to show for a stop: the one that serves it and has the most buses on it.
    public static func variant(for detail: LineDetail, stop: String?, live: [Vehicle]) -> String? {
        let serving = detail.variants.filter { stop == nil || $0.value.stops.contains(stop!) }
        let pool = serving.isEmpty ? detail.variants : serving
        return pool.keys.max { a, b in
            let ca = live.filter { $0.variant == a }.count, cb = live.filter { $0.variant == b }.count
            return ca == cb ? a > b : ca < cb
        }
    }

    /// The stop a bus drives to next, from its position: the end of the stretch between two stops
    /// it is nearest (within 300 m of the road between them).
    static func nextStop(_ v: Vehicle, on route: [String], detail: LineDetail) -> Int? {
        fit(v, on: route, detail: detail)?.i
    }

    /// Which of the line's routes a bus is on, from where it is and which way it heads (OASA's own
    /// bus positions name OASA's route codes, not the feed's): the one whose road it is nearest to.
    public static func bestVariant(for v: Vehicle, detail: LineDetail) -> String? {
        detail.variants.compactMap { id, r in fit(v, on: r.stops, detail: detail).map { (id, $0.off) } }
            .min { $0.1 < $1.1 }?.0
    }

    /// The stretch between two stops a bus is nearest (within 300 m), and how far off it is.
    static func fit(_ v: Vehicle, on route: [String], detail: LineDetail) -> (i: Int, off: Double)? {
        let k = cos(v.latitude * .pi / 180)
        var best: (i: Int, off: Double)?
        for i in 1..<max(1, route.count) {
            guard let a = detail.stops[route[i - 1]], let b = detail.stops[route[i]] else { continue }
            let bx = (b.lon - a.lon) * k, by = b.lat - a.lat, px = (v.longitude - a.lon) * k, py = v.latitude - a.lat
            let L = bx * bx + by * by
            let f = L > 0 ? max(0, min(1, (px * bx + py * by) / L)) : 0
            let off = hypot(px - bx * f, py - by * f) * 111_320
            // a loop line drives some streets both ways: skip a stretch going against the bus's heading
            if let h = v.bearing, L > 0 {
                let dir = atan2(bx, by) * 180 / .pi
                let diff = abs((h - dir + 540).truncatingRemainder(dividingBy: 360) - 180)
                if diff > 100 { continue }
            }
            if off < (best?.off ?? 300) { best = (i, off) }
        }
        return best
    }

    /// The buses still heading to `stop`, nearest first. `official` maps vehicle code → minutes (OASA).
    public static func approaching(_ stop: String, detail: LineDetail, live: [Vehicle],
                                   official: [String: Int], now: Date = Date()) -> [Approaching] {
        let found: [Approaching] = live.compactMap { v in
            // its route (or, without one, a route of the line through this stop)
            guard let route = (v.variant.flatMap { detail.variants[$0]?.stops })
                    ?? detail.variants.values.map(\.stops).first(where: { $0.contains(stop) }),
                  // its next stop: from the feed, or worked out from where it is (some lines' feeds
                  // send none, and then every bus was dropped: "no bus is heading to this stop")
                  let ni = v.nextStopID.flatMap({ route.firstIndex(of: $0) }) ?? nextStop(v, on: route, detail: detail),
                  // this stop at or after it (a loop line passes its first stop again at the end)
                  let si = route[ni...].firstIndex(of: stop) else { return turning(v, stop: stop, detail: detail, official: official) }
            let next = route[ni]
            // along the route: bus → its next stop → … → this stop
            var m = 0.0
            if let a = detail.stops[next] { m = Geo.distance(v.latitude, v.longitude, a.lat, a.lon) }
            for i in ni..<si {
                if let p = detail.stops[route[i]], let q = detail.stops[route[i + 1]] {
                    m += Geo.distance(p.lat, p.lon, q.lat, q.lon)
                }
            }
            if let mins = official[v.id] {
                return Approaching(vehicle: v, stopsAway: si - ni, metres: m, seconds: Double(mins) * 60, official: true)
            }
            // the speed of the moment says little (a bus at a light read 2.5 m/s, and a bus nearer
            // you got a later time than one behind it): a typical pace, tuned below by OASA's own times
            let age = v.positionAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
            return Approaching(vehicle: v, stopsAway: si - ni, metres: m, seconds: max(0, m / defaultSpeed - age), official: false)
        }
        .sorted { $0.metres < $1.metres }
        return consistent(found, now: now).sorted { $0.seconds < $1.seconds }
    }

    /// A bus on the other direction that OASA itself predicts for this stop: it turns round at its
    /// terminus and comes back (opened at the start of a line, every bus was "not heading here").
    static func turning(_ v: Vehicle, stop: String, detail: LineDetail, official: [String: Int]) -> Approaching? {
        guard let mins = official[v.id],
              let route = v.variant.flatMap({ detail.variants[$0]?.stops }),
              let ni = v.nextStopID.flatMap({ route.firstIndex(of: $0) }) ?? nextStop(v, on: route, detail: detail),
              let back = detail.variants.values.map(\.stops).first(where: { $0.contains(stop) && $0 != route }),
              let si = back.firstIndex(of: stop) else { return nil }
        let path = Array(route[ni...]) + Array(back[...si])
        var m = detail.stops[path[0]].map { Geo.distance(v.latitude, v.longitude, $0.lat, $0.lon) } ?? 0
        for (a, b) in zip(path, path.dropFirst()) {
            if let p = detail.stops[a], let q = detail.stops[b] { m += Geo.distance(p.lat, p.lon, q.lat, q.lon) }
        }
        return Approaching(vehicle: v, stopsAway: path.count - 1, metres: m, seconds: Double(mins) * 60, official: true)
    }

    /// Estimates that agree with OASA and with the order of the buses: the pace comes from the line's
    /// official predictions when there are some, and a bus never gets a later time than one behind it.
    static func consistent(_ list: [Approaching], now: Date) -> [Approaching] {
        var out = list
        let paces = list.filter { $0.official && $0.metres > 300 }.map { $0.seconds / $0.metres }.sorted()
        if !paces.isEmpty {
            let pace = min(1 / 2.0, max(1 / 11.0, paces[paces.count / 2]))  // seconds per metre, 2-11 m/s
            for i in out.indices where !out[i].official {
                let age = out[i].vehicle.positionAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
                out[i].seconds = max(0, out[i].metres * pace - age)
            }
        }
        // from the furthest in: an estimate is no later than the bus behind it (official times stay)
        var later = Double.infinity
        for i in out.indices.reversed() {
            if !out[i].official { out[i].seconds = min(out[i].seconds, later) }
            later = out[i].seconds
        }
        return out
    }
}

extension TransitClient {
    /// A line's route variants and stops.
    /// From athens-transit-rt's static data, or OASA's own when that fails or lacks the line (Χ25).
    public func detail(line: String) async throws -> LineDetail {
        // saved on the phone for a day: a line opens at once the second time (routes rarely change)
        let saved = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lines", isDirectory: true)
        let file = saved.appendingPathComponent("\(line.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? line).json")
        if let at = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
           Date().timeIntervalSince(at) < 86_400, let data = try? Data(contentsOf: file),
           let d = try? JSONDecoder().decode(LineDetail.self, from: data) {
            return d
        }
        do {
            let url = Self.staticBase.appendingPathComponent("lines").appendingPathComponent("\(line).json")
            let (data, resp) = try await session.data(for: URLRequest(url: url, timeoutInterval: Self.patience))
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let d = try JSONDecoder().decode(LineDetail.self, from: data)
            try? FileManager.default.createDirectory(at: saved, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
            return d
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
            await OASABackup.shared.used(line)
            return try await OASAClient().lineDetail(line: line)
        }
    }
}

extension OASAClient {
    /// Official predictions at a stop by vehicle: vehicle code → minutes.
    public func predictions(stopID: String) async -> [String: Int] {
        let rows = (try? await stopArrivals(stopID: stopID)) ?? []
        return Dictionary(rows.filter { !$0.vehicle.isEmpty }.map { ($0.vehicle, $0.minutes) }, uniquingKeysWith: min)
    }
}
