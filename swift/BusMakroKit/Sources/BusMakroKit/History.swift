import Foundation

/// What BusMakro learns from watching OASA's predictions (kept on the device), as the Mac app's
/// history.py: following each bus from one reading of a stop to the next tells when it really
/// arrived (scoring the earlier predictions → learned times) or vanished without arriving (ghosts).
public final class History: @unchecked Sendable {
    public static let shared = History()
    static let gap: TimeInterval = 150, arrivedMin = 1.0, vanishedMin = 4.0
    static let maxSamples = 60, minSamples = 5, minEvents = 8
    static let buckets = [5.0, 10, 20]

    struct LineStats: Codable { var err: [String: [Double]] = [:]; var arrived = 0; var vanished = 0 }
    struct Open { var at: Date; var buses: [String: Bus] }
    struct Bus { var line: String; var lastMin: Double; var preds: [(Date, Date)] }

    private let lock = NSLock()
    private var lines: [String: LineStats]
    private var open: [String: Open] = [:]
    private var savedAt = Date.distantPast
    private let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("history.json")

    init() {
        lines = (try? JSONDecoder().decode([String: LineStats].self, from: Data(contentsOf: url))) ?? [:]
    }

    static func bucket(_ m: Double) -> String { String(buckets.firstIndex { m < $0 } ?? buckets.count) }

    /// Feed one reading of a stop: (line, vehicle, minutes).
    public func observe(stop: String, _ arrivals: [(line: String, vehicle: String, minutes: Double)], now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        var seen: [String: (String, Double)] = [:]
        for a in arrivals where !a.vehicle.isEmpty { seen[a.vehicle] = (a.line, a.minutes) }
        var keep: [String: Bus] = [:]
        if let prev = open[stop], now.timeIntervalSince(prev.at) <= Self.gap {
            for (veh, b) in prev.buses where seen[veh] == nil {
                var st = lines[b.line] ?? LineStats()
                if b.lastMin <= Self.arrivedMin {  // arrived: score every prediction made for it
                    let arrivedAt = prev.at.addingTimeInterval(b.lastMin * 60)
                    st.arrived += 1
                    for (tPred, predicted) in b.preds {
                        let horizon = arrivedAt.timeIntervalSince(tPred) / 60
                        guard horizon >= 0.5 else { continue }
                        var e = st.err[Self.bucket(horizon), default: []]
                        e.append(arrivedAt.timeIntervalSince(predicted).rounded())
                        st.err[Self.bucket(horizon)] = Array(e.suffix(Self.maxSamples))
                    }
                } else if b.lastMin >= Self.vanishedMin {
                    st.vanished += 1
                }
                lines[b.line] = st
            }
            keep = prev.buses
        }
        var buses: [String: Bus] = [:]
        for (veh, (line, m)) in seen {
            var b = keep[veh] ?? Bus(line: line, lastMin: m, preds: [])
            b.line = line; b.lastMin = m
            if b.preds.last.map({ now.timeIntervalSince($0.0) >= 55 }) ?? true {
                b.preds = Array((b.preds + [(now, now.addingTimeInterval(m * 60))]).suffix(30))
            }
            buses[veh] = b
        }
        open[stop] = Open(at: now, buses: buses)
        if now.timeIntervalSince(savedAt) > 60, let data = try? JSONEncoder().encode(lines) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url); savedAt = now
        }
    }

    /// OASA's prediction corrected by what was learned (never by more than half of it, or 5 min).
    public func learnedMinutes(line: String, minutes: Int) -> Int? {
        lock.lock(); defer { lock.unlock() }
        guard let errs = lines[line]?.err[Self.bucket(Double(minutes))], errs.count >= Self.minSamples else { return nil }
        let b = errs.sorted()[errs.count / 2]
        guard abs(b) >= 60 else { return nil }
        let cap = min(Double(minutes) * 30, 300)
        return max(0, Int((Double(minutes) + max(-cap, min(cap, b)) / 60).rounded()))
    }

    /// Share of predicted buses of a line that vanished, once there are enough events.
    public func ghostRate(line: String) -> Double? {
        lock.lock(); defer { lock.unlock() }
        guard let st = lines[line], st.arrived + st.vanished >= Self.minEvents else { return nil }
        return Double(st.vanished) / Double(st.arrived + st.vanished)
    }

    /// Two buses within 2 min of each other: a short warning, with the gap after them.
    public static func bunching(_ etas: [Int]) -> String? {
        guard etas.count >= 2, etas[1] - etas[0] <= 2 else { return nil }
        if etas.count > 2, etas[2] - etas[1] >= 10 {
            return String(localized: "2 together, then a \(etas[2] - etas[1]) min gap", bundle: .main)
        }
        return String(localized: "2 buses together", bundle: .main)
    }
}

extension OASAClient {
    /// The same readings the stop screen shows, fed to History (route codes mapped to lines).
    public func observe(stop: String, lines: [StopLine]) async {
        guard let arrivals = try? await stopArrivals(stopID: stop) else { return }
        var lineOf: [String: String] = [:]
        for l in lines { for c in l.routeCodes { lineOf[c] = l.line } }
        History.shared.observe(stop: stop, arrivals.compactMap { a in
            lineOf[a.route].map { ($0, a.vehicle, Double(a.minutes)) }
        })
    }
}
