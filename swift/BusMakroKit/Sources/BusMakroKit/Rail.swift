import Foundation

/// Metro and tram (STASY): stations, lines in station order, and timetables for a typical weekday,
/// Saturday and Sunday, built from STASY's GTFS feed by tools/build_rail.py and shipped with the
/// app. There is no live data for trains, so "next trains" come from the timetable.
public struct Rail: Sendable, Decodable {
    public struct Line: Sendable, Decodable, Identifiable, Hashable {
        public struct Direction: Sendable, Decodable, Hashable {
            public let d: String
            public let to: String
            public let stations: [String]
        }
        public let id: String
        public let name: String
        public let nameEnglish: String
        public let kind: String  // "metro" or "tram"
        public let color: String
        public let dirs: [Direction]
        enum CodingKeys: String, CodingKey { case id, name, nameEnglish = "name_en", kind, color, dirs }
    }
    public struct Station: Sendable, Decodable, Hashable {
        public let name: String
        public let nameEnglish: String
        public let lat: Double
        public let lon: Double
        public let lines: [String]
        enum CodingKeys: String, CodingKey { case name, nameEnglish = "name_en", lat, lon, lines }
    }
    /// The next train of a line at a station, one direction.
    public struct Departure: Sendable, Hashable, Identifiable {
        public var id: String { "\(line)|\(direction)|\(minutes)" }
        public let line: String
        public let direction: String
        public let to: String
        public let minutes: Int  // from now
        public let at: Date
    }

    public let lines: [Line]
    public let stations: [String: Station]
    let departures: [String: [String: [Int]]]  // "station|line|dir" → day kind → gaps in minutes

    public static func load(_ data: Data) throws -> Rail { try JSONDecoder().decode(Rail.self, from: data) }

    public func line(_ id: String) -> Line? { lines.first { $0.id == id } }

    /// Stations within `metres` of a point, nearest first.
    public func stations(near lat: Double, _ lon: Double, within metres: Double) -> [(id: String, station: Station, metres: Double)] {
        stations.compactMap { id, s in
            let m = Geo.distance(lat, lon, s.lat, s.lon)
            return m <= metres ? (id, s, m) : nil
        }.sorted { $0.metres < $1.metres }
    }

    /// Departure times (minutes after midnight) of one line, one direction, at a station, on the day
    /// kind of `date`: weekday, Saturday or Sunday.
    func times(_ station: String, line: String, direction: String, on date: Date) -> [Int] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Athens")!
        let wd = cal.component(.weekday, from: date)  // 1 = Sunday
        let kind = wd == 1 ? "su" : wd == 7 ? "sa" : "wd"
        guard let gaps = departures["\(station)|\(line)|\(direction)"]?[kind] ?? departures["\(station)|\(line)|\(direction)"]?["wd"] else { return [] }
        var t = 0
        return gaps.map { t += $0; return t }
    }

    /// The next `count` trains of every line and direction at a station.
    public func next(at station: String, from now: Date = Date(), count: Int = 3) -> [Departure] {
        guard let st = stations[station] else { return [] }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Athens")!
        let midnight = cal.startOfDay(for: now)
        let nowMin = Int(now.timeIntervalSince(midnight) / 60)
        var out: [Departure] = []
        for lid in st.lines {
            guard let line = line(lid) else { continue }
            for dir in line.dirs where dir.stations.last != station {
                // today's trains, and the ones after midnight still in the previous day's timetable
                let yesterday = times(station, line: lid, direction: dir.d, on: now.addingTimeInterval(-86400)).map { $0 - 1440 }
                let today = times(station, line: lid, direction: dir.d, on: now)
                for t in (yesterday + today).filter({ $0 >= nowMin }).prefix(count) {
                    out.append(Departure(line: lid, direction: dir.d, to: dir.to, minutes: t - nowMin,
                                         at: midnight.addingTimeInterval(Double(t) * 60)))
                }
            }
        }
        return out.sorted { $0.minutes < $1.minutes }
    }

    /// Minutes a train takes from one station to another along a line (from the timetable gaps of
    /// one day's first trains); nil if they aren't in that order on the line.
    public func rideMinutes(line: String, direction: String, from a: String, to b: String) -> Int? {
        guard let dir = self.line(line)?.dirs.first(where: { $0.d == direction }),
              let i = dir.stations.firstIndex(of: a), let j = dir.stations.firstIndex(of: b), i < j else { return nil }
        // ~2 min a station on the metro, ~2.5 on the tram: the feed's own times differ little from this
        let per = self.line(line)?.kind == "tram" ? 2.5 : 2.0
        return Int((Double(j - i) * per).rounded())
    }
}
