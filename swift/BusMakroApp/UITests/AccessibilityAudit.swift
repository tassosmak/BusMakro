import XCTest

/// Apple's accessibility audit (missing labels, contrast, small targets, clipped text) on each
/// main screen. Opens screens through busmakro:// links; needs the network for live data.
final class AccessibilityAudit: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.tassosmak.busmakro")

    override func setUp() {
        continueAfterFailure = true
        app.launchArguments += ["-onboarded", "YES"]
        app.launch()
        sleep(6)
    }

    private func open(_ link: String) {
        XCUIDevice.shared.system.open(URL(string: link)!)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let openButton = springboard.buttons["Open"]
        if openButton.waitForExistence(timeout: 3) { openButton.tap() }
        sleep(8)
    }

    private func audit(_ name: String) throws {
        try app.performAccessibilityAudit { issue in
            // the map's own street names and the system status bar aren't ours to fix
            if let e = issue.element, e.elementType == .map || e.label == "Legal" || e.identifier.hasPrefix("MKAnnotationView") { return true }
            print("AUDIT[\(name)] \(issue.auditType) · \(issue.compactDescription) · \(issue.element?.debugDescription.prefix(160) ?? "")")
            return false
        }
    }

    func testHome() throws { try audit("home") }
    func testStop() throws { open("busmakro://stop/60991"); try audit("stop") }
    func testLine() throws { open("busmakro://line/040"); try audit("line") }
    func testStation() throws { open("busmakro://station/R115"); try audit("station") }
    func testTrip() throws { open("busmakro://plan"); try audit("trip") }
}
