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

    public init(id: String, name: String = "", nameEnglish: String? = nil) {
        self.id = id; self.name = name; self.nameEnglish = nameEnglish
    }

    /// The English name when there is one (the static data often has "" there), else the Greek one.
    public var title: String { (nameEnglish ?? "").isEmpty ? name : nameEnglish! }
}

/// A bus on the road, as athens-transit-rt reports it (`/v1/lines/{id}`).
public struct Vehicle: Identifiable, Hashable, Sendable, Decodable {
    public let id: String
    public private(set) var latitude: Double
    public private(set) var longitude: Double
    public private(set) var bearing: Double?
    public private(set) var positionAt: Date?
    public let variant: String?
    public private(set) var nextStopID: String?
    public let delaySeconds: Int?
    /// m/s along the route; 0 = standing, nil = unknown.
    public private(set) var speed: Double?
    public let tripLabel: String?
    /// The road ahead to the next stop, as [latitude, longitude] pairs.
    public private(set) var path: [[Double]]?
    /// The road on from the end of `path` to the third stop ahead.
    public private(set) var pathBeyond: [[Double]]?
    /// Typical speed (m/s) per 200 m ahead; a nil step means unknown.
    public private(set) var pathSpeeds: [Double?]?

    enum CodingKeys: String, CodingKey {
        case id, lat, lon, bearing, variant, speed, path, pathSpeeds = "path_speeds", pathBeyond = "path_beyond"
        case positionAt = "position_at", nextStopID = "next_stop_id", delaySeconds = "delay_s", tripLabel = "trip_label"
    }

    /// A bus from OASA's own feed (the backup): a position and heading, nothing about the road ahead.
    public init(id: String, latitude: Double, longitude: Double, bearing: Double?, positionAt: Date?, variant: String?) {
        self.id = id; self.latitude = latitude; self.longitude = longitude; self.bearing = bearing
        self.positionAt = positionAt; self.variant = variant
        nextStopID = nil; delaySeconds = nil; speed = nil; tripLabel = nil; path = nil; pathBeyond = nil; pathSpeeds = nil
    }

    /// A bus known only from OASA (no road from the feed): given the road ahead from its route's
    /// shape, so it glides between OASA's fixes (20-40 s apart) instead of sitting still and jumping.
    /// It only drives on while its fix is fresh and it isn't waiting at the start of its route.
    public func onRoad(_ shape: [[Double]], start: (Double, Double)?, ahead: Double = 1500) -> Vehicle {
        guard let r = Movement.make(shape) else { return self }
        let a = Movement.along(r, (latitude, longitude))
        guard a.off < 60 else { return self }
        var v = self
        let i = r.cum.firstIndex { $0 > a.d } ?? r.pts.count
        let end = r.cum.firstIndex { $0 > a.d + ahead } ?? r.pts.count
        v.path = [[latitude, longitude]] + r.pts[i..<max(i, end)].map { [$0.0, $0.1] }
        let fresh = positionAt.map { Date().timeIntervalSince($0) < 90 } ?? false
        let atStart = start.map { Geo.distance(latitude, longitude, $0.0, $0.1) < 60 } ?? false
        v.speed = fresh && !atStart ? LineMath.defaultSpeed * 0.8 : nil  // a little under the usual pace: never far ahead of it
        return v
    }

    /// The same bus at a newer fix (from OASA, when the feed's is stale): its road starts again from
    /// there, and a bus the feed thought standing that has clearly moved drives on at a typical pace.
    public func moved(to lat: Double, _ lon: Double, at when: Date, bearing: Double? = nil) -> Vehicle {
        var v = self
        // the feed's next stop belongs to its older fix: worked out again from here
        v.nextStopID = nil
        if let bearing { v.bearing = bearing }
        let r = Movement.route(for: self)
        let a = r.map { Movement.along($0, (lat, lon)) }
        if let r, let a, a.off < 60 {
            let i = r.cum.firstIndex { $0 > a.d } ?? r.pts.count
            v.path = [[lat, lon]] + r.pts[i...].map { [$0.0, $0.1] }
            v.pathBeyond = nil
            v.pathSpeeds = pathSpeeds.map { Array($0.dropFirst(Int(a.d / 200))) }
        } else {
            v.path = nil; v.pathBeyond = nil; v.pathSpeeds = nil  // off its road: just the fix
        }
        if (speed ?? 0) <= 0, Geo.distance(latitude, longitude, lat, lon) > 40 { v.speed = LineMath.defaultSpeed }
        v.latitude = lat; v.longitude = lon; v.positionAt = when
        return v
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
        pathBeyond = try c.decodeIfPresent([[Double]].self, forKey: .pathBeyond)
        pathSpeeds = try c.decodeIfPresent([Double?].self, forKey: .pathSpeeds)
    }
}

/// The live state of one line.
public struct LineLive: Sendable, Decodable {
    public let line: String
    public let vehicles: [Vehicle]
    public init(line: String, vehicles: [Vehicle]) { self.line = line; self.vehicles = vehicles }
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
    /// Route code → "1" (outbound) or "2" (return), for timetable estimates.
    public var routeTypes: [String: String] = [:]
    /// No bus on the road: the timetable's next arrival here (a rough estimate).
    public var scheduled: Scheduled?

    public init(line: String, name: String, nameEnglish: String, lineCode: String, routeCodes: [String],
                arrivalsMinutes: [Int], vehicles: [String]) {
        self.line = line; self.name = name; self.nameEnglish = nameEnglish; self.lineCode = lineCode
        self.routeCodes = routeCodes; self.arrivalsMinutes = arrivalsMinutes; self.vehicles = vehicles
    }
}

/// A timetable-based arrival: departure from the terminus and about when it gets here.
public struct Scheduled: Hashable, Sendable {
    public let depart: Date
    public let arrive: Date
}
