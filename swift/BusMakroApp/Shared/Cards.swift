import BusMakroKit
import SwiftUI

/// A stop: name and street on the left, distance and walk on the right; the nearest one's
/// distance in orange (the Mac app's "near" card).
struct StopCard: View {
    let stop: Stop
    let metres: Double?
    var closest = false
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(stop.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(subtitle ?? ((stop.street.isEmpty ? "" : stop.street + " · ") + "Stop \(stop.id)"))
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let m = metres {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Geo.format(metres: m)).font(Style.rounded(20))
                        .foregroundStyle(closest ? .orange : .primary)
                    Text("~\(max(1, Int((m / 80).rounded()))) min walk")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 64)
        .card()
    }
}

/// A line at a stop: badge, name, and the next official arrival in green.
struct LineCard: View {
    let line: StopLine

    var body: some View {
        HStack(spacing: 12) {
            LineBadge(line: line.line)
            VStack(alignment: .leading, spacing: 3) {
                Text(line.nameEnglish.isEmpty ? line.name : line.nameEnglish)
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(next).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(eta)
                .font(Style.rounded(18, .bold))
                .foregroundStyle(!line.arrivalsMinutes.isEmpty ? Color.green : line.scheduled != nil ? Color.orange : Color.secondary)
                .contentTransition(.numericText(countsDown: true))  // rolls to the new value, like the Mac app
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .card()
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.timeZone = OASAClient.athens; return f
    }()

    /// Live minutes, or (no bus on the road yet) the clock time the timetable says it gets here.
    private var eta: String {
        if let m = line.arrivalsMinutes.first { return "\(m) min" }
        if let s = line.scheduled { return Self.clock.string(from: s.arrive) }
        return "—"
    }

    private var next: String {
        if line.arrivalsMinutes.isEmpty, let s = line.scheduled {
            let mins = max(0, Int(s.arrive.timeIntervalSinceNow / 60))
            return "Scheduled · leaves the terminus \(Self.clock.string(from: s.depart)) · in about \(mins) min"
        }
        if line.arrivalsMinutes.isEmpty { return "No more buses today" }
        let rest = line.arrivalsMinutes.dropFirst().prefix(2).map { "\($0) min" }
        return rest.isEmpty ? (line.arrivalsMinutes.isEmpty ? "No live bus" : "Live") : "then " + rest.joined(separator: ", ")
    }
}

/// A line in search results: badge and name.
struct LineRow: View {
    let line: LineSummary
    var body: some View {
        HStack(spacing: 12) {
            LineBadge(line: line.id)
            Text(line.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .card()
    }
}

/// An OASA notice: orange ⚠︎ card (red ⛔︎ for strikes); tapping opens it on oasa.gr.
struct AlertCard: View {
    let alert: ServiceAlert
    @Environment(\.openURL) private var openURL
    private static let day: DateFormatter = { let f = DateFormatter(); f.dateFormat = "dd/MM"; return f }()

    var body: some View {
        let tint: Color = alert.strike ? .red : .orange
        Button { if let u = URL(string: alert.link), u.scheme == "https" { openURL(u) } } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: alert.strike ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 18)).foregroundStyle(tint).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(alert.title).font(.system(size: 12, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                    Text(meta).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(alert.strike ? 0.16 : 0.14), in: RoundedRectangle(cornerRadius: Style.cardRadius))
        }
        .buttonStyle(.plain)
    }

    private var meta: String {
        let date = Self.day.string(from: alert.date)
        if alert.strike { return "STRIKE · posted \(date) · tap to read" }
        if alert.lines.isEmpty { return "\(date) · whole network · tap to read" }
        let ls = alert.lines.sorted()
        return "\(date) · \(ls.count == 1 ? "Line" : "Lines") \(ls.prefix(6).joined(separator: ", ")) · tap to read"
    }
}
