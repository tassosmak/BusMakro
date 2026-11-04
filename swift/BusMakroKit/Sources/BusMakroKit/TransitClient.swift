import Foundation

/// athens-transit-rt (by @angelospk): live buses (`transit.haroldpoi.dev`) and static line data.
public struct TransitClient: Sendable {
    public static let live = URL(string: "https://transit.haroldpoi.dev")!
    public static let staticBase = URL(string: "https://angelospk.github.io/athens-transit-rt/static/v1")!
    let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    /// How long to wait for athens-transit-rt before turning to OASA.
    static let patience: TimeInterval = 8

    private func get<T: Decodable>(_ url: URL, as: T.Type) async throws -> T {
        // never from the phone's cache: the server says keep answers 67 s, which froze live buses
        // for a minute however often we asked
        let (data, resp) = try await session.data(for: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.patience))
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Every line: the static list, plus the lines only OASA knows (some express lines, like Χ25);
    /// OASA's list alone when the static one can't be had.
    public func lines() async throws -> [LineSummary] {
        struct Wrapper: Decodable { let lines: [LineSummary] }
        async let main = try? get(Self.staticBase.appendingPathComponent("lines.json"), as: Wrapper.self).lines
        async let backup = try? OASAClient().lineList()
        let (a, b) = await (main, backup)
        guard let a else { if let b, !b.isEmpty { return b }; throw URLError(.cannotConnectToHost) }
        let known = Set(a.map(\.id))
        return a + (b ?? []).filter { !known.contains($0.id) }
    }

    /// The buses of one line right now; from OASA when athens-transit-rt is down, or when the line's
    /// route came from OASA (its variants are OASA's route codes, so the buses must be too).
    public func live(line: String) async throws -> LineLive {
        if await !OASABackup.shared.isUsed(line) {
            // both at once: athens-transit-rt for each bus's road ahead and pace, OASA for where it is
            let oasa = Task { try? await OASAClient().buses(line: line) }
            do {
                let live = try await get(Self.live.appendingPathComponent("v1/lines").appendingPathComponent(line), as: LineLive.self)
                let fixes = await Self.within(3, oasa)
                var out = fresher(live, oasa: fixes)
                // buses OASA sees that the feed doesn't (in November 2026 the feed sent none at all):
                // added on the route they're driving, so arrivals and the map still have them
                let known = Set(out.vehicles.map(\.id))
                let missing = (fixes ?? []).filter { !known.contains($0.id) }
                if !missing.isEmpty, let d = try? await detail(line: line) {
                    out = LineLive(line: line, vehicles: out.vehicles + missing.compactMap { o in
                        LineMath.bestVariant(for: o, detail: d).map {
                            Vehicle(id: o.id, latitude: o.latitude, longitude: o.longitude, bearing: o.bearing, positionAt: o.positionAt, variant: $0)
                        }
                    })
                }
                return out
            }
            catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
            }
        }
        return LineLive(line: line, vehicles: try await OASAClient().buses(line: line))
    }

    /// A task's result, or nil if it takes longer than `seconds` (OASA slow: the buses show anyway).
    static func within<T: Sendable>(_ seconds: Double, _ task: Task<T?, Never>) async -> T? {
        await withTaskGroup(of: T?.self) { g in
            g.addTask { await task.value }
            g.addTask { try? await Task.sleep(for: .seconds(seconds)); return nil }
            let first = await g.next() ?? nil
            g.cancelAll()
            return first
        }
    }

    /// athens-transit-rt's positions run 1-2 minutes behind OASA's (measured: 70-130 s against
    /// 2-37 s), so every bus takes OASA's fix when it is newer, keeping the feed's road and pace.
    private func fresher(_ live: LineLive, oasa: [Vehicle]?) -> LineLive {
        guard let oasa, !oasa.isEmpty else { return live }
        let byID = Dictionary(oasa.map { ($0.id, $0) }, uniquingKeysWith: { a, b in (a.positionAt ?? .distantPast) > (b.positionAt ?? .distantPast) ? a : b })
        return LineLive(line: live.line, vehicles: live.vehicles.map { v in
            guard let o = byID[v.id], let t = o.positionAt, t > (v.positionAt ?? .distantPast) else { return v }
            return v.moved(to: o.latitude, o.longitude, at: t, bearing: o.bearing)
        })
    }
}
