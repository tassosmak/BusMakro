import BusMakroKit
import SwiftUI
import WidgetKit

/// Home Screen widget: the next buses at your favourite stops (OASA's live predictions), without
/// opening the app. Small shows your first favourite, medium two, large four. Edit Widget picks one
/// stop instead, or a line's timetable on a day.
struct NextBusesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "NextBuses", intent: NextBusesConfig.self, provider: NextBusesProvider()) { entry in
            NextBusesView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next Buses")
        .description("The next buses at your favourite stops, or at one stop, or a line's timetable.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct NextBusesEntry: TimelineEntry {
    let date: Date
    /// When the times were fetched: each entry counts the minutes down from then.
    let fetched: Date
    let stops: [(stop: WidgetFavourites.Stop, lines: [StopLine])]
    /// Set when showing a line's timetable instead of stops.
    var timetable: (line: String, day: WidgetDay, directions: [WidgetTimetable.Direction])? = nil
    var noFavourites: Bool { stops.isEmpty && timetable == nil }

    /// A line's next arrival in minutes, as of this entry (gone once it has passed).
    func minutes(_ line: StopLine) -> Int? {
        let passed = Int(date.timeIntervalSince(fetched) / 60)
        return line.arrivalsMinutes.map { $0 - passed }.first { $0 >= 0 }
    }
}

struct NextBusesProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NextBusesEntry {
        let line = StopLine(line: "040", name: "", nameEnglish: "", lineCode: "", routeCodes: [], arrivalsMinutes: [4, 16], vehicles: [])
        return NextBusesEntry(date: .now, fetched: .now, stops: [(WidgetFavourites.Stop(id: "", title: "SYNTAGMA"), [line])])
    }

    func snapshot(for config: NextBusesConfig, in context: Context) async -> NextBusesEntry {
        context.isPreview ? placeholder(in: context) : await fetch(config, context.family)
    }

    /// Fetch once, then an entry a minute for the next 15 minutes counting down from it; iOS asks
    /// again after that (as often as its widget budget allows, usually every 15-30 minutes).
    func timeline(for config: NextBusesConfig, in context: Context) async -> Timeline<NextBusesEntry> {
        let first = await fetch(config, context.family)
        let entries = (0..<15).map { k in
            NextBusesEntry(date: first.fetched.addingTimeInterval(Double(k) * 60), fetched: first.fetched, stops: first.stops, timetable: first.timetable)
        }
        return Timeline(entries: entries, policy: .after(first.fetched.addingTimeInterval(15 * 60)))
    }

    private func fetch(_ config: NextBusesConfig, _ family: WidgetFamily) async -> NextBusesEntry {
        if config.show == .timetable, let line = config.line {
            let dirs = await WidgetTimetable.load(line: line.id, weekday: config.day.weekday)
            return NextBusesEntry(date: .now, fetched: .now, stops: [], timetable: (line.id, config.day, dirs))
        }
        let count = family == .systemSmall ? 1 : family == .systemMedium ? 2 : 4
        let favourites = config.show == .stop && config.stop != nil
            ? [WidgetFavourites.Stop(id: config.stop!.id, title: config.stop!.name)]
            : Array(WidgetFavourites.load().prefix(count))
        let oasa = OASAClient()
        var out: [(WidgetFavourites.Stop, [StopLine])] = []
        await withTaskGroup(of: (Int, [StopLine]).self) { group in
            for (i, s) in favourites.enumerated() {
                group.addTask { (i, (try? await oasa.stopLines(stopID: s.id)) ?? []) }
            }
            var found: [Int: [StopLine]] = [:]
            for await (i, lines) in group { found[i] = lines }
            out = favourites.enumerated().map { ($0.element, found[$0.offset] ?? []) }
        }
        return NextBusesEntry(date: .now, fetched: .now, stops: out)
    }
}

struct NextBusesView: View {
    let entry: NextBusesEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let t = entry.timetable {
            timetable(t.line, t.day, t.directions)
        } else if entry.noFavourites {
            VStack(spacing: 6) {
                Image(systemName: "star").font(.title2).foregroundStyle(.yellow)
                Text("Star a stop in BusMakro to see its next buses here.")
                    .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 10) {
                ForEach(entry.stops, id: \.stop.id) { s in
                    Link(destination: URL(string: "busmakro://stop/\(s.stop.id)")!) { stop(s.stop, s.lines) }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(URL(string: "busmakro://favourites"))
        }
    }

    private func stop(_ stop: WidgetFavourites.Stop, _ lines: [StopLine]) -> some View {
        let shown = lines.compactMap { l in entry.minutes(l).map { (l, $0) } }.sorted { $0.1 < $1.1 }
            .prefix(family == .systemSmall ? 3 : family == .systemMedium ? (entry.stops.count == 1 ? 4 : 2) : (entry.stops.count == 1 ? 8 : 3))
        return VStack(alignment: .leading, spacing: 4) {
            Text(stop.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
            if shown.isEmpty {
                Text("No live buses").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(Array(shown), id: \.0.line) { l, m in
                HStack(spacing: 8) {
                    Text(l.line)
                        .font(.system(.footnote, design: .rounded, weight: .bold)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(width: 44, height: 22)
                        .background(Color(red: 0.09, green: 0.47, blue: 1.0), in: RoundedRectangle(cornerRadius: 6))
                    Spacer(minLength: 0)
                    Text(m == 0 ? String(localized: "Now") : "\(m)'")
                        .font(.system(.body, design: .rounded, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(m <= 2 ? .green : .primary)
                }
            }
        }
    }

    /// A line's next departures from each end (today from now; another day from this time of day).
    private func timetable(_ line: String, _ day: WidgetDay, _ dirs: [WidgetTimetable.Direction]) -> some View {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = OASAClient.athens
        let now = cal.dateComponents([.hour, .minute], from: entry.date)
        let nowMinutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        let perDir = family == .systemSmall ? 3 : family == .systemMedium ? 4 : 10
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                LineBadgeSmall(line: line)
                Text(day.isToday ? String(localized: "Today") : day.localizedName).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            if dirs.isEmpty { Text("No timetable for this day").font(.footnote).foregroundStyle(.secondary) }
            HStack(alignment: .top, spacing: 12) {
                ForEach(dirs.prefix(family == .systemSmall ? 1 : 2), id: \.self) { d in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(d.name).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                        let next = d.times.filter {
                            let c = cal.dateComponents([.hour, .minute], from: $0)
                            return (c.hour ?? 0) * 60 + (c.minute ?? 0) >= nowMinutes
                        }
                        if next.isEmpty { Text("No more today").font(.footnote).foregroundStyle(.secondary) }
                        ForEach(next.prefix(perDir), id: \.self) { t in
                            Text(t, format: .dateTime.hour().minute()).font(.system(.body, design: .rounded, weight: .semibold)).monospacedDigit()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: "busmakro://line/\(line)"))
    }
}

/// The line number on the app's blue.
struct LineBadgeSmall: View {
    let line: String
    var body: some View {
        Text(line)
            .font(.system(.footnote, design: .rounded, weight: .bold)).foregroundStyle(.white)
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(width: 44, height: 22)
            .background(Color(red: 0.09, green: 0.47, blue: 1.0), in: RoundedRectangle(cornerRadius: 6))
    }
}

extension WidgetDay {
    var localizedName: String { String(localized: Self.caseDisplayRepresentations[self]!.title) }
}
