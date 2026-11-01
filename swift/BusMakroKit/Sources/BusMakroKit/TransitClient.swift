import Foundation

/// athens-transit-rt (by @angelospk): live buses (`transit.haroldpoi.dev`) and static line data.
public struct TransitClient: Sendable {
    public static let live = URL(string: "https://transit.haroldpoi.dev")!
    public static let staticBase = URL(string: "https://angelospk.github.io/athens-transit-rt/static/v1")!
    let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    private func get<T: Decodable>(_ url: URL, as: T.Type) async throws -> T {
        let (data, resp) = try await session.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Every line (static list).
    public func lines() async throws -> [LineSummary] {
        struct Wrapper: Decodable { let lines: [LineSummary] }
        return try await get(Self.staticBase.appendingPathComponent("lines.json"), as: Wrapper.self).lines
    }

    /// The buses of one line right now.
    public func live(line: String) async throws -> LineLive {
        try await get(Self.live.appendingPathComponent("v1/lines").appendingPathComponent(line), as: LineLive.self)
    }
}
