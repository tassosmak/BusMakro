import Foundation

/// OASA's telematics API (telematics.oasa.gr). It answers only POST; positional parameters go as
/// p1, p2, … and every number comes back as a string.
public struct OASAClient: Sendable {
    public static let base = URL(string: "https://telematics.oasa.gr/api/")!
    let session: URLSession

    public init(session: URLSession = OASAClient.shared) { self.session = session }

    /// Its own session: the shared one lets only a few requests per host run at once, so a stop's
    /// times queued behind timetable and favourite lookups (10-20 s while OASA answers in 0.5 s).
    public static let shared: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpMaximumConnectionsPerHost = 16
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    /// Answers kept for a short while, and one request shared by everyone asking at the same time.
    actor Recent {
        static let shared = Recent()
        private var kept: [String: (at: Date, task: Task<Any, Error>)] = [:]
        func get(_ key: String, for seconds: TimeInterval, _ fetch: @escaping @Sendable () async throws -> Any) async throws -> Any {
            if let k = kept[key], Date().timeIntervalSince(k.at) < seconds { return try await k.task.value }
            let task = Task { try await fetch() }
            kept[key] = (Date(), task)
            do { return try await task.value } catch { kept[key] = nil; throw error }
        }
    }

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
    static func str(_ v: Any?) -> String { opt(v) ?? "" }

    /// A field as text, whether OASA sent it as text or as a number (in November 2026 it switched
    /// codes like LineCode from "1151" to 1151, and every `as? String` came back empty); nil if missing.
    static func opt(_ v: Any?) -> String? {
        guard let v, !(v is NSNull) else { return nil }
        if let s = v as? String { return s.isEmpty ? nil : s }
        if let n = v as? NSNumber {
            let d = n.doubleValue
            return d == d.rounded() && abs(d) < 1e15 ? String(Int64(d)) : n.stringValue
        }
        return "\(v)"
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
        // the list, the map's buses and the prediction history all ask: one request between them
        Self.rows(try await Recent.shared.get("arr|" + stopID, for: 8) { try await call("getStopArrivals", [stopID]) }).compactMap { a in
            guard let m = Int(Self.str(a["btime2"])) else { return nil }
            return (Self.str(a["route_code"]), Self.str(a["veh_code"]), m)
        }
    }

    /// Every line at a stop with its next official arrivals, soonest first (as get_stop_lines in the Mac app).
    public func stopLines(stopID: String) async throws -> [StopLine] {
        // which lines stop here changes rarely: asked once an hour, not every 15 s
        async let routesCall = Recent.shared.get("routes|" + stopID, for: 3600) {
            let r = try await call("webRoutesForStop", [stopID])
            if Self.rows(r).isEmpty { throw URLError(.zeroByteResource) }  // a null answer isn't kept
            return r
        }
        let arrivals = (try? await stopArrivals(stopID: stopID)) ?? []  // lines are worth showing without times
        var routes = Self.rows((try? await routesCall) ?? [Any]())
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
