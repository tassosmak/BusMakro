import Foundation

/// Today's departures of one OASA variant of a line, from each end ("go" from the start, "come" back).
public struct Timetable: Sendable, Identifiable {
    public var id: String { code }
    public let code: String
    public let name: String
    public let nameEnglish: String
    public let go: [Date]
    public let come: [Date]
}

extension OASAClient {
    public static let athens = TimeZone(identifier: "Europe/Athens")!

    /// Every line's OASA codes (a line can have several variants, each with its own timetable).
    public func lineCodes() async throws -> [String: [(code: String, name: String, nameEnglish: String)]] {
        var out: [String: [(code: String, name: String, nameEnglish: String)]] = [:]
        for l in (try await call("webGetLines")) as? [[String: Any]] ?? [] {
            guard let id = l["LineID"] as? String, let code = l["LineCode"] as? String else { continue }
            out[id, default: []].append((code, l["LineDescr"] as? String ?? "", l["LineDescrEng"] as? String ?? ""))
        }
        return out
    }

    /// Today's timetable of one variant (`line_code`). In a "go" row `sde_start1` is the outbound
    /// departure, in a "come" row `sde_start2` the return one (as oasa/schedule.py).
    public func dailySchedule(code: String, day: Date = Date()) async throws -> (go: [Date], come: [Date]) {
        let raw = try await call("getDailySchedule", named: ["line_code": code]) as? [String: Any] ?? [:]
        var cal = Calendar(identifier: .gregorian); cal.timeZone = Self.athens
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"; fmt.timeZone = Self.athens
        func times(_ key: String, _ field: String) -> [Date] {
            let rows = raw[key] as? [[String: Any]] ?? []
            let set = Set(rows.compactMap { r -> Date? in
                guard let s = r[field] as? String, let t = fmt.date(from: s) else { return nil }
                let hm = cal.dateComponents([.hour, .minute, .second], from: t)
                return cal.date(bySettingHour: hm.hour!, minute: hm.minute!, second: hm.second!, of: day)
            })
            return set.sorted()
        }
        return (times("go", "sde_start1"), times("come", "sde_start2"))
    }

    /// The whole of today's timetable for a line, busiest variant first (variants with no trips left out).
    public func timetable(line: String, codes: [String: [(code: String, name: String, nameEnglish: String)]]) async -> [Timetable] {
        var out: [Timetable] = []
        for v in codes[line] ?? [] {
            if let d = try? await dailySchedule(code: v.code), !(d.go.isEmpty && d.come.isEmpty) {
                out.append(Timetable(code: v.code, name: v.name, nameEnglish: v.nameEnglish, go: d.go, come: d.come))
            }
        }
        return out.sorted { $0.go.count + $0.come.count > $1.go.count + $1.come.count }
    }
}
