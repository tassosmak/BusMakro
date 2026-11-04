import Foundation

/// Where to draw a bus between GPS fixes, with the Mac app's rules (map.html):
/// drive only along `path` (the road to its next stop) at `path_speeds`, from `position_at`, for at
/// most 90 s, and only when it's moving; a new fix that lands up to 150 m behind the drawn marker
/// holds the marker there instead of sliding it back.
public enum Movement {
    public static let maxDeadReckoning: TimeInterval = 240  // the feed's fixes are often 60-120 s old; 90 s froze them
    public static let holdMetres = 150.0

    /// A route as (latitude, longitude) points with cumulative metres.
    public struct Route: Sendable {
        public let pts: [(Double, Double)]
        public let cum: [Double]
        let speeds: [Double?]
        let speed: Double?
        public var total: Double { cum.last ?? 0 }
    }

    /// A route through these [latitude, longitude] points (nil with fewer than two).
    static func make(_ points: [[Double]], speed: Double? = nil) -> Route? {
        guard points.count >= 2 else { return nil }
        let pts = points.map { ($0[0], $0[1]) }
        var cum = [0.0]
        for i in 1..<pts.count { cum.append(cum[i - 1] + Geo.distance(pts[i - 1].0, pts[i - 1].1, pts[i].0, pts[i].1)) }
        return Route(pts: pts, cum: cum, speeds: [], speed: speed)
    }

    public static func route(for v: Vehicle) -> Route? {
        // the road to the next stop, then on past it: GPS fixes arrive 30-50 s old, so a bus driven
        // only to its next stop had usually already reached it and sat still until the next fix
        let joined = (v.path ?? []) + (v.pathBeyond ?? []).dropFirst((v.path?.isEmpty ?? true) ? 0 : 1)
        guard joined.count >= 2 else { return nil }
        let pts = joined.map { ($0[0], $0[1]) }
        var cum = [0.0]
        for i in 1..<pts.count { cum.append(cum[i - 1] + Geo.distance(pts[i - 1].0, pts[i - 1].1, pts[i].0, pts[i].1)) }
        let moving = (v.speed ?? 0) > 0
        return Route(pts: pts, cum: cum, speeds: v.pathSpeeds ?? [], speed: moving ? v.speed : nil)
    }

    /// Metres along the route after `secs`, at the step speeds (a missing step at `speed`, or 1.5 m/s).
    static func travelled(_ r: Route, _ secs: Double) -> Double {
        var d = 0.0, t = secs, i = 0
        while d < r.total {
            let seg = min(200, r.total - d)
            let v = (i < r.speeds.count ? r.speeds[i] : nil) ?? r.speed ?? 1.5
            let dt = seg / v
            if t <= dt { return d + t * v }
            d += seg; t -= dt; i += 1
        }
        return r.total
    }

    public static func point(_ r: Route, at d: Double) -> (Double, Double) {
        var i = 1
        while i < r.pts.count - 1 && r.cum[i] < d { i += 1 }
        let a = r.pts[i - 1], b = r.pts[i], seg = r.cum[i] - r.cum[i - 1]
        let f = seg > 0 ? min(1, max(0, (d - r.cum[i - 1]) / seg)) : 1
        return (a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f)
    }

    /// Where `p` lies along the route: (metres from it, metres along it).
    public static func along(_ r: Route, _ p: (Double, Double)) -> (off: Double, d: Double) {
        var best = (off: Double.infinity, d: 0.0)
        for i in 1..<r.pts.count {
            let a = r.pts[i - 1], b = r.pts[i], k = cos(a.0 * .pi / 180)
            let bx = (b.1 - a.1) * k, by = b.0 - a.0, px = (p.1 - a.1) * k, py = p.0 - a.0
            let L = bx * bx + by * by
            let f = L > 0 ? max(0, min(1, (px * bx + py * by) / L)) : 0
            let off = hypot(px - bx * f, py - by * f) * 111_320
            if off < best.off { best = (off, r.cum[i - 1] + (r.cum[i] - r.cum[i - 1]) * f) }
        }
        return best
    }

    /// The bus's position now: its fix, or driven along its road (never behind `hold` metres).
    public static func position(_ v: Vehicle, route: Route?, hold: Double, now: Date = Date()) -> (Double, Double) {
        guard let r = route else { return (v.latitude, v.longitude) }
        let age = v.positionAt.map { now.timeIntervalSince($0) } ?? 0
        let secs = r.speed != nil ? min(max(0, age), maxDeadReckoning) : 0
        let ahead = travelled(r, secs)
        // held ahead of the fix: carry on from there at half pace (not frozen until the fix catches
        // up: a bus that had stopped at a stop sat still on the map long after it drove off)
        return point(r, at: hold > 0 ? max(ahead, hold + ahead * 0.5) : ahead)
    }

    /// How far along the new route to hold a marker drawn at `drawn` (0 = don't hold).
    public static func hold(drawn: (Double, Double), on r: Route?) -> Double {
        guard let r else { return 0 }
        let a = along(r, drawn)
        return a.off < 40 && a.d > 0 && a.d <= holdMetres ? a.d : 0
    }
}
