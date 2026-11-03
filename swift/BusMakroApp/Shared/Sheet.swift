import BusMakroKit
import SwiftUI

/// The bottom panel: handle, "Browse a line…" menu, then the home tabs and stop cards, or a stop's
/// lines. One inset (Style.gap) for everything, as in the Mac app.
struct Sheet: View {
    @Bindable var model: Model
    @Binding var height: CGFloat
    let range: ClosedRange<CGFloat>
    @State private var dragStart: CGFloat?
    @AppStorage("favFilter") private var favFilter = "all"
    /// The favourite being renamed ("stop:ID" / "line:ID") and the name typed so far.
    @State private var renaming: String?
    @State private var nickname = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            handle
            header.simultaneousGesture(drag)  // the menu row drags the panel too (taps still work)
            if !model.online || model.serviceDown { offline.transition(.opacity.combined(with: .move(edge: .top))) }
            // fades out as the panel nears the slim strip (the strip shows just the handle and the menu)
            // fades with the panel's height, so it follows the drag and the snap exactly
            content.opacity(Double(min(1, max(0, (height - 90) / 70))))
        }
        // the banner comes and goes with the panel's own spring, not in a jump
        .animation(.spring(response: 0.36, dampingFraction: 1), value: !model.online || model.serviceDown)
        .padding(.horizontal, Style.gap)
        .padding(.bottom, 16)  // clear of the rounded bottom corners and the home indicator
        .frame(height: height, alignment: .top)
        .frame(maxWidth: 480)
        // what doesn't fit stays inside the panel (dragged small, the tabs and list were drawn below it)
        .clipShape(Style.panelShape)
        .panelGlass(Style.panelShape)
        .alert("Nickname", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Home, Work, Gym…", text: $nickname)
            Button("Save") { if let k = renaming { model.setNickname(nickname, for: k) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        } message: {
            Text("Shown instead of its name. Leave empty to use the name again.")
        }
    }

    // Drag the handle to resize; it snaps to the nearest of strip / normal / full.
    private var handle: some View {
        Capsule().fill(.tertiary).frame(width: 40, height: 5)
            .frame(maxWidth: .infinity).padding(.top, Style.gap).padding(.bottom, 1)  // so the strip leaves Style.gap under the menu
            .contentShape(Rectangle())
            .gesture(drag)
    }

    /// Drag the panel by its handle or header. Measured in screen coordinates: the handle moves with the
    /// panel, so measuring against itself made the drag fight its own movement (jitter).
    private var drag: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { g in
                let start = dragStart ?? height
                dragStart = start
                let raw = start - g.translation.height
                // past the ends it gives a little, like iOS sheets, instead of stopping dead
                if raw > range.upperBound { height = range.upperBound + (raw - range.upperBound) * 0.2 }
                else if raw < range.lowerBound { height = range.lowerBound - (range.lowerBound - raw) * 0.2 }
                else { height = raw }
            }
            .onEnded { g in
                dragStart = nil
                // where a flick would carry it, then the nearest of strip / normal / full
                let projected = height - (g.predictedEndTranslation.height - g.translation.height)
                let normal = min(360, range.upperBound)
                let stops = [range.lowerBound, normal, range.upperBound]
                let target = stops.min { abs($0 - projected) < abs($1 - projected) }!
                withAnimation(.spring(response: 0.36, dampingFraction: 1)) { height = target }
            }
    }

    /// No connection, or the bus service didn't answer: say so; it retries by itself, or tap.
    private var offline: some View {
        Button { Task { await model.retry() } } label: {
            HStack(spacing: 10) {
                Image(systemName: model.online ? "exclamationmark.icloud" : "wifi.slash").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.online ? "Couldn't reach the bus service. Tap to try again."
                                      : "No internet connection. Retrying when you're back online.")
                        .font(.scaled(12, .semibold)).multilineTextAlignment(.leading)
                    if let d = model.lastUpdated {
                        Text("Last updated \(d.formatted(date: Calendar.current.isDateInToday(d) ? .omitted : .abbreviated, time: .shortened))")
                            .font(.scaled(11)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: Style.cardRadius))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var header: some View {
        HStack(spacing: 8) {
            if case .stop = model.screen {
                Button { withAnimation { model.screen = .home } } label: { Label("Back", systemImage: "chevron.left") }
            }
            if case .station = model.screen {
                Button { withAnimation { model.screen = .home } } label: { Label("Back", systemImage: "chevron.left") }
            }
            if case .line = model.screen {
                Button { withAnimation { model.closeLine() } } label: { Label("Back", systemImage: "chevron.left") }
            }
            if let place = placeTitle {
                // in a stop or station: its name where "Browse a line…" was
                Text(place).font(.scaled(12, .semibold)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .frame(height: Style.lineMenuHeight)
                    .background(.primary.opacity(0.10), in: Capsule())
            } else {
            Menu {
                ForEach(model.lines) { l in
                    Button("\(l.id) — \(l.shown)") { withAnimation { model.openLine(l.id, at: nil) } }
                }
            } label: {
                Text(menuTitle).font(.scaled(12)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)  // works on both iPhone and Mac (.borderlessButton is Mac-only)
            .padding(.horizontal, 10)
            .frame(height: Style.lineMenuHeight)
            // the panel's bottom corners (39 pt) less the gap would be wider than the menu is tall:
            // a capsule is as round as it gets, and follows the corners with the same gap all round
            .background(.primary.opacity(0.10), in: Capsule())
            }
            if case .line(let id, _) = model.screen {
                Button { model.toggleFavouriteLine(id) } label: {
                    Image(systemName: model.isFavouriteLine(id) ? "star.fill" : "star")
                        .foregroundStyle(model.isFavouriteLine(id) ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.isFavouriteLine(id) ? "Remove from Favourites" : "Add to Favourites")
            }
            if case .stop(let s) = model.screen {
                Button { model.toggleFavourite(s) } label: {
                    Image(systemName: model.isFavourite(s) ? "star.fill" : "star")
                        .foregroundStyle(model.isFavourite(s) ? .yellow : .secondary)
                }.buttonStyle(.plain)
            }
        }
    }

    /// The open stop's or station's name (nil on the home and line screens).
    private var placeTitle: String? {
        switch model.screen {
        case .stop(let s): return s.title
        case .station(let id): return Rail.shared?.stations[id]?.shown
        default: return nil
        }
    }

    private var menuTitle: String {
        if case .line(let id, _) = model.screen {
            return "\(id) — " + (model.lines.first { $0.id == id }?.shown ?? "")
        }
        return String(localized: "Browse a line…")
    }

    @ViewBuilder private var content: some View {
        screenContent
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.scaled(11, .semibold)).foregroundStyle(.secondary).padding(.top, 4)
    }

    @ViewBuilder private var screenContent: some View {
        switch model.screen {
        case .home:
            Picker("", selection: $model.homeTab) {
                Text("Nearby Stops").tag(Model.HomeTab.nearby)
                Text("Favourites").tag(Model.HomeTab.favourites)
            }
            .pickerStyle(.segmented).labelsHidden()
            if model.homeTab == .nearby {
                list(model.stops, empty: String(localized: "Finding stops near you…"))
            } else {
                favouritesFilter
                list(favFilter == "lines" ? [] : model.favourites,
                     lines: favFilter == "stops" ? [] : model.favouriteLines,
                     empty: favFilter == "lines" ? String(localized: "No favourite lines yet. Tap ☆ on a line to add it.")
                          : favFilter == "stops" ? String(localized: "No favourite stops yet. Tap ☆ on a stop to add it.")
                          : String(localized: "No favourites yet. Tap ☆ on a stop or a line to add it."))
            }
        case .line:
            LineContent(model: model)
        case .station(let id):
            StationContent(model: model, id: id)
        case .stop(let stop):
            Text(String(localized: "Stop \(stop.id)").uppercased())
                .font(.scaled(11, .semibold)).foregroundStyle(.secondary)
            if let at = model.stopLinesSaved { SavedTimesNote(at: at) }
            if let lines = model.stopLines, !lines.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.networkAlerts.prefix(2)) { AlertCard(alert: $0) }
                        ForEach(model.alerts(for: lines.map(\.line))) { AlertCard(alert: $0) }
                        ForEach(Array(lines.enumerated()), id: \.element.id) { i, line in
                            Button { withAnimation { model.openLine(line.line, at: stop) } } label: { LineCard(line: line) }
                                .buttonStyle(.plain)
                                .appearing(i)
                        }
                    }
                }
            } else {
                // outside the scroll view: a lone message inside it wasn't drawn
                Text(model.stopLines == nil ? "Loading the lines at this stop…"
                     : model.error == nil ? "No lines stop here." : "Couldn't reach the bus service. Tap ↻ to try again.")
                    .font(.scaled(12)).foregroundStyle(.subtle)
                    .frame(maxWidth: .infinity).padding(.top, 20)
                Spacer(minLength: 0)
            }
        }
    }

    /// Long-press a favourite: give it a nickname, take it back, or remove the favourite.
    @ViewBuilder private func favouriteMenu(_ key: String, name: String, index: Int, count: Int, remove: @escaping () -> Void) -> some View {
        Button { nickname = model.nicknames[key] ?? ""; renaming = key } label: { Label("Rename…", systemImage: "pencil") }
        if model.nicknames[key] != nil {
            Button { model.setNickname("", for: key) } label: { Label("Remove Nickname", systemImage: "arrow.uturn.backward") }
        }
        if index > 0 {
            Button { withAnimation { model.moveFavourite(key, by: -index) } } label: { Label("Move to Top", systemImage: "arrow.up.to.line") }
            Button { withAnimation { model.moveFavourite(key, by: -1) } } label: { Label("Move Up", systemImage: "arrow.up") }
        }
        if index < count - 1 {
            Button { withAnimation { model.moveFavourite(key, by: 1) } } label: { Label("Move Down", systemImage: "arrow.down") }
        }
        Button(role: .destructive, action: remove) { Label("Remove from Favourites", systemImage: "star.slash") }
    }

    /// Favourites: stops, lines, or both.
    private var favouritesFilter: some View {
        Picker("", selection: $favFilter) {
            Text("All").tag("all")
            Text("Stops").tag("stops")
            Text("Lines").tag("lines")
        }
        .pickerStyle(.segmented).labelsHidden()
        .controlSize(.small)
    }

    private func list(_ stops: [Stop], lines: [String] = [], empty: String) -> some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(model.networkAlerts.prefix(2)) { AlertCard(alert: $0) }
                if stops.isEmpty && lines.isEmpty {
                    Text(empty).font(.scaled(12)).foregroundStyle(.secondary).padding(.top, 20)
                }
                ForEach(Array(stops.enumerated()), id: \.element.id) { i, stop in
                    Button { model.open(stop) } label: {
                        StopCard(stop: stop, metres: model.distance(to: stop), closest: i == 0 && (model.distance(to: stop) ?? .infinity) < 500,  // only when the list is around you
                                 subtitle: model.homeTab == .favourites ? favouriteSubtitle(model.favLines[stop.id]) : nil,
                                 favourite: model.homeTab == .nearby && model.isFavourite(stop))
                    }
                    .buttonStyle(.plain)
                    .contextMenu { if model.homeTab == .favourites { favouriteMenu("stop:\(stop.id)", name: stop.title, index: i, count: stops.count) { model.toggleFavourite(stop) } } }
                    .modifier(Reorderable(key: "stop:\(stop.id)", on: model.homeTab == .favourites, model: model))
                    .appearing(i)
                }
                ForEach(Array(lines.enumerated()), id: \.element) { i, id in
                    Button { withAnimation { model.openLine(id, at: nil) } } label: {
                        LineRow(line: model.lines.first { $0.id == id } ?? LineSummary(id: id), nickname: model.nicknames["line:\(id)"])
                    }
                    .buttonStyle(.plain)
                    .contextMenu { favouriteMenu("line:\(id)", name: model.nicknames["line:\(id)"] ?? id, index: i, count: lines.count) { model.toggleFavouriteLine(id) } }
                    .modifier(Reorderable(key: "line:\(id)", on: true, model: model))
                    .appearing(stops.count + i)
                }
            }
        }
    }
}

/// Drag a favourite onto another of the same kind to put it there.
struct Reorderable: ViewModifier {
    let key: String, on: Bool, model: Model
    func body(content: Content) -> some View {
        if on {
            content
                .draggable(key)
                .dropDestination(for: String.self) { items, _ in
                    guard let k = items.first, k != key else { return false }
                    withAnimation { model.moveFavourite(k, to: key) }
                    return true
                }
        } else { content }
    }
}

/// Rows ease in one after another: fade, slide up a little, scale from 97 % (motion.appear).
struct Appearing: ViewModifier {
    let index: Int
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .scaleEffect(shown ? 1 : 0.97)
            .onAppear {
                if LowPower.shared.on { shown = true; return }  // rows just appear
                withAnimation(.easeOut(duration: 0.38).delay(Double(min(index, 12)) * 0.035)) { shown = true }
            }
    }
}

extension View {
    func appearing(_ index: Int) -> some View { modifier(Appearing(index: index)) }
}

/// Over a stop's saved times while offline: when they were seen, so "12'" reads as "12' back then".
struct SavedTimesNote: View {
    let at: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let ago = max(0, Int(ctx.date.timeIntervalSince(at) / 60))
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ago == 0 ? String(localized: "Saved just now") : String(localized: "Saved \(ago) min ago, at \(at.formatted(date: .omitted, time: .shortened))"))
                        .font(.scaled(13, .semibold))
                    Text("You're offline: these are the times as they were then.")
                        .font(.scaled(12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .card()
        }
    }
}
