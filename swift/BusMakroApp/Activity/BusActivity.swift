#if os(iOS)
import ActivityKit
import Foundation

/// The Live Activity of a bus alert ("notify me when the bus is N stops away"): shared by the app,
/// which starts and updates it, and the widget extension, which draws it on the lock screen and
/// in the Dynamic Island.
struct BusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var stopsAway: Int
        /// When the bus should reach the stop: the lock screen counts down to it between updates.
        var arrival: Date
        /// Set once the bus is there (or the alert ended), for the last look before it closes.
        var arrived = false
    }

    let line: String
    let bus: String
    let stopID: String
    let stopName: String
    /// The alert fires at this many stops away.
    let alertAt: Int
}
#endif
