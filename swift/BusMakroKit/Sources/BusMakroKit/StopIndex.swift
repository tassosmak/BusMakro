import Foundation

/// Every stop of every line, for searching by name (OASA has no stop-name search). Built from the
/// static line files, then cached for a day, as the Mac app's stop_index.py.
public struct StopIndex: Sendable {
    public struct Entry: Sendable, Codable {
        public let name: String
        public let lat: Double
        public let lon: Double
        public var lines: [String]
        var norm: String?
    }
    public let stops: [String: Entry]

    static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("stop_index.json")
    }
    static let maxAge: TimeInterval = 24 * 3600

    /// The last saved index, however old (for Siri and Shortcuts, which shouldn't download it all).
    public static func cached() -> StopIndex? {
        guard let data = try? Data(contentsOf: cacheURL),
              let stops = try? JSONDecoder().decode([String: Entry].self, from: data) else { return nil }
        return StopIndex(stops: stops)
    }

    /// From the cache when it is fresh, else downloaded (one file per line, 8 at a time).
    public static func load(lines: [String], transit: TransitClient = TransitClient()) async throws -> StopIndex {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
           let date = attrs[.modificationDate] as? Date, Date().timeIntervalSince(date) < maxAge,
           let data = try? Data(contentsOf: cacheURL),
           let stops = try? JSONDecoder().decode([String: Entry].self, from: data) {
            return StopIndex(stops: stops)
        }
        var stops: [String: Entry] = [:], failed = 0
        try await withThrowingTaskGroup(of: (String, LineDetail?).self) { group in
            var it = lines.makeIterator()
            func add() { if let id = it.next() { group.addTask { (id, try? await transit.detail(line: id)) } } }
            for _ in 0..<8 { add() }
            while let (id, detail) = try await group.next() {
                add()
                guard let detail else { failed += 1; continue }
                for (sid, s) in detail.stops {
                    var e = stops[sid] ?? Entry(name: s.name, lat: s.lat, lon: s.lon, lines: [], norm: nil)
                    if !e.lines.contains(id) { e.lines.append(id) }
                    stops[sid] = e
                }
            }
        }
        if stops.isEmpty { throw URLError(.cannotLoadFromNetwork) }
        if failed <= lines.count / 20 {  // don't keep an incomplete index for a day
            let normed = stops.mapValues { var e = $0; e.norm = Translit.normalize(e.name); return e }
            try? JSONEncoder().encode(normed).write(to: cacheURL)
            return StopIndex(stops: normed)
        }
        return StopIndex(stops: stops)
    }

    /// Stops whose name contains the query, best first: exact name, then word starts, then anywhere.
    public func search(_ query: String, limit: Int = 20) -> [(id: String, entry: Entry)] {
        let q = Translit.normalize(query)
        guard !q.isEmpty else { return [] }
        var exact: [(String, Entry)] = [], starts: [(String, Entry)] = [], contains: [(String, Entry)] = []
        for (sid, e) in stops {
            let n = e.norm ?? Translit.normalize(e.name)
            if n == q { exact.append((sid, e)) }
            else if n.hasPrefix(q) || n.contains(" " + q) { starts.append((sid, e)) }
            else if n.contains(q) || q == sid { contains.append((sid, e)) }
        }
        let byName: ((String, Entry), (String, Entry)) -> Bool = { $0.1.name < $1.1.name }
        return (exact.sorted(by: byName) + starts.sorted(by: byName) + contains.sorted(by: byName))
            .prefix(limit).map { (id: $0.0, entry: $0.1) }
    }
}
