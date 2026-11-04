import XCTest
@testable import BusMakroKit

/// The arrival maths behind the Arrivals tab, alerts and the Live Activity, on a made-up line:
/// six stops due north, ~333 m apart ("go"), and the same stops back ("back").
final class ApproachingTests: XCTestCase {
    static let ids = ["S0", "S1", "S2", "S3", "S4", "S5"]
    static func lat(_ i: Double) -> Double { 37.95 + 0.003 * i }
    let detail = LineDetail(
        id: "T1",
        variants: ["go": .init(headsign: "North", shape: [], stops: ids),
                   "back": .init(headsign: "South", shape: [], stops: ids.reversed())],
        stops: Dictionary(uniqueKeysWithValues: ids.enumerated().map { i, id in
            (id, LineDetail.StopInfo(name: "Stop \(i)", lat: lat(Double(i)), lon: 23.70))
        }))

    /// A bus heading north at stop-index position `at` (1.5 = halfway between S1 and S2).
    func bus(_ id: String, at: Double, variant: String = "go", seen: Date = Date()) -> Vehicle {
        Vehicle(id: id, latitude: Self.lat(at), longitude: 23.70, bearing: variant == "go" ? 0 : 180, positionAt: seen, variant: variant)
    }

    func testStopsLeftCountsTheStopsAhead() {
        let a = LineMath.approaching("S4", detail: detail, live: [bus("B", at: 1.5)], official: [:])
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a.first?.stopsAway, 2, "next stop S2, then S3, then S4")
    }

    func testStopsLeftGoesDownAsTheBusPassesStops() {
        // the bug where the count stayed put while the bus visibly passed stops
        let early = LineMath.approaching("S5", detail: detail, live: [bus("B", at: 0.5)], official: [:]).first?.stopsAway
        let later = LineMath.approaching("S5", detail: detail, live: [bus("B", at: 3.5)], official: [:]).first?.stopsAway
        XCTAssertNotNil(early); XCTAssertNotNil(later)
        XCTAssertLessThan(later!, early!)
    }

    func testMovedBusIsCountedFromWhereItIsDrawn() {
        let v = bus("B", at: 0.5)
        let moved = v.moved(to: Self.lat(3.5), 23.70, at: Date())
        XCTAssertNil(moved.nextStopID, "a moved bus drops the feed's old next stop")
        let a = LineMath.approaching("S5", detail: detail, live: [moved], official: [:]).first
        XCTAssertEqual(a?.stopsAway, 1)
    }

    func testBusPastTheStopIsNotComing() {
        let a = LineMath.approaching("S1", detail: detail, live: [bus("B", at: 3.5)], official: [:])
        XCTAssertTrue(a.isEmpty)
    }

    func testOfficialPredictionIsUsed() {
        let a = LineMath.approaching("S4", detail: detail, live: [bus("B", at: 1.5)], official: ["B": 7]).first
        XCTAssertEqual(a?.official, true)
        XCTAssertEqual(a?.seconds ?? 0, 420, accuracy: 0.1)
    }

    func testEstimateFollowsDistance() {
        let a = LineMath.approaching("S4", detail: detail, live: [bus("B", at: 1.5)], official: [:]).first
        XCTAssertEqual(a?.official, false)
        // ~2.5 stops of 333 m at the default pace
        let expected = (a?.metres ?? 0) / LineMath.defaultSpeed
        XCTAssertEqual(a?.seconds ?? 0, expected, accuracy: 5)
        XCTAssertEqual(a?.metres ?? 0, 833, accuracy: 40)
    }

    func testNearerBusComesFirstAndNeverLater() {
        let near = bus("N", at: 2.5), far = bus("F", at: 0.5)
        let a = LineMath.approaching("S4", detail: detail, live: [far, near], official: [:])
        XCTAssertEqual(a.map(\.vehicle.id), ["N", "F"])
        XCTAssertLessThanOrEqual(a[0].seconds, a[1].seconds)
    }

    func testOldPositionCountsDown() {
        // a fix a minute old: the bus has driven on since, so less time is left
        let fresh = LineMath.approaching("S4", detail: detail, live: [bus("B", at: 1.5)], official: [:]).first!
        let old = LineMath.approaching("S4", detail: detail, live: [bus("B", at: 1.5, seen: Date().addingTimeInterval(-60))], official: [:]).first!
        XCTAssertEqual(fresh.seconds - old.seconds, 60, accuracy: 2)
    }

    func testBusTurningAtTheTerminusCountsWhenOASAPredictsIt() {
        // going south towards S0, while we wait at S2 northbound: it turns round at S0 and comes back
        let v = bus("R", at: 1.5, variant: "back")
        XCTAssertTrue(LineMath.approaching("S2", detail: detail, live: [v], official: [:]).isEmpty, "no prediction: not counted")
        let a = LineMath.approaching("S2", detail: detail, live: [v], official: ["R": 12]).first
        XCTAssertEqual(a?.official, true)
        XCTAssertEqual(a?.stopsAway, 4, "S1, S0 (terminus), then S1, S2 again")
    }

    func testDistanceIsInMetres() {
        XCTAssertEqual(Geo.distance(37.95, 23.70, 37.953, 23.70), 333, accuracy: 3)
    }
}
