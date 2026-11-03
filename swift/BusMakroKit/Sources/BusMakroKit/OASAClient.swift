import Foundation

/// OASA's telematics API (telematics.oasa.gr). It answers only POST; positional parameters go as
/// p1, p2, … and every number comes back as a string.
public struct OASAClient: Sendable {
    public static let base = URL(string: "https://telematics.oasa.gr/api/")!
    let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    func call(_ act: String, _ args: [String] = [], named: [String: String] = [:]) async throws -> Any {
        var comps = URLComponents(url: Self.base, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "act", value: act)]
            + args.enumerated().map { URLQueryItem(name: "p\($0.offset + 1)", value: $0.element) }
            + named.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: comps.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)  // live answers, never cached
        req.httpMethod = "POST"
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        // OASA answers `null` (or nothing) when it has no rows, e.g. lines at a terminus: that's an empty list
        let any = try JSONSerialization.jsonObject(with: data.isEmpty ? Data("[]".utf8) : data, options: .fragmentsAllowed)
        return any is NSNull ? [Any]() : any
    }

    private static func rows(_ any: Any) -> [[String: Any]] { any as? [[String: Any]] ?? [] }
    /// A field as text; OASA sends JSON null for missing ones (NSNull, which would print "<null>").
    private static func str(_ v: Any?) -> String {
        guard let v, !(v is NSNull) else { return "" }
        return (v as? String) ?? "\(v)"
    }

    /// The stops nearest a point, nearest first.
    public func closestStops(latitude: Double, longitude: Double, limit: Int = 12) async throws -> [Stop] {
        let raw = Self.rows(try await call("getClosestStops", [String(latitude), String(longitude)]))
        return raw.prefix(limit).compactMap { s in
            guard let lat = Double(Self.str(s["StopLat"])), let lon = Double(Self.str(s["StopLng"])) else { return nil }
            return Stop(id: Self.str(s["StopCode"]), name: Self.str(s["StopDescr"]), nameEnglish: Self.str(s["StopDescrEng"]),
                        street: Self.str(s["StopStreet"]), latitude: lat, longitude: lon)
        }
    }

    /// Official predictions at a stop: (route code, vehicle code, minutes).
    public func stopArrivals(stopID: String) async throws -> [(route: String, vehicle: String, minutes: Int)] {
        Self.rows(try await call("getStopArrivals", [stopID])).compactMap { a in
            guard let m = Int(Self.str(a["btime2"])) else { return nil }
            return (Self.str(a["route_code"]), Self.str(a["veh_code"]), m)
        }
    }

    /// Every line at a stop with its next official arrivals, soonest first (as get_stop_lines in the Mac app).
    public func stopLines(stopID: String) async throws -> [StopLine] {
        async let routesCall = call("webRoutesForStop", [stopID])
        let arrivals = (try? await stopArrivals(stopID: stopID)) ?? []  // lines are worth showing without times
        var routes = Self.rows(try await routesCall)
        if routes.isEmpty {  // OASA sometimes answers null for a stop that has lines: ask once more
            try? await Task.sleep(for: .milliseconds(800))
            routes = Self.rows(try await call("webRoutesForStop", [stopID]))
        }
        var lines: [String: StopLine] = [:]
        for r in routes where Self.str(r["hidden"]) != "1" {
            let id = Self.str(r["LineID"]), code = Self.str(r["RouteCode"])
            guard !id.isEmpty else { continue }
            var ln = lines[id] ?? StopLine(line: id, name: Self.str(r["RouteDescr"] ?? r["LineDescr"]),
                                           nameEnglish: Self.str(r["RouteDescrEng"] ?? r["LineDescrEng"]),
                                           lineCode: Self.str(r["LineCode"]), routeCodes: [], arrivalsMinutes: [], vehicles: [])
            if !ln.routeCodes.contains(code) {  // OASA repeats routes
                ln.routeCodes.append(code)
                ln.routeTypes[code] = Self.str(r["RouteType"]).isEmpty ? "1" : Self.str(r["RouteType"])
                for a in arrivals where a.route == code {
                    ln.arrivalsMinutes.append(a.minutes)
                    if !a.vehicle.isEmpty { ln.vehicles.append(a.vehicle) }
                }
            }
            lines[id] = ln
        }
        return lines.values
            .map { var l = $0; l.arrivalsMinutes = Array(Set(l.arrivalsMinutes)).sorted(); return l }
            .sorted { ($0.arrivalsMinutes.first ?? .max, $0.line) < ($1.arrivalsMinutes.first ?? .max, $1.line) }
    }
}
