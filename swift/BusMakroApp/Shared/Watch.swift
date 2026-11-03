import BusMakroKit
import Foundation
import UserNotifications
#if os(iOS)
import ActivityKit
#endif

/// Bus alerts: "notify me when this bus is N stops from my stop" (oasa/app/watch.py). The watch
/// keeps checking the line every 20 s, posts one notification, then ends; or ends quietly when the
/// bus passes the stop or disappears for 10 minutes. While a watch is set the app keeps location on
/// in the background, so the checks carry on with the app closed or the phone locked.
/// On iPhone a Live Activity shows the countdown on the lock screen and in the Dynamic Island,
/// from when the alert is set until the bus reaches the stop.
struct BusWatch: Hashable {
    let line: String, stop: String, stopName: String, stops: Int
    var seen = Date()
    /// The notification went out; the watch carries on to the stop for the Live Activity.
    var notified = false
}

extension Model {
    static let watchChoices = [1, 2, 3, 5]

    func watch(_ bus: String, stops n: Int?) {
        guard let n else {
            watches[bus] = nil; LiveBus.end(bus)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["watch-\(bus)"])
            return
        }
        guard case .line(let line, _) = screen, let stop = lineStop else { return }
        watches[bus] = BusWatch(line: line, stop: stop, stopName: lineDetail?.stops[stop]?.name ?? stop, stops: n)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        checkWatches(line: line, vehicles: vehicles)
        startWatchLoop()
    }

    /// Compare watched buses in a fresh response; notify (once) when one is close enough.
    func checkWatches(line: String, vehicles: [Vehicle], detail: LineDetail? = nil) {
        guard let detail = detail ?? lineDetail else { return }
        for (bus, w) in watches where w.line == line {
            guard let v = vehicles.first(where: { $0.id == bus }) else {
                if Date().timeIntervalSince(w.seen) > 600 { watches[bus] = nil; LiveBus.end(bus) }  // lost
                continue
            }
            watches[bus]?.seen = Date()
            guard let a = LineMath.approaching(w.stop, detail: detail, live: [v], official: w.stop == lineStop ? official : [:]).first else {
                watches[bus] = nil  // passed the stop
                LiveBus.end(bus, arrived: true)
                continue
            }
            LiveBus.update(bus, watch: w, stopsAway: a.stopsAway, seconds: a.seconds)
            if a.stopsAway > w.stops && !w.notified {
                // not yet: also book it for when the bus should get there, so it still comes if iOS
                // has suspended the app by then (each reading moves the booking; same identifier)
                let perStop = a.seconds / Double(max(1, a.stopsAway))
                let due = a.seconds - perStop * Double(w.stops)
                if due > 5 {
                    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "watch-\(bus)",
                        content: Self.alert(line: line, bus: bus, stopsAway: w.stops, stopName: w.stopName),
                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: due, repeats: false)))
                }
            }
            if a.stopsAway <= w.stops && !w.notified {
                let content = Self.alert(line: line, bus: bus, stopsAway: a.stopsAway, stopName: w.stopName)
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "watch-\(bus)", content: content, trigger: nil))
                if LiveBus.running(bus) { watches[bus]?.notified = true }  // keep the countdown going to the stop
                else { watches[bus] = nil }
            }
        }
    }

    static func alert(line: String, bus: String, stopsAway: Int, stopName: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Your \(line) is almost here")
        content.body = stopsAway == 0 ? String(localized: "Bus \(bus) is arriving at \(stopName) now.")
            : stopsAway == 1 ? String(localized: "Bus \(bus) is 1 stop away from \(stopName).")
            : String(localized: "Bus \(bus) is \(stopsAway) stops away from \(stopName).")
        content.sound = .default
        return content
    }

    func startWatchLoop() {
        guard watchTask == nil else { return }
        keepRunningInBackground(true)
        watchTask = Task { [weak self] in
            while let self, !self.watches.isEmpty {
                try? await Task.sleep(for: .seconds(20))
                for line in Set(self.watches.values.map(\.line)) {
                    if let live = try? await TransitClient().live(line: line),
                       let detail = try? await TransitClient().detail(line: line) {
                        self.checkWatches(line: line, vehicles: live.vehicles, detail: detail)
                    }
                }
            }
            self?.watchTask = nil
            self?.keepRunningInBackground(false)
        }
    }
}

/// The Live Activities of bus alerts, one per watched bus (iPhone only; no-ops elsewhere).
@MainActor
enum LiveBus {
    #if os(iOS)
    private static var activities: [String: Activity<BusActivityAttributes>] = [:]
    #endif

    static func running(_ bus: String) -> Bool {
        #if os(iOS)
        return activities[bus] != nil
        #else
        return false
        #endif
    }

    /// Start the activity on the first reading, then update it.
    static func update(_ bus: String, watch w: BusWatch, stopsAway: Int, seconds: Double) {
        #if os(iOS)
        let state = BusActivityAttributes.ContentState(stopsAway: stopsAway, arrival: Date().addingTimeInterval(max(0, seconds)))
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(60))  // the minutes go out of date after a minute
        if let a = activities[bus] {
            Task { await a.update(content) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            let attrs = BusActivityAttributes(line: w.line, bus: bus, stopID: w.stop, stopName: w.stopName, alertAt: w.stops)
            do { activities[bus] = try Activity.request(attributes: attrs, content: content) }
            catch { print("Live Activity failed: \(error)") }
        }
        #endif
    }

    /// End it: "Now" for a moment when the bus got there, else straight away.
    static func end(_ bus: String, arrived: Bool = false) {
        #if os(iOS)
        guard let a = activities.removeValue(forKey: bus) else { return }
        var state = a.content.state
        state.arrived = arrived
        Task { await a.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: arrived ? .after(.now + 120) : .immediate) }
        #endif
    }
}
