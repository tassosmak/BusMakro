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
    }
    public struct StopInfo: Sendable, Decodable, Hashable {
        public let name: String
        public let lat: Double
        public let lon: Double
    }

    public let id: String
    public let variants: [String: Variant]
    public let stops: [String: StopInfo]
}

/// A bus on its way to a stop.
public struct Approaching: Identifiable, Hashable, Sendable {
    public var id: String { vehicle.id }
    public let vehicle: Vehicle
    public let stopsAway: Int
    public let metres: Double
    /// Seconds to the stop: OASA's official prediction when there is one, else our own estimate.
    public let seconds: Double
    public let official: Bool
}

public enum LineMath {
    static let defaultSpeed = 4.5  // m/s, a typical Athens bus pace incl. stops and lights

    /// The variant to show for a stop: the one that serves it and has the most buses on it.
    public static func variant(for detail: LineDetail, stop: String?, live: [Vehicle]) -> String? {
        let serving = detail.variants.filter { stop == nil || $0.value.stops.contains(stop!) }
        let pool = serving.isEmpty ? detail.variants : serving
        return pool.keys.max { a, b in
            let ca = live.filter { $0.variant == a }.count, cb = live.filter { $0.variant == b }.count
            return ca == cb ? a > b : ca < cb
        }
    }

    /// The buses still heading to `stop`, nearest first. `official` maps vehicle code → minutes (OASA).
    public static func approaching(_ stop: String, detail: LineDetail, live: [Vehicle],
                                   official: [String: Int], now: Date = Date()) -> [Approaching] {
        live.compactMap { v in
            guard let vid = v.variant, let route = detail.variants[vid]?.stops,
                  let si = route.firstIndex(of: stop), let next = v.nextStopID,
                  let ni = route.firstIndex(of: next), ni <= si else { return nil }
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
            let age = v.positionAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
            let speed = min(11, max(2.5, (v.speed ?? 0) > 0 ? v.speed! : defaultSpeed))
            return Approaching(vehicle: v, stopsAway: si - ni, metres: m, seconds: max(0, m / speed - age), official: false)
        }
        .sorted { $0.metres < $1.metres }
    }
}

extension TransitClient {
    /// A line's route variants and stops.
    public func detail(line: String) async throws -> LineDetail {
        let url = Self.staticBase.appendingPathComponent("lines").appendingPathComponent("\(line).json")
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(LineDetail.self, from: data)
    }
}

extension OASAClient {
    /// Official predictions at a stop by vehicle: vehicle code → minutes.
    public func predictions(stopID: String) async -> [String: Int] {
        let rows = (try? await stopArrivals(stopID: stopID)) ?? []
        return Dictionary(rows.filter { !$0.vehicle.isEmpty }.map { ($0.vehicle, $0.minutes) }, uniquingKeysWith: min)
    }
}
