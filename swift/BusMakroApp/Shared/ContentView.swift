import BusMakroKit
import CoreSpotlight
import MapKit
import SwiftUI

/// The main screen, laid out like the Mac app: full-bleed Apple Maps, the floating search bar and
/// recent-stop chips at the top, round map buttons on the right, and the glass panel at the bottom.
struct ContentView: View {
    @State private var model = Model()
    @State private var links = Links.shared
    /// The panel's height, in its own object: dragging changes it every frame, and only the views that
    /// read it (panel, bars, map buttons) redraw, not this whole screen with the map and its pins.
    @State private var panel = Panel()
    @State private var fittedLine: String?
    @State private var menuOpen = false
    @State private var showMetroMap = false
    @State private var showDebug = false  // Debug builds only
    @State private var refreshing = false
    /// Where the map was before a line opened, to go back there when it closes.
    @State private var beforeLine: MKCoordinateRegion?
    /// The top bar's height (search bar and chips), so the zoom hint sits right under it.
    @State private var topHeight: CGFloat = 0
    @State private var followedAt: CLLocationCoordinate2D?
    @State private var visibleRegion: MKCoordinateRegion?
    /// The stops inside the visible map (from the stop index), worked out when the map stops moving.
    @State private var regionStops: [Stop] = []
    @AppStorage("mapStyle") private var mapStyle = "system"
    @AppStorage("showRecents") private var showRecents = true
    @AppStorage("map3D") private var map3D = false
    // map layers (the layers button, or Settings)
    @AppStorage("showStops") private var showStops = true
    @AppStorage("favColor") private var favColor = Style.favouriteColor
    @AppStorage("showBuses") private var showBuses = true
    @AppStorage("showMetro") private var showMetro = true
    @AppStorage("showTram") private var showTram = true
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.9755, longitude: 23.7348),  // Syntagma
        span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)))

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                map
                VStack(spacing: 8) {
                    topArea.overlay(alignment: .top) { zoomHintView }  // outside the bars' fade
                    Spacer()
                    mapButtons
                    PanelReader(panel: panel) { p in
                    Sheet(model: model, height: Bindable(p).height, range: 66...(geo.size.height - 120))
                        // while searching the panel (and the map buttons) step aside for the keyboard and results
                        .offset(y: model.searchActive ? p.height + 40 : 0)
                        .opacity(model.searchActive ? 0 : 1)
                        .allowsHitTesting(!model.searchActive)
                        .animation(.spring(response: 0.36, dampingFraction: 1), value: model.searchActive)
                    }
                }
                .padding(.horizontal, Style.panelInset)
                .padding(.top, 4)                  // right under the status bar
                .padding(.bottom, Style.panelInset) // the panel hugs the screen's bottom corners
                .ignoresSafeArea(.container, edges: .bottom)  // measured from the screen edge, not the home indicator
            }
        }
        .overlay { SideMenu(open: $menuOpen, onMetroMap: { showMetroMap = true }, onSettings: { model.showSettings = true }, onTrip: { model.showTrip = true }, onDebug: { showDebug = true }) }
        .fullScreenCoverOrSheet(isPresented: $showMetroMap) { MetroMapView() }
        .ignoresSafeArea(.keyboard)
        .preferredColorScheme(mapStyle == "light" ? .light : mapStyle == "dark" ? .dark : nil)
        .sheet(isPresented: $model.showSettings) { SettingsView(model: model) }
        .sheet(isPresented: $model.showTrip) { TripView(model: model) }
        #if DEBUG
        .sheet(isPresented: $showDebug) { DebugView(model: model) }
        #endif
        .fullScreenCoverOrSheet(isPresented: $model.showWelcome) {
            WelcomeView {
                UserDefaults.standard.set(true, forKey: "onboarded")
                model.showWelcome = false
                model.askLocation()
            }
        }
        .onChange(of: model.stopIndex == nil) { if let r = visibleRegion { regionStops = model.stops(in: r) } }
        .task {
            if let link = links.pending { links.pending = nil; Task { await model.follow(link) } }  // launched from a quick action
            await model.start()
            await model.loadStops(near: CLLocationCoordinate2D(latitude: 37.9755, longitude: 23.7348))  // until a fix arrives
        }
        .modifier(LinkHandling(model: model, links: links, menuOpen: $menuOpen))
        .onChange(of: model.variantID) {
            // a line opened: show its whole route, like the Mac app's fit on the stops
            // once per line: refreshes can re-pick the variant, and must not pull the map away from where you zoomed
            guard case .line(let lineID, _) = model.screen, fittedLine != lineID, let d = model.lineDetail,
                  let vid = model.variantID, let shape = d.variants[vid]?.shape, !shape.isEmpty else { return }
            fittedLine = lineID
            let lats = shape.map { $0[0] }, lons = shape.map { $0[1] }
            let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
            // extra room south for the panel, which covers the lower part of the map
            let span = MKCoordinateSpan(latitudeDelta: (lats.max()! - lats.min()!) * 2.2, longitudeDelta: (lons.max()! - lons.min()!) * 1.3)
            withAnimation { camera = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: center.latitude - span.latitudeDelta * 0.2, longitude: center.longitude), span: span)) }
        }
        .onChange(of: model.tick) {
            // follow the pinned bus: re-centre only once it has moved ~25 m, with a short animation.
            // (Animating the camera every second kept the map always mid-animation, and taps on the
            // panel were lost while following.)
            guard let p = model.pinnedPosition else { followedAt = nil; return }
            if let f = followedAt, Geo.distance(f.latitude, f.longitude, p.latitude, p.longitude) < 25 { return }
            followedAt = p
            withAnimation(.easeInOut(duration: 0.4)) {
                camera = .camera(MapCamera(centerCoordinate: p, distance: 1400, pitch: map3D ? 45 : 0))
            }
        }
        .onChange(of: map3D) {
            // 3D buildings only show on a tilted map: tilt to 55° (and back to flat) around the current centre
            guard let region = visibleRegion else { return }
            withAnimation(.easeInOut(duration: 0.6)) {
                camera = .camera(MapCamera(centerCoordinate: region.center,
                                           distance: max(600, region.span.latitudeDelta * 111_000 * 1.6),
                                           pitch: map3D ? 55 : 0))
            }
        }
        .onChange(of: model.screen) { old, new in
            // a line takes over the map; leaving it puts the map back where it was
            if case .line = new { if case .line = old {} else { beforeLine = visibleRegion }; return }
            guard case .line = old else { return }
            fittedLine = nil
            if let r = beforeLine { withAnimation(.easeInOut(duration: 0.5)) { camera = .region(r) } }
            beforeLine = nil
        }
        .onChange(of: model.homeTab) { if model.homeTab == .favourites { Task { await model.loadFavourites() } } }
        .onChange(of: model.userLocation?.latitude) {
            // first fix only: centre on you and list the stops around you (later fixes don't move the map)
            guard let c = model.userLocation, model.screen == .home, !model.centredOnUser else { return }
            model.centredOnUser = true
            withAnimation { camera = .region(MKCoordinateRegion(center: c, span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008))) }
            Task { await model.loadStops(near: c, force: true) }
        }
    }

    /// The search bar, the results that drop down from it, and the recent-stop chips. The bar slides
    /// away as the panel goes down to the strip (the Mac app's map focus); while searching it stays.
    private var topArea: some View {
        VStack(spacing: 8) {
            TopBar(text: $model.searchText, searching: $model.searchActive, refreshing: refreshing, onRefresh: { Task { await refresh() } },
                   onMenu: { menuOpen = true })
            if showResults {
                SearchResults(model: model)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if showChips {
                RecentChips(stops: model.recents.map(\.title)) { i in model.open(model.recents[i]) }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 1), value: showResults)
        .modifier(BarsFollowPanel(panel: panel, searching: model.searchActive))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topHeight = $0 }
    }

    /// "Zoom in to see bus stops": just under the bars, and up near the top as they slide away
    /// (it moves with the panel's height, so it follows the drag and the snap frame by frame).
    private var zoomHintView: some View {
        Group {
            if zoomHint {
                Text("Zoom in to see bus stops")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.thinMaterial.opacity(0.7), in: Capsule())
                    .transition(.opacity)
            }
        }
        .modifier(HintFollowsPanel(panel: panel, below: topHeight))
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.25), value: zoomHint)
    }

    private var showResults: Bool {
        model.searchActive && !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var showChips: Bool {
        model.screen == .home && !model.recents.isEmpty && model.searchText.isEmpty && showRecents && !model.searchActive
    }

    /// Expand the map and Locate Me, on the right above the panel (hidden while searching).
    private var mapButtons: some View {
        HStack {
            Spacer()
            VStack(spacing: 10) {
                PanelReader(panel: panel) { p in
                RoundButton(symbol: p.height <= 66 ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                            help: "Expand the map") {
                    withAnimation(.spring(response: 0.36, dampingFraction: 1)) { p.height = p.height <= 66 ? 360 : 66 }
                }
                }
                RoundButton(symbol: "location", help: "Locate Me") { locate() }
                layersButton
            }
            .opacity(model.searchActive ? 0 : 1)
            .animation(.spring(response: 0.36, dampingFraction: 1), value: model.searchActive)
        }
    }

    /// What the map shows: bus stops, live buses, metro, tram (each can be hidden).
    private var layersButton: some View {
        Menu {
            Toggle(isOn: $showStops) { Label("Bus Stops", systemImage: "bus") }
            Toggle(isOn: $showBuses) { Label("Live Buses", systemImage: "dot.radiowaves.left.and.right") }
            Toggle(isOn: $showMetro) { Label("Metro", systemImage: "tram.fill.tunnel") }
            Toggle(isOn: $showTram) { Label("Tram", systemImage: "tram.fill") }
        } label: {
            Image(systemName: "square.3.layers.3d")
                .font(.system(size: 15, weight: .medium))
                .frame(width: Style.roundButton, height: Style.roundButton)
                .contentShape(Circle())
        }
        #if os(iOS)
        .menuActionDismissBehavior(.disabled)  // flip several at once
        #endif
        .buttonStyle(.plain)
        .glass(Circle())
        .accessibilityLabel("Map Layers")
    }

    /// 0 with the panel at the strip, 1 from the normal height up.

    private var map: some View {
        Map(position: $camera) {
            UserAnnotation()
            if case .line = model.screen, let d = model.lineDetail, let vid = model.variantID, let v = d.variants[vid] {
                // the route on the roads, with a white casing (map.html's route-casing + route-line)
                let coords = v.shape.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
                MapPolyline(coordinates: coords).stroke(.white, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: coords).stroke(Color(red: 0.09, green: 0.47, blue: 1.0),
                                                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                ForEach(v.stops, id: \.self) { sid in
                    if let st = d.stops[sid] {
                        Annotation("", coordinate: CLLocationCoordinate2D(latitude: st.lat, longitude: st.lon)) {
                            let sel = sid == model.lineStop
                            Circle().fill(sel ? Color.orange : Color(red: 0.09, green: 0.47, blue: 1.0))
                                .frame(width: sel ? 15 : 10, height: sel ? 15 : 10)
                                .overlay(Circle().stroke(.white, lineWidth: sel ? 3 : 2))
                                .frame(width: 36, height: 36).contentShape(Circle())  // easier to hit than the 10 pt dot
                                .onTapGesture { model.lineStop = sid }
                                .accessibilityLabel(st.name)
                                .accessibilityAddTraits(sel ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                }
                ForEach(showBuses ? model.vehicles : []) { b in
                    Annotation("", coordinate: model.drawn[b.id] ?? CLLocationCoordinate2D(latitude: b.latitude, longitude: b.longitude)) {
                        BusMarker(bearing: b.bearing, faded: (b.positionAt.map { Date().timeIntervalSince($0) > 120 } ?? false),
                                  pinned: model.pinned == b.id, fix: b.positionAt)
                            .onTapGesture { model.pinned = model.pinned == b.id ? nil : b.id }
                            .accessibilityLabel(Text("Bus \(b.id)"))
                            .accessibilityHint(model.pinned == b.id ? Text("Stop following") : Text("Follow this bus"))
                            .accessibilityAddTraits(.isButton)
                    }
                }
            }
            if case .stop(let stop) = model.screen {
                // the buses on their way to this stop, labelled with their line; tap opens it, following the bus
                ForEach(showBuses ? model.stopBuses : [], id: \.vehicle.id) { b in
                    Annotation("", coordinate: model.drawn[b.vehicle.id] ?? CLLocationCoordinate2D(latitude: b.vehicle.latitude, longitude: b.vehicle.longitude)) {
                        BusMarker(bearing: b.vehicle.bearing, label: b.line, fix: b.vehicle.positionAt)
                            .onTapGesture { model.pendingPin = b.vehicle.id; model.openLine(b.line, at: stop) }
                            .accessibilityLabel(Text("Line \(b.line) bus"))
                            .accessibilityAddTraits(.isButton)
                    }
                }
            }
            if let rail = Rail.shared, showMetro || showTram || isStation {
                switch model.screen {
                case .home, .station:
                    RailMapLayer(rail: rail, selected: selectedStation,
                                 stations: (visibleRegion?.span.latitudeDelta ?? 0) <= 0.08,
                                 kinds: Set((showMetro ? ["metro"] : []) + (showTram ? ["tram"] : []))) { id in withAnimation { model.openStation(id) } }
                default: EmptyMapContent()
                }
            }
            ForEach(shownStops) { stop in
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude)) {
                    let selected = model.screen == .stop(stop)
                    StopPin(selected: selected, favourite: model.isFavourite(stop) ? Color(hex: favColor) : nil)
                        .onTapGesture { model.open(stop) }
                        .accessibilityLabel(Text("Stop \(stop.title)"))
                        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .mapStyle(.standard(elevation: map3D ? .realistic : .flat, pointsOfInterest: .excludingAll))
        .mapControls { }  // no zoom or compass buttons, like the Mac app
        // a fixed inset (the slim strip's height), not the panel's: changing the map's safe area on every
        // animation frame made Apple Maps re-centre continuously, so the whole map jiggled
        .safeAreaPadding(.bottom, 66 + Style.panelInset * 2)
        .onMapCameraChange(frequency: .onEnd) { ctx in
            visibleRegion = ctx.region
            regionStops = model.stops(in: ctx.region)
            // zoomed far out, the nearby list stays around you rather than following the map
            let far = ctx.region.span.latitudeDelta > Model.stopsMaxSpan
            let centre = far ? (model.userLocation ?? ctx.region.center) : ctx.region.center
            if model.screen == .home { fittedLine = nil; Task { await model.loadStops(near: centre) } }
        }
        .ignoresSafeArea()
    }

    /// Faint hint when the map is zoomed too far out for stop pins.
    private var zoomHint: Bool {
        model.screen == .home && model.homeTab != .favourites && showStops && !model.searchActive
            && (visibleRegion?.span.latitudeDelta ?? 0) > Model.stopsMaxSpan
    }

    private var isStation: Bool { if case .station = model.screen { true } else { false } }
    private var selectedStation: String? { if case .station(let id) = model.screen { id } else { nil } }

    private var shownStops: [Stop] {
        switch model.screen {
        case .home:
            if model.homeTab == .favourites { return model.favourites }
            guard showStops else { return [] }
            // zoomed far out the pins would cover the city: only your favourites until you zoom in
            guard (visibleRegion?.span.latitudeDelta ?? 0) <= Model.stopsMaxSpan else { return model.favourites }
            // every stop on screen, plus the nearby list's (OASA's, with street names) where they're missing
            let ids = Set(regionStops.map(\.id))
            let all = regionStops + model.stops.filter { !ids.contains($0.id) }
            // favourites last, so their pins sit on top of the others
            return all.filter { !model.isFavourite($0) } + model.favourites
        case .stop(let s): return [s]
        case .line, .station: return []
        }
    }

    private func locate() {
        guard let c = model.userLocation else { return }
        withAnimation { camera = .region(MKCoordinateRegion(center: c, span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008))) }
    }

    /// ↻ fetches whatever is on screen again: nearby stops, a stop's lines, or a line's buses (it only
    /// handled the stop screen before, so on home and line views it did nothing).
    /// The ↻ spins while it works, at least one turn, so a fast answer still shows something happened.
    private func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        async let minimum: Void = { try? await Task.sleep(for: .milliseconds(700)) }()
        await model.retry()
        await minimum
        refreshing = false
    }
}

/// A live bus: green dot with a white ring and a heading arrow; faded when its fix is old.
struct BusMarker: View {
    let bearing: Double?
    var faded = false
    var label: String? = nil
    var pinned = false
    /// The GPS fix time: a new one sends a ring rippling out (the Mac app's ping).
    var fix: Date? = nil
    @State private var ripple = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(Color(red: 0.10, green: 0.53, blue: 0.33), lineWidth: 2)
                .frame(width: 27, height: 27)
                .scaleEffect(ripple ? 2.4 : 1).opacity(ripple ? 0 : 0.8)
            if let b = bearing {
                Image(systemName: "arrowtriangle.up.fill").font(.system(size: 10)).foregroundStyle(Color(red: 0.10, green: 0.53, blue: 0.33))
                    .offset(y: -18).rotationEffect(.degrees(b))
            }
            Group {
                if let label { Text(label).font(.system(size: 10, weight: .bold)).minimumScaleFactor(0.6) }
                else { Image(systemName: "bus.fill").font(.system(size: 12)) }
            }
            .foregroundStyle(.white)
            .frame(width: 27, height: 27)
            .background(Color(red: 0.10, green: 0.53, blue: 0.33), in: Circle())  // #198754
            .overlay(Circle().stroke(pinned ? Color.orange : .white, lineWidth: 2))
            .background(Circle().fill(Color.orange.opacity(pinned ? 0.4 : 0)).frame(width: 37, height: 37))
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
        }
        .opacity(faded ? 0.45 : 1)
        .animation(.easeInOut(duration: 1.5), value: bearing)
        .onChange(of: fix) {
            ripple = false
            guard !reduceMotion, !LowPower.shared.on else { return }
            withAnimation(.easeOut(duration: 1.2)) { ripple = true }
        }
    }
}

extension View {
    /// Full-screen on iPhone, a sheet on Mac.
    @ViewBuilder func fullScreenCoverOrSheet<C: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> C) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented, content: content)
        #else
        sheet(isPresented: isPresented, content: content)
        #endif
    }
}

/// A bus-stop pin: a small rounded sign with a bus, on a short stem; orange and larger when selected.
struct StopPin: View {
    var selected = false
    /// A favourite's colour (Settings → Favourite Stops); nil for the usual blue.
    var favourite: Color? = nil
    var body: some View {
        let tint = selected ? Color.orange : favourite ?? Color(red: 0.09, green: 0.47, blue: 1.0)
        let size: CGFloat = selected ? 30 : 22
        VStack(spacing: 0) {
            Image(systemName: "bus.fill")
                .font(.system(size: size * 0.48, weight: .semibold)).foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(tint, in: RoundedRectangle(cornerRadius: size * 0.3))
                .overlay(RoundedRectangle(cornerRadius: size * 0.3).stroke(.white, lineWidth: 1.5))
            Rectangle().fill(tint).frame(width: 2, height: selected ? 8 : 5)
        }
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        .frame(width: 44, height: 48).contentShape(Rectangle())  // a finger-sized tap area around the sign (alone it is 22 pt)
        .offset(y: -(size + (selected ? 8 : 5)) / 2)  // the stem's foot is on the stop
        .animation(.smooth(duration: 0.25), value: selected)
    }
}

/// Links from outside (quick actions, Siri, Spotlight, busmakro:// URLs) followed in the model, and
/// the quick actions and Spotlight kept in step with your stops. (A modifier of its own: in the main
/// body it made the expression too big for the compiler.)
struct LinkHandling: ViewModifier {
    let model: Model
    let links: Links
    @Binding var menuOpen: Bool

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in if let link = AppLink(url: url) { links.pending = link } }
            .onContinueUserActivity(CSSearchableItemActionType) { a in if let link = SpotlightStops.link(a) { links.pending = link } }
            .onChange(of: links.pending) {
                guard let link = links.pending else { return }
                links.pending = nil
                menuOpen = false
                Task { await model.follow(link) }
            }
            .onChange(of: model.favourites, initial: true) {
                SpotlightStops.index(favourites: model.favourites, recents: model.recents)
                #if os(iOS)
                QuickActions.update(favourites: model.favourites)
                #endif
            }
            .onChange(of: model.recents) { SpotlightStops.index(favourites: model.favourites, recents: model.recents) }
    }
}

@Observable final class Panel {
    var height: CGFloat = 360
    /// 1 with the panel up, 0 down at the slim strip: the top bars slide away in between.
    var barShown: Double { min(1, max(0, (height - 66) / (360 - 66))) }
}

/// Reads the panel's height in its own body, so only this part redraws while it's dragged.
struct PanelReader<Content: View>: View {
    let panel: Panel
    @ViewBuilder var content: (Panel) -> Content
    var body: some View { content(panel) }
}

/// The search bar and chips fade and rise as the panel goes down (they stay while searching).
struct BarsFollowPanel: ViewModifier {
    let panel: Panel, searching: Bool
    func body(content: Content) -> some View {
        content
            .opacity(searching ? 1 : panel.barShown)
            .offset(y: searching ? 0 : (panel.barShown - 1) * 40)
            .allowsHitTesting(searching || panel.barShown > 0.5)
    }
}

/// The zoom hint sits under the bars, and rises with them.
struct HintFollowsPanel: ViewModifier {
    let panel: Panel, below: CGFloat
    func body(content: Content) -> some View { content.offset(y: 6 + panel.barShown * (below + 2)) }
}
