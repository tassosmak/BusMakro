import Foundation

/// A bus stop (OASA stop code as `id`).
public struct Stop: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let nameEnglish: String
    public let street: String
    public let latitude: Double
    public let longitude: Double

    public init(id: String, name: String, nameEnglish: String, street: String, latitude: Double, longitude: Double) {
        self.id = id; self.name = name; self.nameEnglish = nameEnglish; self.street = street
        self.latitude = latitude; self.longitude = longitude
    }
}

/// One line in the line list (static data).
public struct LineSummary: Identifiable, Hashable, Sendable, Decodable {
    public let id: String
    public let name: String
    public let nameEnglish: String?

    enum CodingKeys: String, CodingKey { case id, name, nameEnglish = "name_en" }
}

/// A bus on the road, as athens-transit-rt reports it (`/v1/lines/{id}`).
public struct Vehicle: Identifiable, Hashable, Sendable, Decodable {
    public let id: String
    public let latitude: Double
    public let longitude: Double
    public let bearing: Double?
    public let positionAt: Date?
    public let variant: String?
    public let nextStopID: String?
    public let delaySeconds: Int?
    /// m/s along the route; 0 = standing, nil = unknown.
    public let speed: Double?
    public let tripLabel: String?
    /// The road ahead to the next stop, as [latitude, longitude] pairs.
    public let path: [[Double]]?

    enum CodingKeys: String, CodingKey {
        case id, lat, lon, bearing, variant, speed, path
        case positionAt = "position_at", nextStopID = "next_stop_id", delaySeconds = "delay_s", tripLabel = "trip_label"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        latitude = try c.decode(Double.self, forKey: .lat)
        longitude = try c.decode(Double.self, forKey: .lon)
        bearing = try c.decodeIfPresent(Double.self, forKey: .bearing)
        positionAt = try c.decodeIfPresent(Double.self, forKey: .positionAt).map { Date(timeIntervalSince1970: $0) }
        variant = try c.decodeIfPresent(String.self, forKey: .variant)
        nextStopID = try c.decodeIfPresent(String.self, forKey: .nextStopID)
        delaySeconds = try c.decodeIfPresent(Int.self, forKey: .delaySeconds)
        speed = try c.decodeIfPresent(Double.self, forKey: .speed)
        tripLabel = try c.decodeIfPresent(String.self, forKey: .tripLabel)
        path = try c.decodeIfPresent([[Double]].self, forKey: .path)
    }
}

/// The live state of one line.
public struct LineLive: Sendable, Decodable {
    public let line: String
    public let vehicles: [Vehicle]
}

/// A line serving a stop, with OASA's next predictions (minutes), soonest first.
public struct StopLine: Identifiable, Hashable, Sendable {
    public var id: String { line }
    public let line: String
    public let name: String
    public let nameEnglish: String
    public let lineCode: String
    public var routeCodes: [String]
    public var arrivalsMinutes: [Int]
    /// The buses on their way here (vehicle codes).
    public var vehicles: [String]
}
