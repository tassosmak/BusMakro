import BusMakroKit
import SwiftUI
import TipKit

/// The line view's panel content: Arrivals (buses heading to your stop) and Route (the stops in
/// order, with the buses between them), like the Mac app's line tabs.
struct LineContent: View {
    @Bindable var model: Model
    /// "Wake me at my stop" chosen: the next stop tapped on the Route tab is where you get off.

    var body: some View {
        Picker("Line view", selection: $model.lineTab) {
            Text("Arrivals").tag(Model.LineTab.arrivals)
            Text("Route").tag(Model.LineTab.route)
            Text("Timetable").tag(Model.LineTab.timetable)
        }
        .pickerStyle(.segmented).labelsHidden()
        if model.lineMissing {
            VStack(spacing: 6) {
                Image(systemName: "moon.zzz").font(.scaled(26)).foregroundStyle(.subtle)
                Text("This line isn't running right now").font(.scaled(15, .semibold))
                Text("Some lines run only part of the year (like Χ80 outside summer) or were withdrawn. Its timetable may still be in the Timetable tab when it runs again.")
                    .font(.scaled(12)).foregroundStyle(.subtle).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.top, 24).padding(.horizontal, 12)
        } else if model.lineDetail == nil {
            loading("Loading the line…")
        } else {
            switch model.lineTab {
            case .arrivals: arrivals
            case .route: route
            case .timetable: TimetableList(model: model)
            }
        }
    }

    private var stopName: String? {
        model.lineStop.flatMap { id in model.lineDetail?.stops[id].map { Names.place($0.name, "") } }
    }

    private func loading(_ text: LocalizedStringKey) -> some View {
        VStack(spacing: 8) {
            ProgressView().controlSize(.regular)
            Text(text).font(.scaled(12)).foregroundStyle(.subtle)
        }
        .frame(maxWidth: .infinity).padding(.top, 20)
        .accessibilityElement(children: .combine)
    }

    private var arrivals: some View {
        VStack(alignment: .leading, spacing: 8) {
            // which stop: picked for you when the line opened without one
            Text(stopName.map { String(localized: "Buses to \($0)") } ?? String(localized: "Approaching buses"))
                .textCase(.uppercase).font(.scaled(11, .semibold)).foregroundStyle(.subtle).lineLimit(2).heading()
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.alerts(for: [currentLine])) { AlertCard(alert: $0) }
                    let rows = model.approaching
                    if rows.isEmpty && model.lineLoading {
                        loading("Finding the buses…")
                    } else if rows.isEmpty {
                        Text(model.lineStop == nil ? String(localized: "Choose a stop to see approaching buses.") : String(localized: "No bus is heading to this stop right now."))
                            .font(.scaled(12)).foregroundStyle(.subtle).padding(.top, 20)
                    }
                    if !rows.isEmpty { TipView(BusButtonsTip(), arrowEdge: .bottom).tipBackground(.thinMaterial) }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, a in
                        ArrivalCard(item: a, watching: model.watches[a.vehicle.id].flatMap { $0.kind != .alert || $0.notified ? nil : $0.stops },  // normal again once notified
                                    onWatch: { BusButtonsTip().invalidate(reason: .actionPerformed); model.watch(a.vehicle.id, stops: $0) },
                                    following: model.pinned == a.vehicle.id,
                                    onFollow: { BusButtonsTip().invalidate(reason: .actionPerformed); model.pinned = model.pinned == a.vehicle.id ? nil : a.vehicle.id },
                                    wakeStops: stopsAhead(a.vehicle),
                                    waking: model.watches[a.vehicle.id].flatMap { $0.kind == .ride ? $0.stopName : nil },
                                    onWake: { sid in
                                        BusButtonsTip().invalidate(reason: .actionPerformed)
                                        if let sid { model.ride(a.vehicle.id, to: sid) } else { model.watch(a.vehicle.id, stops: nil) }
                                    })
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
                Picker("Direction", selection: Binding(get: { model.variantID ?? "" }, set: { model.chosenVariant = $0 })) {
                    ForEach(d.variants.keys.sorted(), id: \.self) { k in
                        Text(Names.place(d.variants[k]!.headsign, "")).tag(k)
                    }
                }
                .pickerStyle(.menu).labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            wakeBar
            routeList
        }
    }

    /// On the bus you're following: be woken before the stop you get off at.
    @ViewBuilder private var wakeBar: some View {
        if let r = model.riding {
            HStack(spacing: 10) {
                Image(systemName: "bell.and.waves.left.and.right.fill").foregroundStyle(.orange).accessibilityHidden(true)
                Text("Waking you before \(Names.place(r.watch.stopName, ""))").font(.scaled(13, .semibold))
                Spacer(minLength: 4)
                Button("Cancel") { model.watch(r.bus, stops: nil) }.font(.scaled(13, .semibold))
            }
            .padding(10)
            .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: Style.cardRadius))
            .accessibilityElement(children: .combine)
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
                                         first: i == 0, last: i == v.stops.count - 1, wake: model.riding?.watch.stop == sid)
                                .id(sid)
                                .onTapGesture {
                                    model.lineStop = sid; Task { await model.refreshLine(currentLine) }
                                }
                                .contextMenu {
                                    if let bus = model.pinned { Button("Wake Me Here", systemImage: "bell.and.waves.left.and.right") { model.ride(bus, to: sid) } }
                                }
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                }
            }
            .onAppear { if let s = model.lineStop { proxy.scrollTo(s, anchor: .center) } }
        }
    }
    /// The stops this bus still has to go after yours: where you could get off it.
    private func stopsAhead(_ v: Vehicle) -> [(id: String, name: String)] {
        guard let d = model.lineDetail, let vid = v.variant ?? model.variantID, let stops = d.variants[vid]?.stops,
              let mine = model.lineStop, let i = stops.firstIndex(of: mine) else { return [] }
        return stops[(i + 1)...].map { ($0, Names.place(d.stops[$0]?.name ?? $0, "")) }
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
    /// "Wake me at my stop": the stops ahead to choose from, the one chosen (its name), and the choice.
    var wakeStops: [(id: String, name: String)] = []
    var waking: String? = nil
    var onWake: (String?) -> Void = { _ in }
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
                    .font(.scaled(11)).foregroundStyle(.subtle)
            }
            // the time and stops as one sentence; long press (bus number, delay, trip) as an action
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenTime)
            .accessibilityValue(Speak.join([Speak.stops(item.stopsAway), item.waiting ? String(localized: "waiting to set off") : nil,
                                            following ? String(localized: "following on the map") : nil]))
            .accessibilityAction(named: Text("Bus details")) { showDetails = true }
            Spacer(minLength: 0)
            // 🔔: notify me when this bus is N stops from my stop
            Menu { watchMenu } label: {
                circle(watching != nil ? "bell.fill" : "bell", on: watching != nil)
            }
            .accessibilityLabel(Text("Notify Me"))
            .accessibilityValue(watching.map { Speak.join([String(localized: "On"), Speak.stops($0)]) } ?? String(localized: "Off"))
            // ⌖: follow this bus on the map
            Button(action: onFollow) { circle(following ? "location.fill" : "scope", on: following) }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Follow on Map"))
                .accessibilityAddTraits(following ? .isSelected : [])
            // ⏰: on this bus? wake me before the stop I get off at
            if !wakeStops.isEmpty || waking != nil {
                Menu { wakeMenu } label: {
                    circle(waking != nil ? "bell.and.waves.left.and.right.fill" : "bell.and.waves.left.and.right", on: waking != nil)
                }
                .accessibilityLabel(Text("Wake Me at My Stop"))
                .accessibilityValue(waking.map { String(localized: "On, at \($0)") } ?? String(localized: "Off"))
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 72)
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
            Image(systemName: symbol).font(.scaled(15)).foregroundStyle(.subtle).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.scaled(11, .semibold)).foregroundStyle(.subtle).textCase(.uppercase)
                Text(value).font(.scaled(16, .semibold))
                Text(note).font(.scaled(12)).foregroundStyle(.subtle)
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

    @ViewBuilder private var wakeMenu: some View {
        if let waking {
            Text("Waking you before \(waking)")
            Button("Don't Wake Me", role: .destructive) { onWake(nil) }
        } else {
            Text("On this bus? Wake me before…")
            ForEach(wakeStops, id: \.id) { st in Button(st.name) { onWake(st.id) } }
        }
    }

    /// A round, finger-sized button face (44 pt), tinted orange while on.
    private func circle(_ symbol: String, on: Bool) -> some View {
        Image(systemName: symbol)
            .font(.scaled(16, .medium))
            .foregroundStyle(on ? Color.orange : Color.primary.opacity(0.7))
            .frame(width: 40, height: 40)
            .background(on ? Color.orange.opacity(0.16) : Color.primary.opacity(0.06), in: Circle())
            .contentShape(Circle())
            .frame(width: 44, height: 44)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)  // the symbol stays inside its circle
    }

    private var spokenTime: String {
        let live = item.official ? String(localized: "live") : String(localized: "estimated")
        if item.seconds < 20 { return Speak.join([String(localized: "Due now"), live]) }
        return Speak.join([String(localized: "in \(Speak.minutes(Int(item.seconds) / 60))"), live])
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
    /// Where "wake me at my stop" is set.
    var wake = false

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
                Text(name).font(.scaled(13, selected ? .semibold : .regular)).lineLimit(1)
                Text("Stop \(id)").font(.scaled(11)).foregroundStyle(.subtle)
            }
            Spacer()
            if wake { Image(systemName: "bell.and.waves.left.and.right.fill").foregroundStyle(.orange).accessibilityHidden(true) }
        }
        .padding(.horizontal, 6)
        .frame(minHeight: 46)
        .background(selected ? Color.orange.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Speak.join([name, String(localized: "Stop \(id)"), first ? String(localized: "first stop") : last ? String(localized: "last stop") : nil,
                                        wake ? String(localized: "you'll be woken here") : nil]))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(selected ? Text("") : Text("Shows the buses heading to this stop"))
    }
}

/// A bus between two stops on the Route tab.
struct RouteBusRow: View {
    let id: String
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Rectangle().fill(.tertiary).frame(width: 2)
                Image(systemName: "bus.fill").font(.scaled(10)).foregroundStyle(.white)
                    .frame(width: 22, height: 22).background(.green, in: Circle())
            }
            .frame(width: 22)
            Text("Bus \(id)").font(.scaled(12, .semibold)).foregroundStyle(.green)
            Spacer()
        }
        .padding(.horizontal, 6)
        .frame(height: 34)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Bus \(id), on its way to the next stop"))
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
                Picker("Day", selection: Binding(get: { model.timetableWeekday },
                                              set: { w in Task { await model.loadTimetable(weekday: w) } })) {
                    ForEach(1...7, id: \.self) { Text(Self.dayLetters[$0 - 1]).accessibilityLabel(Self.dayNames[$0 - 1]).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                if let d = model.timetableDays.first(where: { $0.code == model.timetableDay }) {
                    Text(dayName(d)).font(.scaled(11)).foregroundStyle(.subtle)
                }
            }
            Text(today ? LocalizedStringKey("TODAY'S DEPARTURES FROM EACH END") : "DEPARTURES FROM EACH END")
                .font(.scaled(11, .semibold)).foregroundStyle(.subtle).heading()
            if let tt = model.timetable?.variants {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            if tt.isEmpty {
                                Text("No timetable for today").font(.scaled(12)).foregroundStyle(.subtle).padding(.top, 20)
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
                Text("Loading the timetable…").font(.scaled(12)).foregroundStyle(.subtle).padding(.top, 20)
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

    /// Monday … Sunday, in full, for VoiceOver.
    private static var dayNames: [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: Names.greek ? "el" : "en")
        let s = cal.weekdaySymbols
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
        Text(text).font(.scaled(11, .semibold)).foregroundStyle(.subtle).padding(.top, 8)
            .accessibilityLabel(text.replacingOccurrences(of: "·", with: ","))
            .heading()
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
                            .accessibilityLabel(Speak.time(t))
                            .accessibilityValue(isNext ? String(localized: "next departure") : t < now ? String(localized: "departed") : "")
                    }
                    ForEach(0..<(5 - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                }
                .frame(height: 30)
                .id(row.contains { $0 == next } ? "next" : "\(key)\(row[0].timeIntervalSince1970)")
            }
        }
    }
}
