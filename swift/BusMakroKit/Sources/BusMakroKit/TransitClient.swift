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
        let (data, resp) = try await session.data(for: URLRequest(url: url, timeoutInterval: Self.patience))
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
            do { return try await get(Self.live.appendingPathComponent("v1/lines").appendingPathComponent(line), as: LineLive.self) }
            catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
            }
        }
        return LineLive(line: line, vehicles: try await OASAClient().buses(line: line))
    }
}
