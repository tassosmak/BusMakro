import Foundation

/// The lines whose route came from OASA (athens-transit-rt was down or doesn't know them), so their
/// buses come from OASA too, and OASA's codes, fetched once.
actor OASABackup {
    static let shared = OASABackup()
    private var fromOASA: Set<String> = []
    private var lineCodes: [String: [String]]?
    private var routeCodes: [String: [String]] = [:]

    func used(_ line: String) { fromOASA.insert(line) }
    func isUsed(_ line: String) -> Bool { fromOASA.contains(line) }

    /// OASA's route codes (one per direction or variant) of a line, e.g. "Χ25" → ["6079", "6080"].
    func routes(of line: String, client: OASAClient) async throws -> [String] {
        if let r = routeCodes[line] { return r }
        if lineCodes == nil { lineCodes = try await client.lineCodes().mapValues { $0.map(\.code) } }
        var out: [String] = []
        for code in lineCodes?[line] ?? [] {
            for r in (try await client.call("webGetRoutes", [code])) as? [[String: Any]] ?? [] {
                if let rc = OASAClient.opt(r["RouteCode"]), !out.contains(rc) { out.append(rc) }
            }
        }
        routeCodes[line] = out
        return out
    }
}

extension OASAClient {
    /// Every line in OASA's list, one per line number (night versions share it).
    public func lineList() async throws -> [LineSummary] {
        var seen = Set<String>(), out: [LineSummary] = []
        for l in (try await call("webGetLines")) as? [[String: Any]] ?? [] {
            guard let id = OASAClient.opt(l["LineID"]), seen.insert(id).inserted else { continue }
            out.append(LineSummary(id: id, name: OASAClient.opt(l["LineDescr"]) ?? "", nameEnglish: OASAClient.opt(l["LineDescrEng"])))
        }
        return out
    }

    /// A line's routes (one variant per OASA route code), its stops and the roads, from OASA alone.
    public func lineDetail(line: String) async throws -> LineDetail {
        let routes = try await OASABackup.shared.routes(of: line, client: self)
        guard !routes.isEmpty else { throw URLError(.fileDoesNotExist) }  // not running (X80 in winter)
        var variants: [String: LineDetail.Variant] = [:], stops: [String: LineDetail.StopInfo] = [:]
        for code in routes {
            let rows = (try await call("webGetStops", [code])) as? [[String: Any]] ?? []
            let ordered = rows.sorted { Int("\($0["RouteStopOrder"] ?? 0)") ?? 0 < Int("\($1["RouteStopOrder"] ?? 0)") ?? 0 }
            var ids: [String] = []
            for r in ordered {
                guard let id = OASAClient.opt(r["StopCode"]), let lat = Double("\(r["StopLat"] ?? "")"),
                      let lon = Double("\(r["StopLng"] ?? "")") else { continue }
                ids.append(id)
                stops[id] = LineDetail.StopInfo(name: OASAClient.opt(r["StopDescr"]) ?? id, lat: lat, lon: lon)
            }
            let points = (try? await call("webRouteDetails", [code])) as? [[String: Any]] ?? []
            let shape = points.sorted { Int("\($0["routed_order"] ?? 0)") ?? 0 < Int("\($1["routed_order"] ?? 0)") ?? 0 }
                .compactMap { p -> [Double]? in
                    guard let lat = Double("\(p["routed_y"] ?? "")"), let lon = Double("\(p["routed_x"] ?? "")") else { return nil }
                    return [lat, lon]
                }
            // the direction: towards the last stop
            let headsign = ids.last.flatMap { stops[$0]?.name } ?? line
            if !ids.isEmpty { variants[code] = LineDetail.Variant(headsign: headsign, shape: shape.isEmpty ? ids.compactMap { stops[$0].map { [$0.lat, $0.lon] } } : shape, stops: ids) }
        }
        guard !variants.isEmpty else { throw URLError(.fileDoesNotExist) }
        return LineDetail(id: line, variants: variants, stops: stops)
    }

    /// A line's buses from OASA: position, heading and when it was taken (no speed or road ahead,
    /// so they don't glide between fixes). Each bus's variant is its OASA route code.
    public func buses(line: String) async throws -> [Vehicle] {
        // OASA has sent both "Nov  2 2026 05:44:46:000PM" and (since November 2026) "2026-11-04 12:19:44.000"
        let fmts = ["MMM d yyyy hh:mm:ss:SSSa", "yyyy-MM-dd HH:mm:ss.SSS", "yyyy-MM-dd HH:mm:ss"].map { f in
            let d = DateFormatter(); d.locale = Locale(identifier: "en_US_POSIX"); d.timeZone = Self.athens; d.dateFormat = f; return d
        }
        var out: [Vehicle] = []
        for code in try await OASABackup.shared.routes(of: line, client: self) {
            for b in (try? await call("getBusLocation", [code])) as? [[String: Any]] ?? [] {
                guard let id = OASAClient.opt(b["VEH_NO"]), let lat = Double("\(b["CS_LAT"] ?? "")"),
                      let lon = Double("\(b["CS_LNG"] ?? "")") else { continue }
                let when = OASAClient.opt(b["CS_DATE"]).flatMap { raw in
                    let s = raw.replacingOccurrences(of: " +", with: " ", options: .regularExpression)
                    return fmts.lazy.compactMap { $0.date(from: s) }.first
                }
                out.append(Vehicle(id: id, latitude: lat, longitude: lon, bearing: Double("\(b["VEH_HEADING"] ?? "")"),
                                   positionAt: when, variant: code))
            }
        }
        return out
    }
}
