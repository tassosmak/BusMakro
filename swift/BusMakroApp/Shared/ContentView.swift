import BusMakroKit
import MapKit
import SwiftUI

/// The main screen, laid out like the Mac app: full-bleed Apple Maps, the floating search bar and
/// recent-stop chips at the top, round map buttons on the right, and the glass panel at the bottom.
struct ContentView: View {
    @State private var model = Model()
    @State private var sheetHeight: CGFloat = 360
    @State private var fittedLine: String?
    @AppStorage("mapStyle") private var mapStyle = "system"
    @AppStorage("showRecents") private var showRecents = true
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.9755, longitude: 23.7348),  // Syntagma
        span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)))

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                map
                VStack(spacing: 8) {
                    TopBar(text: $model.searchText, onRefresh: { Task { await refresh() } },
                           onSettings: { model.showSettings = true })
                    if model.screen == .home && !model.recents.isEmpty && model.searchText.isEmpty && showRecents {
                        RecentChips(stops: model.recents.map(\.title)) { i in model.open(model.recents[i]) }
                    }
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            RoundButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Expand the map") {
                                withAnimation(.spring(duration: 0.3)) { sheetHeight = 66 }
                            }
                            RoundButton(symbol: "location", help: "Locate Me") { locate() }
                        }
                    }
                    Sheet(model: model, height: $sheetHeight, range: 66...(geo.size.height - 120))
                }
                .padding(.horizontal, 10)
                .padding(.top, 34)
                .padding(.bottom, 10)
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
        .onChange(of: model.userLocation?.latitude) {
            // first fix only: centre on you and list the stops around you (later fixes don't move the map)
            guard let c = model.userLocation, model.screen == .home, !model.centredOnUser else { return }
            model.centredOnUser = true
            withAnimation { camera = .region(MKCoordinateRegion(center: c, span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008))) }
            Task { await model.loadStops(near: c, force: true) }
        }
    }

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
                        BusMarker(bearing: b.bearing, faded: (b.positionAt.map { Date().timeIntervalSince($0) > 120 } ?? false))
                    }
                }
            }
            ForEach(shownStops) { stop in
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude)) {
                    let selected = model.screen == .stop(stop)
                    Circle().fill(selected ? Color.orange : Color(red: 0.09, green: 0.47, blue: 1.0))  // #1677ff
                        .frame(width: selected ? 15 : 12, height: selected ? 15 : 12)
                        .overlay(Circle().stroke(.white, lineWidth: selected ? 3 : 2))
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .onTapGesture { model.open(stop) }
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls { }  // no zoom or compass buttons, like the Mac app
        .onMapCameraChange(frequency: .onEnd) { ctx in
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

    var body: some View {
        ZStack {
            if let b = bearing {
                Image(systemName: "arrowtriangle.up.fill").font(.system(size: 10)).foregroundStyle(Color(red: 0.10, green: 0.53, blue: 0.33))
                    .offset(y: -18).rotationEffect(.degrees(b))
            }
            Image(systemName: "bus.fill").font(.system(size: 12)).foregroundStyle(.white)
                .frame(width: 27, height: 27)
                .background(Color(red: 0.10, green: 0.53, blue: 0.33), in: Circle())  // #198754
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
        }
        .opacity(faded ? 0.45 : 1)
        .animation(.easeInOut(duration: 1.5), value: bearing)
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
