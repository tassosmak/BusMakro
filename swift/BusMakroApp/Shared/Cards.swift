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
            Text(line.arrivalsMinutes.first.map { "\($0) min" } ?? "—")
                .font(Style.rounded(18, .bold))
                .foregroundStyle(line.arrivalsMinutes.isEmpty ? Color.secondary : Color.green)
                .contentTransition(.numericText(countsDown: true))  // rolls to the new value, like the Mac app
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .card()
    }

    private var next: String {
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
