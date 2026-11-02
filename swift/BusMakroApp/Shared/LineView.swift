import BusMakroKit
import SwiftUI

/// The line view's panel content: Arrivals (buses heading to your stop) and Route (the stops in
/// order, with the buses between them), like the Mac app's line tabs.
struct LineContent: View {
    @Bindable var model: Model

    var body: some View {
        Picker("", selection: $model.lineTab) {
            Text("Arrivals").tag(Model.LineTab.arrivals)
            Text("Route").tag(Model.LineTab.route)
            Text("Nearby").tag(Model.LineTab.nearby)
            Text("Timetable").tag(Model.LineTab.timetable)
        }
        .pickerStyle(.segmented).labelsHidden()
        if model.lineDetail == nil {
            Text("Loading the line…").font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 20)
                .frame(maxWidth: .infinity)
        } else {
            switch model.lineTab {
            case .arrivals: arrivals
            case .route: route
            case .nearby: nearby
            case .timetable: TimetableList(model: model)
            }
        }
    }

    private var arrivals: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("APPROACHING BUSES").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.alerts(for: [currentLine])) { AlertCard(alert: $0) }
                    let rows = model.approaching
                    if rows.isEmpty {
                        Text(model.lineStop == nil ? String(localized: "Choose a stop to see approaching buses.") : String(localized: "No bus is heading to this stop right now."))
                            .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 20)
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, a in
                        ArrivalCard(item: a, watching: model.watches[a.vehicle.id]?.stops, onWatch: { model.watch(a.vehicle.id, stops: $0) },
                                    following: model.pinned == a.vehicle.id,
                                    onFollow: { model.pinned = model.pinned == a.vehicle.id ? nil : a.vehicle.id })
                            .appearing(i)
                    }
                }
            }
        }
    }

    private var route: some View {
        VStack(spacing: 8) {
            if let d = model.lineDetail, d.variants.count > 1 {
                // lines with several routes: pick which one (the Mac app's variant menu)
                Picker("", selection: Binding(get: { model.variantID ?? "" }, set: { model.chosenVariant = $0 })) {
                    ForEach(d.variants.keys.sorted(), id: \.self) { k in
                        Text(Names.place(d.variants[k]!.headsign, "")).tag(k)
                    }
                }
                .pickerStyle(.menu).labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            routeList
        }
    }

    private var routeList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let d = model.lineDetail, let vid = model.variantID, let v = d.variants[vid] {
                        ForEach(Array(v.stops.enumerated()), id: \.offset) { i, sid in
                            let buses = model.vehicles.filter { $0.variant == vid && $0.nextStopID == sid }
                            ForEach(buses) { b in RouteBusRow(id: b.id) }
                            RouteStopRow(name: Names.place(d.stops[sid]?.name ?? sid, ""), id: sid, selected: sid == model.lineStop,
                                         first: i == 0, last: i == v.stops.count - 1)
                                .id(sid)
                                .onTapGesture { model.lineStop = sid; Task { await model.refreshLine(currentLine) } }
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                }
            }
            .onAppear { if let s = model.lineStop { proxy.scrollTo(s, anchor: .center) } }
        }
    }

    /// The line's stops nearest you; tapping one selects it and shows its arrivals.
    private var nearby: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NEAREST STOPS ON THIS LINE").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 6) {
                    let rows = model.nearestOnLine(from: nil)
                    if rows.isEmpty {
                        Text("Tap the location button to find the stops near you.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 20)
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.0) { i, row in
                        Button {
                            model.lineStop = row.0
                            model.lineTab = .arrivals
                            Task { await model.refreshLine(currentLine) }
                        } label: {
                            StopCard(stop: Stop(id: row.0, name: row.1.name, nameEnglish: "", street: "",
                                                latitude: row.1.lat, longitude: row.1.lon),
                                     metres: row.2, closest: i == 0)
                        }
                        .buttonStyle(.plain)
                        .appearing(i)
                    }
                }
            }
        }
    }

    private var currentLine: String {
        if case .line(let id, _) = model.screen { return id }
        return ""
    }
}

/// An approaching bus: time (rolling), stops away, and the alert and follow buttons; long-press
/// for the bus number, delay and trip.
struct ArrivalCard: View {
    let item: Approaching
    var watching: Int? = nil
    var onWatch: (Int?) -> Void = { _ in }
    var following = false
    var onFollow: () -> Void = {}
    @State private var showDetails = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(time).font(Style.rounded(20)).contentTransition(.numericText(countsDown: true))
                    if item.official { PulseDot(fast: item.seconds < 90) }
                }
                Text((item.stopsAway == 0 ? String(localized: "next stop") : item.stopsAway == 1 ? String(localized: "1 stop away") : String(localized: "\(item.stopsAway) stops away"))
                     + (item.waiting ? " · " + String(localized: "waiting to set off") : ""))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            // 🔔: notify me when this bus is N stops from my stop
            Menu { watchMenu } label: {
                circle(watching != nil ? "bell.fill" : "bell", on: watching != nil)
            }
            .accessibilityLabel(Text("Notify Me"))
            // ⌖: follow this bus on the map
            Button(action: onFollow) { circle(following ? "location.fill" : "scope", on: following) }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Follow on Map"))
        }
        .padding(.horizontal, 14)
        .frame(height: 72)
        .card()
        .background(item.seconds < 90 ? Color.green.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: Style.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Style.cardRadius).stroke(following ? Color.orange : .clear, lineWidth: 1.5))
        // long press: just the explained details, in a wide popover (the buttons stay on the card;
        // a context menu with no items never opens)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in showDetails = true })
        .sensoryFeedback(.impact(weight: .medium), trigger: showDetails) { _, on in on }
        .popover(isPresented: $showDetails, arrowEdge: .bottom) {
            details.presentationCompactAdaptation(.popover)
        }
    }

    /// Long press: the bus number, how late or early it runs, and its trip, each with what it means.
    private var details: some View {
        let trip = item.vehicle.tripLabel.map { Names.place($0, "") }
        // "13:55 SCHISTO → SCHISTO": the time it set off, then the route
        let parts = trip?.split(separator: " ", maxSplits: 1).map(String.init) ?? []
        let started = parts.count == 2 && parts[0].contains(":") ? parts[0] : nil
        let route = started != nil ? parts[1] : trip
        return VStack(alignment: .leading, spacing: 14) {
            detail("bus.fill", "Bus number", item.vehicle.id, "The number painted on the bus, to spot it.")
            if let d = item.vehicle.delaySeconds {
                detail("clock", "Schedule", abs(d) < 60 ? String(localized: "On time")
                       : d > 0 ? String(localized: "\(d / 60) min late") : String(localized: "\(-d / 60) min early"),
                       "Compared with the timetable, by OASA.")
            }
            if let route {
                detail("arrow.triangle.turn.up.right.diamond", "Trip", route,
                       started.map { String(localized: "Set off at \($0).") } ?? String(localized: "Where this bus is going."))
            }
        }
        .padding(20)
        .frame(width: 340, alignment: .leading)
    }

    private func detail(_ symbol: String, _ title: LocalizedStringKey, _ value: String, _ note: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                Text(value).font(.system(size: 16, weight: .semibold))
                Text(note).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var watchMenu: some View {
        Text("Notify me when this bus is…")
        ForEach(Model.watchChoices, id: \.self) { n in
            Button(n == 1 ? String(localized: "1 stop away") : String(localized: "\(n) stops away")) { onWatch(n) }
        }
        if watching != nil { Button("Don't Notify Me", role: .destructive) { onWatch(nil) } }
    }

    /// A round, finger-sized button face (44 pt), tinted orange while on.
    private func circle(_ symbol: String, on: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(on ? Color.orange : Color.primary.opacity(0.7))
            .frame(width: 40, height: 40)
            .background(on ? Color.orange.opacity(0.16) : Color.primary.opacity(0.06), in: Circle())
            .contentShape(Circle())
    }

    private var time: String {
        item.seconds < 20 ? String(localized: "Due") : String(localized: "\(Int(item.seconds) / 60) min") + (item.official ? "" : " ~")
    }

    private var delay: (String, Color) {
        guard let d = item.vehicle.delaySeconds else { return ("", .secondary) }
        if abs(d) < 60 { return (String(localized: "On time"), .green) }
        return ((d > 0 ? "+" : "") + String(localized: "\(d / 60) min"), d > 0 ? .orange : .blue)
    }
}

/// A stop on the Route tab: a dot on the line's spine, orange and larger when selected.
struct RouteStopRow: View {
    let name: String, id: String
    let selected: Bool, first: Bool, last: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Rectangle().fill(.tertiary).frame(width: 2)
                    .padding(.top, first ? 23 : 0).padding(.bottom, last ? 23 : 0)
                Circle().fill(selected ? Color.orange : Color(red: 0.09, green: 0.47, blue: 1.0))
                    .frame(width: selected ? 16 : 10, height: selected ? 16 : 10)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
            .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13, weight: selected ? .semibold : .regular)).lineLimit(1)
                Text("Stop \(id)").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 6)
        .frame(height: 46)
        .background(selected ? Color.orange.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }
}

/// A bus between two stops on the Route tab.
struct RouteBusRow: View {
    let id: String
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Rectangle().fill(.tertiary).frame(width: 2)
                Image(systemName: "bus.fill").font(.system(size: 10)).foregroundStyle(.white)
                    .frame(width: 22, height: 22).background(.green, in: Circle())
            }
            .frame(width: 22)
            Text("Bus \(id)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.green)
            Spacer()
        }
        .padding(.horizontal, 6)
        .frame(height: 34)
    }
}

/// Today's departures from each end of the line, five to a row: gone ones dimmed, the next one in a
/// green pill, scrolled to now (the Mac app's Timetable tab).
struct TimetableList: View {
    @Bindable var model: Model
    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.timeZone = OASAClient.athens; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.timetableDays.count > 1 {
                // the days of the week, Monday first; each shows the timetable that applies to it
                Picker("", selection: Binding(get: { model.timetableWeekday },
                                              set: { w in Task { await model.loadTimetable(weekday: w) } })) {
                    ForEach(1...7, id: \.self) { Text(Self.dayLetters[$0 - 1]).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                if let d = model.timetableDays.first(where: { $0.code == model.timetableDay }) {
                    Text(dayName(d)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Text(today ? LocalizedStringKey("TODAY'S DEPARTURES FROM EACH END") : "DEPARTURES FROM EACH END")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            if let tt = model.timetable?.variants {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            if tt.isEmpty {
                                Text("No timetable for today").font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 20)
                            }
                            ForEach(Array(tt.enumerated()), id: \.offset) { vi, v in
                                let ends = v.name.components(separatedBy: " - ")
                                if vi > 0 { header(String(localized: "Also: \(Names.place(v.name, v.nameEnglish))")) }
                                section(v.go, from: ends.first ?? v.name, key: "\(vi)g")
                                section(v.come, from: ends.last ?? v.name, key: "\(vi)c")
                            }
                        }
                    }
                    .onAppear { proxy.scrollTo("next", anchor: .center) }
                }
            } else {
                Text("Loading the timetable…").font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 20)
                    .frame(maxWidth: .infinity)
            }
        }
        .task { await model.loadTimetable() }
    }

    private var today: Bool { model.timetableIsToday }

    /// Mon … Sun, short, in the app's language.
    private static var dayLetters: [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: Names.greek ? "el" : "en")
        let s = cal.shortWeekdaySymbols  // Sunday first
        return Array(s[1...]) + [s[0]]
    }

    /// Which timetable the chosen day uses: "Timetable: Monday to Friday", "…: Friday", …
    private func dayName(_ d: OASAClient.ScheduleDay) -> String {
        let w = d.weekdays.sorted()
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: Names.greek ? "el" : "en")
        let names = cal.weekdaySymbols.map { $0.capitalized }
        func name(_ i: Int) -> String { names[i % 7] }  // 1 Monday … 7 Sunday → weekdaySymbols (Sunday first)
        let text: String
        if w.count == 1 { text = name(w[0]) }
        else if w == Array(w[0]...w[w.count - 1]) { text = String(localized: "\(name(w[0])) to \(name(w.last!))") }
        else { text = w.map(name).joined(separator: ", ") }
        return String(localized: "Timetable: \(text)")
    }

    private func header(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 8)
    }

    @ViewBuilder private func section(_ times: [Date], from place: String, key: String) -> some View {
        if !times.isEmpty {
            // another day's timetable: all times plain, no "next"
            let now = today ? Date() : .distantPast
            let next = today ? times.first { $0 >= now } : nil
            header(today ? String(localized: "From \(Names.place(place, ""))  ·  \(times.filter { $0 >= now }.count) more today")
                         : String(localized: "From \(Names.place(place, ""))  ·  \(times.count) departures"))
            let rows = stride(from: 0, to: times.count, by: 5).map { Array(times[$0..<min($0 + 5, times.count)]) }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(row, id: \.self) { t in
                        let isNext = t == next
                        Text(Self.fmt.string(from: t))
                            .font(Style.rounded(14, isNext ? .bold : .regular))
                            .foregroundStyle(isNext ? Color.green : t < now ? Color.secondary.opacity(0.5) : Color.primary)
                            .frame(maxWidth: .infinity).frame(height: 24)
                            .background(isNext ? Color.green.opacity(0.22) : .clear, in: Capsule())
                            .padding(.horizontal, 4)
                    }
                    ForEach(0..<(5 - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                }
                .frame(height: 30)
                .id(row.contains { $0 == next } ? "next" : "\(key)\(row[0].timeIntervalSince1970)")
            }
        }
    }
}
