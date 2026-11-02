import BusMakroKit
import CoreLocation
import MapKit
import SwiftUI

/// Plan a trip (☰ → Plan a Trip): from here (or anywhere) to a stop, station, address or place.
/// Buses, trolleys, metro and tram, at most one change; the first wait is the real next arrival.

extension Model {
    var planner: TripPlanner? {
        guard let stopIndex else { return nil }
        if let p = cachedPlanner { return p }
        let p = TripPlanner(index: stopIndex, rail: Rail.shared)
        cachedPlanner = p
        return p
    }

    /// Swap each trip's typical first wait for the real one: OASA's live arrival at the boarding
    /// stop, or the train timetable. Then fastest first again.
    func refine(_ trips: [TripPlanner.Trip]) async -> [TripPlanner.Trip] {
        var out: [TripPlanner.Trip] = []
        let oasa = OASAClient()
        await withTaskGroup(of: (Int, TripPlanner.Trip).self) { group in
            for (n, trip) in trips.enumerated() {
                group.addTask {
                    var trip = trip
                    guard let i = trip.legs.firstIndex(where: { $0.mode != .walk }) else { return (n, trip) }
                    let leg = trip.legs[i]
                    let walk = trip.legs[..<i].reduce(0) { $0 + $1.minutes }
                    if leg.mode == .bus {
                        if let lines = try? await oasa.stopLines(stopID: leg.from.id),
                           let m = lines.first(where: { $0.line == leg.line })?.arrivalsMinutes.first(where: { $0 >= walk }) {
                            trip.legs[i].wait = m - walk
                            trip.legs[i].waitIsLive = true
                        }
                    } else if let rail = Rail.shared {
                        let after = Date().addingTimeInterval(Double(walk) * 60)
                        if let d = rail.next(at: leg.from.id, from: after, count: 1)
                            .first(where: { $0.line == leg.line && $0.direction == leg.direction }) {
                            trip.legs[i].wait = d.minutes
                            trip.legs[i].waitIsLive = true
                        }
                    }
                    return (n, trip)
                }
            }
            var got: [(Int, TripPlanner.Trip)] = []
            for await r in group { got.append(r) }
            out = got.sorted { $0.0 < $1.0 }.map(\.1)
        }
        return out.sorted { $0.minutes < $1.minutes }
    }
}

/// Where a trip starts or ends.
enum TripEnd: Equatable {
    case here
    case place(TripPlanner.Place)

    var title: String {
        switch self {
        case .here: String(localized: "My Location")
        case .place(let p): p.name
        }
    }
}

struct TripView: View {
    @Bindable var model: Model
    @Environment(\.dismiss) private var dismiss
    @State private var from: TripEnd = .here
    @State private var to: TripEnd?
    @State private var editing: Field?
    @State private var trips: [TripPlanner.Trip]?
    @State private var open: String?
    @State private var leaving = Date()
    enum Field { case from, to }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ends.padding(Style.gap)
                Divider()
                if let editing {
                    PlaceSearch(model: model, allowHere: !model.pickingHome) { choice in
                        // setting Home first ("Take Me Home" with no Home yet): keep it, then go there
                        if model.pickingHome, case .place(let p) = choice { model.home = p; model.pickingHome = false; from = .here }
                        if editing == .from { from = choice } else { to = choice }
                        self.editing = nil
                        Task { await plan() }
                    }
                } else {
                    results
                }
            }
            .navigationTitle("Plan a Trip")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .onAppear {
            if let t = model.tripTo { from = .here; to = .place(t); model.tripTo = nil; Task { await plan() } }
            else if to == nil { editing = .to }
        }
        .onDisappear { model.pickingHome = false }
    }

    private var ends: some View {
        HStack(spacing: 10) {
            VStack(spacing: 0) {
                Circle().stroke(.blue, lineWidth: 3).frame(width: 10, height: 10)
                Rectangle().fill(.tertiary).frame(width: 2, height: 26)
                Image(systemName: "mappin.circle.fill").foregroundStyle(.red).font(.scaled(14))
            }
            VStack(spacing: 8) {
                endButton(from.title, placeholder: "From", field: .from)
                endButton(to?.title, placeholder: model.pickingHome ? "Where is Home?" : "To", field: .to)
            }
            Button {
                guard let t = to else { return }
                (from, to) = (t, from)
                Task { await plan() }
            } label: {
                Image(systemName: "arrow.up.arrow.down").font(.scaled(15, .semibold)).frame(width: 36, height: 36)
            }
            .buttonStyle(.plain).accessibilityLabel("Swap")
        }
    }

    private func endButton(_ title: String?, placeholder: LocalizedStringKey, field: Field) -> some View {
        Button { editing = field } label: {
            HStack {
                if let title { Text(title).foregroundStyle(title == String(localized: "My Location") ? .blue : .primary) }
                else { Text(placeholder).foregroundStyle(.secondary) }
                Spacer()
            }
            .font(.scaled(15)).lineLimit(1)
            .padding(.horizontal, 12).frame(minHeight: 40)
            .background(.primary.opacity(editing == field ? 0.12 : 0.07), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var results: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if to == nil {
                    EmptyView()
                } else if model.stopIndex == nil {
                    note("Getting the bus network ready…")
                } else if let trips {
                    if trips.isEmpty {
                        note("No trip found with at most one change. Try a place closer to a stop or station.")
                    }
                    ForEach(Array(trips.enumerated()), id: \.element.id) { i, t in
                        TripCard(trip: t, leaving: leaving, expanded: open == t.id) {
                            withAnimation(.smooth(duration: 0.25)) { open = open == t.id ? nil : t.id }
                        } onOpen: { leg in go(to: leg) }
                        .appearing(i)
                    }
                    if !trips.isEmpty {
                        Text("Times are estimates. The first wait is live (bus) or from the timetable (train) when marked with a dot.")
                            .font(.scaled(10)).foregroundStyle(.tertiary).multilineTextAlignment(.center).padding(.top, 4)
                    }
                } else {
                    ProgressView().padding(.top, 30)
                }
            }
            .padding(Style.gap)
        }
        .refreshable { await plan() }
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.scaled(13)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 30)
    }

    private func point(_ end: TripEnd) -> TripPlanner.Place? {
        switch end {
        case .here: model.userLocation.map { TripPlanner.Place(name: String(localized: "My Location"), lat: $0.latitude, lon: $0.longitude) }
        case .place(let p): p
        }
    }

    private func plan() async {
        guard let to, let a = point(from), let b = point(to) else { return }
        trips = nil
        for _ in 0..<60 where model.planner == nil { try? await Task.sleep(for: .milliseconds(500)) }  // the index is still loading
        guard let planner = model.planner else { trips = []; return }
        leaving = Date()
        let rough = await Task.detached { planner.plan(from: a, to: b) }.value
        trips = rough
        trips = await model.refine(rough)
    }

    /// Open the stop or station where a ride starts, in the main panel.
    private func go(to leg: TripPlanner.Leg) {
        dismiss()
        if leg.mode == .bus {
            if let s = model.knownStop(leg.from.id) { model.open(s) }
        } else {
            model.openStation(leg.from.id)
        }
    }
}

/// One way to go: total time and arrival, the legs as chips; tap for each leg in detail.
struct TripCard: View {
    let trip: TripPlanner.Trip
    let leaving: Date
    let expanded: Bool
    let onTap: () -> Void
    let onOpen: (TripPlanner.Leg) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(trip.minutes) min").font(.scaled(20, .bold, design: .rounded))
                        Text(String(localized: "arrive \(leaving.addingTimeInterval(Double(trip.minutes) * 60).formatted(date: .omitted, time: .shortened))"))
                            .font(.scaled(12)).foregroundStyle(.secondary)
                        Spacer()
                        if let first = trip.rides.first {
                            HStack(spacing: 4) {
                                if first.waitIsLive { PulseDot() }
                                Text(leaveText).font(.scaled(12, .semibold)).foregroundStyle(.orange)
                            }
                        }
                    }
                    chips
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(trip.legs.enumerated()), id: \.offset) { _, leg in legRow(leg) }
                }
                .transition(.opacity)
            }
        }
        .padding(12)
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: Style.cardRadius))
    }

    /// When to set off: the first ride's wait, less nothing (you walk while the bus comes).
    private var leaveText: String {
        guard let i = trip.legs.firstIndex(where: { $0.mode != .walk }) else { return "" }
        let wait = trip.legs[i].wait
        return wait <= 1 ? String(localized: "Leave now") : String(localized: "Leave in \(wait) min")
    }

    private var chips: some View {
        let legs = trip.legs.filter { $0.mode != .walk || $0.minutes >= 3 || trip.rides.isEmpty }
        return HStack(spacing: 4) {
            ForEach(Array(legs.enumerated()), id: \.offset) { i, leg in
                if i > 0 { Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary) }
                chip(leg)
            }
        }
    }

    @ViewBuilder private func chip(_ leg: TripPlanner.Leg) -> some View {
        switch leg.mode {
        case .walk:
            HStack(spacing: 2) {
                Image(systemName: "figure.walk").font(.scaled(12))
                Text("\(leg.minutes)").font(.scaled(11, .semibold))
            }.foregroundStyle(.secondary)
        case .bus:
            Text(leg.line).font(.scaled(12, .bold, design: .rounded)).foregroundStyle(.white)
                .padding(.horizontal, 6).frame(height: 22).background(.blue, in: RoundedRectangle(cornerRadius: 6))
        case .metro, .tram:
            RailBadge(line: leg.line)
        }
    }

    private func legRow(_ leg: TripPlanner.Leg) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: leg.mode == .walk ? "figure.walk" : leg.mode == .bus ? "bus.fill" : leg.mode == .tram ? "tram.fill" : "tram.fill.tunnel")
                .frame(width: 22).foregroundStyle(leg.mode == .walk ? Color.secondary : .accentColor).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                if leg.mode == .walk {
                    Text(String(localized: "Walk \(leg.minutes) min to \(Names.place(leg.to.name, nil))")).font(.scaled(13))
                } else {
                    Text(String(localized: "\(leg.line) towards \(Names.place(leg.headsign, nil))")).font(.scaled(13, .semibold))
                    Text(String(localized: "From \(Names.place(leg.from.name, nil)) · \(leg.stops) stops · \(leg.minutes) min"))
                        .font(.scaled(11)).foregroundStyle(.secondary)
                    Text(String(localized: "Get off at \(Names.place(leg.to.name, nil))")).font(.scaled(11)).foregroundStyle(.secondary)
                    Button(leg.mode == .bus ? String(localized: "Open the stop") : String(localized: "Open the station")) { onOpen(leg) }
                        .font(.scaled(12, .semibold)).padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

/// Search for a trip's start or end: My Location, stations, stops, then addresses and places
/// (Apple Maps, around Athens).
struct PlaceSearch: View {
    @Bindable var model: Model
    var allowHere = true
    let onPick: (TripEnd) -> Void
    @State private var text = ""
    @State private var completer = PlaceCompleter()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Stop, station, address or place", text: $text)
                .textFieldStyle(.plain).focused($focused)
                .autocorrectionDisabled()  // place names aren't words: "Kifisia" became "Kiwis is"
                .padding(.horizontal, 12).frame(minHeight: 40)
                .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                .padding(Style.gap)
                .onChange(of: text) { completer.query(text) }
            List {
                if allowHere && text.isEmpty {
                    row("location.fill", String(localized: "My Location"), nil, tint: .blue) { onPick(.here) }
                }
                if text.isEmpty, let h = model.home, !model.pickingHome {
                    row("house.fill", String(localized: "Home"), h.name, tint: .orange) { onPick(.place(h)) }
                }
                if text.isEmpty {
                    ForEach(model.favourites + model.recents.filter { r in !model.favourites.contains { $0.id == r.id } }) { s in
                        row(model.isFavourite(s) ? "star.fill" : "clock", s.title, String(localized: "Stop \(s.id)"), tint: model.isFavourite(s) ? .yellow : .secondary) {
                            onPick(.place(.init(id: s.id, name: s.title, lat: s.latitude, lon: s.longitude)))
                        }
                    }
                }
                ForEach(stations, id: \.id) { r in
                    row("tram.fill", r.station.shown, r.station.lines.joined(separator: " · "), tint: .accentColor) {
                        onPick(.place(.init(id: r.id, name: r.station.shown, lat: r.station.lat, lon: r.station.lon)))
                    }
                }
                ForEach(stops, id: \.id) { r in
                    row("bus.fill", Names.place(r.entry.name, nil), String(localized: "Lines \(r.entry.lines.prefix(6).joined(separator: ", "))"), tint: .blue) {
                        onPick(.place(.init(id: r.id, name: r.entry.name, lat: r.entry.lat, lon: r.entry.lon)))
                    }
                }
                ForEach(completer.results, id: \.self) { c in
                    row("mappin.circle.fill", c.title, c.subtitle, tint: .red) {
                        Task { if let p = await PlaceCompleter.resolve(c) { onPick(.place(p)) } }
                    }
                }
            }
            .listStyle(.plain)
        }
        .onAppear { focused = true }
    }

    private var stations: [(id: String, station: Rail.Station)] {
        let q = Translit.normalize(text)
        guard q.count >= 2, let rail = Rail.shared else { return [] }
        var out: [(id: String, station: Rail.Station)] = []
        for (id, s) in rail.stations where Translit.normalize(s.name).contains(q) || Translit.normalize(s.nameEnglish).contains(q) {
            out.append((id, s))
        }
        return Array(out.prefix(4))
    }

    private var stops: [(id: String, entry: StopIndex.Entry)] {
        text.count >= 2 ? (model.stopIndex?.search(text, limit: 5) ?? []) : []
    }

    private func row(_ symbol: String, _ title: String, _ sub: String?, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(tint).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.scaled(14)).lineLimit(1)
                    if let sub, !sub.isEmpty { Text(sub).font(.scaled(11)).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Apple Maps' address and place suggestions, kept to Athens.
@MainActor @Observable
final class PlaceCompleter: NSObject, MKLocalSearchCompleterDelegate {
    var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()
    static let athens = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 37.98, longitude: 23.73),
                                           span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5))

    override init() {
        super.init()
        completer.delegate = self
        completer.region = Self.athens
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func query(_ q: String) {
        if q.count < 3 { results = []; return }
        completer.queryFragment = q
    }

    nonisolated func completerDidUpdateResults(_ c: MKLocalSearchCompleter) {
        let r = Array(c.results.prefix(6))
        Task { @MainActor in self.results = r }
    }

    nonisolated func completer(_ c: MKLocalSearchCompleter, didFailWithError error: Error) {}

    static func resolve(_ c: MKLocalSearchCompletion) async -> TripPlanner.Place? {
        let req = MKLocalSearch.Request(completion: c)
        req.region = athens
        guard let item = try? await MKLocalSearch(request: req).start().mapItems.first else { return nil }
        let co = item.placemark.coordinate
        return TripPlanner.Place(name: item.name ?? c.title, lat: co.latitude, lon: co.longitude)
    }
}
