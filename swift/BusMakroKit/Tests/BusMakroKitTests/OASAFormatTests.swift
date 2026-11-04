import XCTest
@testable import BusMakroKit

/// OASA's answers as text or as numbers: in November 2026 it switched codes from "1151" to 1151,
/// and the timetables (which read them as text only) went empty.
final class OASAFormatTests: XCTestCase {
    func parsed(_ json: String) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
    }

    func testCodesAsTextOrNumbers() {
        let old = parsed(#"{"LineCode":"1151","RouteCode":"2045","hidden":"0"}"#)
        let new = parsed(#"{"LineCode":1151,"RouteCode":2045,"hidden":0}"#)
        for r in [old, new] {
            XCTAssertEqual(OASAClient.opt(r["LineCode"]), "1151")
            XCTAssertEqual(OASAClient.opt(r["RouteCode"]), "2045")
            XCTAssertEqual(OASAClient.str(r["hidden"]), "0")
        }
    }

    func testMissingAndEmpty() {
        let r = parsed(#"{"a":null,"b":""}"#)
        XCTAssertNil(OASAClient.opt(r["a"]))
        XCTAssertNil(OASAClient.opt(r["b"]))
        XCTAssertNil(OASAClient.opt(r["missing"]))
        XCTAssertEqual(OASAClient.str(r["missing"]), "")
    }

    func testDecimalsStayDecimals() {
        XCTAssertEqual(OASAClient.opt(parsed(#"{"d":22204.98}"#)["d"]), "22204.98")
    }

    func testBusOnTheRouteItDrives() {
        // an OASA-only bus (no feed variant) is put on the route whose road it is on, going its way
        let ids = ["S0", "S1", "S2"]
        let d = LineDetail(id: "T", variants: ["go": .init(headsign: "N", shape: [], stops: ids),
                                               "back": .init(headsign: "S", shape: [], stops: ids.reversed())],
                           stops: Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, .init(name: $1, lat: 37.95 + 0.003 * Double($0), lon: 23.7)) }))
        let north = Vehicle(id: "B", latitude: 37.9515, longitude: 23.7, bearing: 0, positionAt: nil, variant: "2045")
        let south = Vehicle(id: "C", latitude: 37.9515, longitude: 23.7, bearing: 180, positionAt: nil, variant: "2046")
        XCTAssertEqual(LineMath.bestVariant(for: north, detail: d), "go")
        XCTAssertEqual(LineMath.bestVariant(for: south, detail: d), "back")
        let far = Vehicle(id: "D", latitude: 38.2, longitude: 23.9, bearing: 0, positionAt: nil, variant: nil)
        XCTAssertNil(LineMath.bestVariant(for: far, detail: d), "nowhere near the line")
    }
}
