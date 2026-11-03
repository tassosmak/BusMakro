import BusMakroKit
import Foundation

/// The last arrivals seen at each stop, kept on the phone, so underground or offline a stop still
/// shows "10 minutes ago, 810 was due in 12'". The newest 60 stops are kept.
enum ArrivalCache {
    struct Line: Codable { let line, name, nameEnglish: String; let minutes: [Int] }
    struct Entry: Codable { let at: Date; let lines: [Line] }
    private static let key = "arrivalCache"
    private static var all: [String: Entry] = {
        guard let d = UserDefaults.standard.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: d)) ?? [:]
    }()

    static func save(stop: String, _ lines: [StopLine]) {
        all[stop] = Entry(at: .now, lines: lines.map { Line(line: $0.line, name: $0.name, nameEnglish: $0.nameEnglish, minutes: $0.arrivalsMinutes) })
        if all.count > 60, let oldest = all.min(by: { $0.value.at < $1.value.at })?.key { all[oldest] = nil }
        if let d = try? JSONEncoder().encode(all) { UserDefaults.standard.set(d, forKey: key) }
    }

    /// A stop's last arrivals and when they were seen.
    static func load(stop: String) -> (at: Date, lines: [StopLine])? {
        guard let e = all[stop] else { return nil }
        return (e.at, e.lines.map {
            StopLine(line: $0.line, name: $0.name, nameEnglish: $0.nameEnglish, lineCode: "", routeCodes: [], arrivalsMinutes: $0.minutes, vehicles: [])
        })
    }
}
