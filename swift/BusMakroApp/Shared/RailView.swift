import BusMakroKit
import MapKit
import SwiftUI

/// Metro and tram: the lines and stations on the map, and a station's next trains in the panel.
/// Trains have no live positions, so the times are STASY's timetable (marked "scheduled").

extension Rail {
    /// Shipped with the app (Rail.json, from tools/build_rail.py).
    static let shared: Rail? = Bundle.main.url(forResource: "Rail", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }.flatMap { try? Rail.load($0) }
}

extension Rail.Station {
    var shown: String { Names.place(name, nameEnglish) }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

extension Rail.Line {
    var tint: Color { Color(hex: color) }
    var shown: String { Names.greek ? name : nameEnglish }
}

extension Color {
    init(hex: String) {
        let v = UInt64(hex.dropFirst(), radix: 16) ?? 0x666666
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

extension Model {
    func openStation(_ id: String) {
        searchActive = false
        screen = .station(id)
    }

    /// Stations whose name matches the search (Greek or Latin letters).
    var stationResults: [(id: String, station: Rail.Station)] {
        let q = Translit.normalize(searchText)
        guard q.count >= 2, let rail = Rail.shared else { return [] }
        var out: [(id: String, station: Rail.Station)] = []
        for (id, s) in rail.stations where Translit.normalize(s.name).contains(q) || Translit.normalize(s.nameEnglish).contains(q) {
            out.append((id, s))
        }
        out.sort { $0.station.name < $1.station.name }
        return Array(out.prefix(5))
    }
}

/// A line's badge: "M1" in its colour, or "T6" for the tram.
struct RailBadge: View {
    let line: String
    var small = false
    var body: some View {
        Text(line)
            .font(.system(size: small ? 10 : 13, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            .frame(minWidth: small ? 22 : 34).frame(height: small ? 16 : 24).padding(.horizontal, small ? 2 : 4)
            .background(Rail.shared?.line(line)?.tint ?? .gray, in: RoundedRectangle(cornerRadius: small ? 4 : 6))
            .accessibilityLabel(Text(Rail.shared?.line(line)?.shown ?? line))
    }
}

/// A station on the map: a white square with the colour of its (first) line.
struct StationPin: View {
    let station: Rail.Station
    var selected = false
    var body: some View {
        let tram = station.lines.allSatisfy { $0.hasPrefix("T") }
        Image(systemName: tram ? "tram.fill" : "m.square.fill")
            .font(.system(size: selected ? 15 : 11, weight: .bold))
            .foregroundStyle(Rail.shared?.line(station.lines.first ?? "")?.tint ?? .gray)
            .frame(width: selected ? 26 : 18, height: selected ? 26 : 18)
            .background(.white, in: RoundedRectangle(cornerRadius: selected ? 7 : 5))
            .overlay(RoundedRectangle(cornerRadius: selected ? 7 : 5).stroke(selected ? Color.orange : .black.opacity(0.15), lineWidth: selected ? 2.5 : 1))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .animation(.smooth(duration: 0.25), value: selected)
            .frame(width: 40, height: 40).contentShape(Rectangle())
    }
}

/// The panel for a station: its lines, then the next trains each way.
struct StationContent: View {
    @Bindable var model: Model
    let id: String
    @State private var now = Date()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        if let rail = Rail.shared, let st = rail.stations[id] {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(st.shown.uppercased()).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(st.lines, id: \.self) { RailBadge(line: $0, small: true) }
                    if let m = model.userLocation.map({ Geo.distance($0.latitude, $0.longitude, st.lat, st.lon) }) {
                        Spacer()
                        Text(Geo.format(metres: m)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                ScrollView {
                    LazyVStack(spacing: 6) {
                        let groups = grouped(rail.next(at: id, from: now, count: 4))
                        if groups.isEmpty {
                            Text("No more trains today.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 20)
                        }
                        ForEach(Array(groups.enumerated()), id: \.element.key) { i, g in
                            TrainCard(line: g.line, to: g.to, departures: g.deps).appearing(i)
                        }
                        Text("Scheduled times from STASY's timetable: trains have no live data.")
                            .font(.system(size: 10)).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity).padding(.top, 6)
                    }
                }
            }
            .onReceive(timer) { now = $0 }
        }
    }

    private func grouped(_ deps: [Rail.Departure]) -> [(key: String, line: String, to: String, deps: [Rail.Departure])] {
        var order: [String] = [], by: [String: [Rail.Departure]] = [:]
        for d in deps {
            let k = "\(d.line)|\(d.direction)"
            if by[k] == nil { order.append(k) }
            by[k, default: []].append(d)
        }
        return order.map { k in (k, by[k]![0].line, by[k]![0].to, by[k]!) }
    }
}

/// One line and direction at a station: "M1 → Κηφισιά" and its next trains.
struct TrainCard: View {
    let line: String, to: String
    let departures: [Rail.Departure]

    var body: some View {
        HStack(spacing: 10) {
            RailBadge(line: line)
            VStack(alignment: .leading, spacing: 2) {
                Text("→ \(Names.place(to, Rail.shared?.stations.values.first { $0.name == to }?.nameEnglish))")
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(departures.dropFirst().map { $0.at.formatted(date: .omitted, time: .shortened) }.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if let first = departures.first {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(first.minutes == 0 ? String(localized: "Now") : String(localized: "\(first.minutes) min"))
                        .font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
                    Text(first.at.formatted(date: .omitted, time: .shortened)).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: Style.cardRadius))
        .accessibilityElement(children: .combine)
    }
}

/// The metro and tram lines on the map (straight between stations: the feed has no track shapes).
struct RailMapLayer: MapContent {
    let rail: Rail
    let selected: String?
    /// Zoomed far out only the lines show (the station squares would cover them), and the selected one.
    var stations = true
    /// Which kinds to draw ("metro", "tram"): the map's layer options.
    var kinds: Set<String> = ["metro", "tram"]
    let onTap: (String) -> Void

    var body: some MapContent {
        ForEach(rail.lines.filter { kinds.contains($0.kind) }) { line in
            if let dir = line.dirs.first {
                let coords = dir.stations.compactMap { rail.stations[$0]?.coordinate }
                MapPolyline(coordinates: coords).stroke(line.tint.opacity(0.75), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
        }
        ForEach(Array(rail.stations.keys).sorted(), id: \.self) { id in
            if let st = rail.stations[id], (stations && st.lines.contains { l in rail.line(l).map { kinds.contains($0.kind) } ?? false })
                || id == selected {
                Annotation("", coordinate: st.coordinate) {
                    StationPin(station: st, selected: id == selected)
                        .onTapGesture { onTap(id) }
                        .accessibilityLabel(Text("Station \(st.shown)"))
                        .accessibilityAddTraits(.isButton)
                }
            }
        }
    }
}
