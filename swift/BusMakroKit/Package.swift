// swift-tools-version: 5.9
// BusMakroKit: the data side of BusMakro (models, OASA and live-bus clients, distances), shared by
// the coming SwiftUI apps for iPhone and Mac. `busmakro-check` is a small command-line smoke test
// against the live services: `swift run busmakro-check`.
import PackageDescription

let package = Package(
    name: "BusMakroKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "BusMakroKit", targets: ["BusMakroKit"])],
    targets: [
        .target(name: "BusMakroKit"),
        .executableTarget(name: "busmakro-check", dependencies: ["BusMakroKit"]),
    ]
)
