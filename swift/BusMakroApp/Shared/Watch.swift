import BusMakroKit
import Foundation
import UserNotifications

/// Bus alerts: "notify me when this bus is N stops from my stop" (oasa/app/watch.py). The watch
/// keeps checking the line every 20 s, posts one notification, then ends; or ends quietly when the
/// bus passes the stop or disappears for 10 minutes. On iPhone it runs while the app is open (and
/// briefly after); reliable background alerts would need push notifications from a server.
struct BusWatch: Hashable {
    let line: String, stop: String, stopName: String, stops: Int
    var seen = Date()
}

extension Model {
    static let watchChoices = [1, 2, 3, 5]

    func watch(_ bus: String, stops n: Int?) {
        guard let n else { watches[bus] = nil; return }
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
                if Date().timeIntervalSince(w.seen) > 600 { watches[bus] = nil }  // lost
                continue
            }
            watches[bus]?.seen = Date()
            guard let a = LineMath.approaching(w.stop, detail: detail, live: [v], official: [:]).first else {
                watches[bus] = nil  // passed the stop
                continue
            }
            if a.stopsAway <= w.stops {
                let content = UNMutableNotificationContent()
                content.title = String(localized: "Your \(line) is almost here")
                content.body = a.stopsAway == 0 ? String(localized: "Bus \(bus) is arriving at \(w.stopName) now.")
                    : a.stopsAway == 1 ? String(localized: "Bus \(bus) is 1 stop away from \(w.stopName).")
                    : String(localized: "Bus \(bus) is \(a.stopsAway) stops away from \(w.stopName).")
                content.sound = .default
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "watch-\(bus)", content: content, trigger: nil))
                watches[bus] = nil
            }
        }
    }

    func startWatchLoop() {
        guard watchTask == nil else { return }
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
        }
    }
}
