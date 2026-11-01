import BusMakroKit
import MapKit
import SwiftUI

/// The main screen, laid out like the Mac app: full-bleed Apple Maps, the floating search bar and
/// recent-stop chips at the top, round map buttons on the right, and the glass panel at the bottom.
struct ContentView: View {
    @State private var model = Model()
    @State private var sheetHeight: CGFloat = 360
    @State private var fittedLine: String?
    @State private var followedAt: CLLocationCoordinate2D?
    @State private var visibleRegion: MKCoordinateRegion?
    @AppStorage("mapStyle") private var mapStyle = "system"
    @AppStorage("showRecents") private var showRecents = true
    @AppStorage("map3D") private var map3D = false
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.9755, longitude: 23.7348),  // Syntagma
        span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)))

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                map
                VStack(spacing: 8) {
                    // the top bar slides away as the panel goes down to the strip (the Mac app's map focus)
                    VStack(spacing: 8) {
                        TopBar(text: $model.searchText, onRefresh: { Task { await refresh() } },
                               onSettings: { model.showSettings = true })
                        if model.screen == .home && !model.recents.isEmpty && model.searchText.isEmpty && showRecents {
                            RecentChips(stops: model.recents.map(\.title)) { i in model.open(model.recents[i]) }
                        }
                    }
                    .opacity(barShown)
                    .offset(y: (barShown - 1) * 40)
                    .allowsHitTesting(barShown > 0.5)
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            RoundButton(symbol: sheetHeight <= 66 ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                                        help: "Expand the map") {
                                withAnimation(.spring(duration: 0.3)) { sheetHeight = sheetHeight <= 66 ? 360 : 66 }
                            }
                            RoundButton(symbol: "location", help: "Locate Me") { locate() }
                        }
                    }
                    Sheet(model: model, height: $sheetHeight, range: 66...(geo.size.height - 120))
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)      // right under the status bar
                .padding(.bottom, 0)   // the panel sits on the home-indicator line
            }
        }
        .preferredColorScheme(mapStyle == "light" ? .light : mapStyle == "dark" ? .dark : nil)
        .sheet(isPresented: $model.showSettings) { SettingsView(model: model) }
        .fullScreenCoverOrSheet(isPresented: $model.showWelcome) {
            WelcomeView {
                UserDefaults.standard.set(true, forKey: "onboarded")
                model.showWelcome = false
                model.askLocation()
            }
        }
        .task {
            await model.start()
            await model.loadStops(near: CLLocationCoordinate2D(latitude: 37.9755, longitude: 23.7348))  // until a fix arrives
        }
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
        .onChange(of: model.homeTab) { if model.homeTab == .favourites { Task { await model.loadFavourites() } } }
        .onChange(of: model.userLocation?.latitude) {
            // first fix only: centre on you and list the stops around you (later fixes don't move the map)
            guard let c = model.userLocation, model.screen == .home, !model.centredOnUser else { return }
            model.centredOnUser = true
            withAnimation { camera = .region(MKCoordinateRegion(center: c, span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008))) }
            Task { await model.loadStops(near: c, force: true) }
        }
    }

    /// 0 with the panel at the strip, 1 from the normal height up.
    private var barShown: Double { min(1, max(0, (sheetHeight - 66) / (360 - 66))) }

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
                                .onTapGesture { model.lineStop = sid }
                        }
                    }
                }
                ForEach(model.vehicles) { b in
                    Annotation("", coordinate: model.drawn[b.id] ?? CLLocationCoordinate2D(latitude: b.latitude, longitude: b.longitude)) {
                        BusMarker(bearing: b.bearing, faded: (b.positionAt.map { Date().timeIntervalSince($0) > 120 } ?? false),
                                  pinned: model.pinned == b.id, fix: b.positionAt)
                            .onTapGesture { model.pinned = model.pinned == b.id ? nil : b.id }
                    }
                }
            }
            if case .stop(let stop) = model.screen {
                // the buses on their way to this stop, labelled with their line; tap opens it, following the bus
                ForEach(model.stopBuses, id: \.vehicle.id) { b in
                    Annotation("", coordinate: model.drawn[b.vehicle.id] ?? CLLocationCoordinate2D(latitude: b.vehicle.latitude, longitude: b.vehicle.longitude)) {
                        BusMarker(bearing: b.vehicle.bearing, label: b.line, fix: b.vehicle.positionAt)
                            .onTapGesture { model.pendingPin = b.vehicle.id; model.openLine(b.line, at: stop) }
                    }
                }
            }
            ForEach(shownStops) { stop in
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude)) {
                    let selected = model.screen == .stop(stop)
                    StopPin(selected: selected).onTapGesture { model.open(stop) }
                }
            }
        }
        .mapStyle(.standard(elevation: map3D ? .realistic : .flat, pointsOfInterest: .excludingAll))
        .mapControls { }  // no zoom or compass buttons, like the Mac app
        .safeAreaPadding(.bottom, sheetHeight + 8)  // the Maps logo and Legal sit just above the panel
        .onMapCameraChange(frequency: .onEnd) { ctx in
            visibleRegion = ctx.region
            if model.screen == .home { fittedLine = nil; Task { await model.loadStops(near: ctx.region.center) } }
        }
        .ignoresSafeArea()
    }

    private var shownStops: [Stop] {
        switch model.screen {
        case .home: return model.homeTab == .nearby ? model.stops : model.favourites
        case .stop(let s): return [s]
        case .line: return []
        }
    }

    private func locate() {
        guard let c = model.userLocation else { return }
        withAnimation { camera = .region(MKCoordinateRegion(center: c, span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008))) }
    }

    private func refresh() async {
        if case .stop(let s) = model.screen { await model.loadStopLines(s) }
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
    var body: some View {
        let tint = selected ? Color.orange : Color(red: 0.09, green: 0.47, blue: 1.0)
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
        .offset(y: -(size + (selected ? 8 : 5)) / 2)  // the stem's foot is on the stop
        .animation(.smooth(duration: 0.25), value: selected)
    }
}
