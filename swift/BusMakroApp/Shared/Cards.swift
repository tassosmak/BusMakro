import BusMakroKit
import SwiftUI

/// A stop: name and street on the left, distance and walk on the right; the nearest one's
/// distance in orange (the Mac app's "near" card).
struct StopCard: View {
    let stop: Stop
    let metres: Double?
    var closest = false
    var subtitle: String? = nil
    var favourite = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // at the Accessibility text sizes the distance goes under the name (side by side, both were cut off)
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        layout {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if favourite {
                        Image(systemName: "star.fill").font(.scaled(11)).foregroundStyle(.yellow)
                            .accessibilityLabel("Favourite")
                    }
                    Text(stop.title).font(.scaled(13, .semibold)).lineLimit(3)
                }
                Text(subtitle ?? ((stop.street.isEmpty ? "" : stop.street + " · ") + String(localized: "Stop \(stop.id)")))
                    .font(.scaled(12)).foregroundStyle(.subtle).lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            if let m = metres {
                VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                    Text(Geo.format(metres: m)).font(Style.rounded(20))
                        .foregroundStyle(closest ? .orange : .primary)
                    if m <= 2500 {  // "~192 min walk" helped no one: farther stops show just the distance
                        Text("~\(max(1, Int((m / 80).rounded()))) min walk")
                            .font(.scaled(11)).foregroundStyle(.subtle)
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .card()
        // one sentence: "Syntagma, Stop 10361, 70 metres, about 1 minute's walk, favourite"
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Speak.join([stop.title,
                                        subtitle ?? Speak.join([stop.street, String(localized: "Stop \(stop.id)")]),
                                        metres.map { Speak.distance($0) },
                                        metres.flatMap { $0 <= 2500 ? String(localized: "about \(Speak.minutes(max(1, Int(($0 / 80).rounded())))) walk") : nil },
                                        favourite ? String(localized: "Favourite") : nil]))
    }
}

/// A line at a stop: badge, name, and the next official arrival in green.
struct LineCard: View {
    let line: StopLine
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            LineBadge(line: line.line)
                .overlay(alignment: .topTrailing) {
                    if !line.arrivalsMinutes.isEmpty { PulseDot(fast: due).offset(x: 4, y: -4) }  // official live time
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(Names.place(line.name, line.nameEnglish))
                    .font(.scaled(13, .semibold)).lineLimit(typeSize.isAccessibilitySize ? 5 : 2)  // long route names wrap instead of being cut off
                Text(next).font(.scaled(11)).foregroundStyle(.subtle).lineLimit(typeSize.isAccessibilitySize ? 4 : 1)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Text(eta)
                .font(Style.rounded(18, .bold))
                .foregroundStyle(!line.arrivalsMinutes.isEmpty ? Color.green : line.scheduled != nil ? Color.orange : Color.secondary)
                .contentTransition(.numericText(countsDown: true))  // rolls to the new value, like the Mac app
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .card()
        .background(due ? Color.green.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: Style.cardRadius))
        // "Line 040, Peiraias - Syntagma, in 3 minutes, live, then 9 minutes, 22 minutes"
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Speak.join([String(localized: "Line \(line.line)"), Names.place(line.name, line.nameEnglish)]))
        .accessibilityValue(spoken)
    }

    private var spoken: String {
        if let m = line.arrivalsMinutes.first {
            let shown = History.shared.learnedMinutes(line: line.line, minutes: m) ?? m
            let rest = line.arrivalsMinutes.dropFirst().prefix(2).map { Speak.minutes($0) }
            var parts = [m <= 1 ? String(localized: "arriving now") : String(localized: "in \(Speak.minutes(shown))"), String(localized: "live")]
            if !rest.isEmpty { parts.append(String(localized: "then \(rest.joined(separator: ", "))")) }
            if let g = History.shared.ghostRate(line: line.line), g >= 0.25 { parts.append(String(localized: "\(Int(g * 100))% of buses don't arrive")) }
            return Speak.join(parts)
        }
        if let s = line.scheduled {
            return String(localized: "scheduled, arrives at \(Speak.time(s.arrive)), leaves the terminus at \(Speak.time(s.depart))")
        }
        return String(localized: "No more buses today")
    }

    /// Arriving now: the card glows green and its dot pulses faster.
    private var due: Bool { (line.arrivalsMinutes.first ?? 99) <= 1 }

    private static let clock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.timeZone = OASAClient.athens; return f
    }()

    /// Live minutes, or (no bus on the road yet) the clock time the timetable says it gets here.
    private var eta: String {
        if let m = line.arrivalsMinutes.first {
            let shown = History.shared.learnedMinutes(line: line.line, minutes: m) ?? m
            return shown <= 0 ? String(localized: "Now") : String(localized: "\(shown) min")
        }
        if let s = line.scheduled { return Self.clock.string(from: s.arrive) }
        return "—"
    }

    private var next: String {
        if line.arrivalsMinutes.isEmpty, let s = line.scheduled {
            let mins = max(0, Int(s.arrive.timeIntervalSinceNow / 60))
            return String(localized: "Scheduled · leaves the terminus \(Self.clock.string(from: s.depart)) · in about \(mins) min")
        }
        if line.arrivalsMinutes.isEmpty { return String(localized: "No more buses today") }
        let rest = line.arrivalsMinutes.dropFirst().prefix(2).map { String(localized: "\($0) min") }
        // the next times first: the hints after them got cut off (and the ghost emoji drew as "?")
        var hints: [String] = [rest.isEmpty ? String(localized: "Live") : String(localized: "then \(rest.joined(separator: ", "))")]
        if let m = line.arrivalsMinutes.first, History.shared.learnedMinutes(line: line.line, minutes: m) != nil {
            hints.append(String(localized: "learned · OASA says \(m) min"))
        }
        if let b = History.bunching(line.arrivalsMinutes) { hints.append(b) }
        if let g = History.shared.ghostRate(line: line.line), g >= 0.25 {
            hints.append(String(localized: "\(Int(g * 100))% of buses don't arrive"))
        }
        return hints.joined(separator: " · ")
    }
}

/// A line in search results: badge and name.
struct LineRow: View {
    let line: LineSummary
    /// Your nickname for the line, shown over its route name.
    var nickname: String? = nil
    var body: some View {
        HStack(spacing: 12) {
            LineBadge(line: line.id)
            VStack(alignment: .leading, spacing: 1) {
                if let nickname {
                    Text(nickname).font(.scaled(14, .semibold)).lineLimit(1)
                    Text(line.shown).font(.scaled(11)).foregroundStyle(.subtle).lineLimit(1)
                } else {
                    Text(line.shown).font(.scaled(13, .semibold)).lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
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
                    .font(.scaled(18)).foregroundStyle(tint).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(alert.title).font(.scaled(12, .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                    Text(meta).font(.scaled(11)).foregroundStyle(.subtle)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(alert.strike ? 0.16 : 0.14), in: RoundedRectangle(cornerRadius: Style.cardRadius))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Speak.join([alert.strike ? String(localized: "Strike") : String(localized: "Service notice"), alert.title,
                                        alert.lines.isEmpty ? String(localized: "whole network") : String(localized: "lines \(alert.lines.sorted().prefix(6).joined(separator: ", "))")]))
        .accessibilityHint(Text("Opens the notice on oasa.gr"))
        .accessibilityAddTraits(.isLink)
    }

    private var meta: String {
        let date = Self.day.string(from: alert.date)
        if alert.strike { return String(localized: "STRIKE · posted \(date) · tap to read") }
        if alert.lines.isEmpty { return String(localized: "\(date) · whole network · tap to read") }
        let ls = alert.lines.sorted()
        let list = ls.prefix(6).joined(separator: ", ")
        return ls.count == 1 ? String(localized: "\(date) · Line \(list) · tap to read") : String(localized: "\(date) · Lines \(list) · tap to read")
    }
}

/// A small green dot with a ring breathing out of it: "this is live" (the Mac app's pulse_dot).
/// Live: a few breaths then still; due now: keeps going, faster.
struct PulseDot: View {
    var fast = false
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(.green).frame(width: 8, height: 8)
                .scaleEffect(on ? 2.6 : 1).opacity(on ? 0 : 0.55)
            Circle().fill(.green).frame(width: 8, height: 8)
                .overlay(Circle().stroke(.white, lineWidth: 1.5))
        }
        .frame(width: 10, height: 10)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion, !LowPower.shared.on else { return }  // Reduce Motion, Low Power: a still dot
            withAnimation(.easeOut(duration: fast ? 1.1 : 2).repeatCount(fast ? 10_000 : 3, autoreverses: false)) { on = true }
        }
    }
}

/// Favourite stop subtitle: its next live arrivals ("046 4 min · 040 9 min").
func favouriteSubtitle(_ lines: [StopLine]?) -> String? {
    guard let lines else { return nil }
    let live = lines.filter { !$0.arrivalsMinutes.isEmpty }.sorted { $0.arrivalsMinutes[0] < $1.arrivalsMinutes[0] }.prefix(3)
    if live.isEmpty { return String(localized: "No live buses") }
    return live.map { "\($0.line) " + ($0.arrivalsMinutes[0] <= 0 ? String(localized: "now") : String(localized: "\($0.arrivalsMinutes[0]) min")) }.joined(separator: " · ")  // not "810 0 min"
}
