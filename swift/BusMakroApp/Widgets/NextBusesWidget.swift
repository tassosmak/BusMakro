import BusMakroKit
import SwiftUI
import WidgetKit

/// Home Screen widget: the next buses at your favourite stops (OASA's live predictions), without
/// opening the app. Small shows your first favourite, medium two, large four.
struct NextBusesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextBuses", provider: NextBusesProvider()) { entry in
            NextBusesView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next Buses")
        .description("The next buses at your favourite stops.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct NextBusesEntry: TimelineEntry {
    let date: Date
    /// When the times were fetched: each entry counts the minutes down from then.
    let fetched: Date
    let stops: [(stop: WidgetFavourites.Stop, lines: [StopLine])]
    var noFavourites: Bool { stops.isEmpty }

    /// A line's next arrival in minutes, as of this entry (gone once it has passed).
    func minutes(_ line: StopLine) -> Int? {
        let passed = Int(date.timeIntervalSince(fetched) / 60)
        return line.arrivalsMinutes.map { $0 - passed }.first { $0 >= 0 }
    }
}

struct NextBusesProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextBusesEntry {
        let line = StopLine(line: "040", name: "", nameEnglish: "", lineCode: "", routeCodes: [], arrivalsMinutes: [4, 16], vehicles: [])
        return NextBusesEntry(date: .now, fetched: .now, stops: [(WidgetFavourites.Stop(id: "", title: "SYNTAGMA"), [line])])
    }

    func getSnapshot(in context: Context, completion: @escaping (NextBusesEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        Task { completion(await fetch(context.family)) }
    }

    /// Fetch once, then an entry a minute for the next 15 minutes counting down from it; iOS asks
    /// again after that (as often as its widget budget allows, usually every 15-30 minutes).
    func getTimeline(in context: Context, completion: @escaping (Timeline<NextBusesEntry>) -> Void) {
        Task {
            let first = await fetch(context.family)
            let entries = (0..<15).map { k in
                NextBusesEntry(date: first.fetched.addingTimeInterval(Double(k) * 60), fetched: first.fetched, stops: first.stops)
            }
            completion(Timeline(entries: entries, policy: .after(first.fetched.addingTimeInterval(15 * 60))))
        }
    }

    private func fetch(_ family: WidgetFamily) async -> NextBusesEntry {
        let count = family == .systemSmall ? 1 : family == .systemMedium ? 2 : 4
        let favourites = Array(WidgetFavourites.load().prefix(count))
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
        if entry.noFavourites {
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
            .prefix(family == .systemSmall ? 3 : family == .systemMedium ? 2 : 3)
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
}
