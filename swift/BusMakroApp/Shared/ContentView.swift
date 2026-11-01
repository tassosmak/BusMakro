import BusMakroKit
import MapKit
import SwiftUI

/// The main screen, laid out like the Mac app: full-bleed Apple Maps, the floating search bar and
/// recent-stop chips at the top, round map buttons on the right, and the glass panel at the bottom.
struct ContentView: View {
    @State private var model = Model()
    @State private var sheetHeight: CGFloat = 360
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.9755, longitude: 23.7348),  // Syntagma
        span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)))

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                map
                VStack(spacing: 8) {
                    TopBar(text: $model.searchText) { Task { await refresh() } }
                    if model.screen == .home && !model.recents.isEmpty && model.searchText.isEmpty {
                        RecentChips(stops: model.recents.map(\.title)) { i in Task { await model.open(model.recents[i]) } }
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
        .task { await model.start() }
    }

    private var map: some View {
        Map(position: $camera) {
            UserAnnotation()
            ForEach(shownStops) { stop in
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude)) {
                    let selected = model.screen == .stop(stop)
                    Circle().fill(selected ? Color.orange : Color(red: 0.09, green: 0.47, blue: 1.0))  // #1677ff
                        .frame(width: selected ? 15 : 12, height: selected ? 15 : 12)
                        .overlay(Circle().stroke(.white, lineWidth: selected ? 3 : 2))
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .onTapGesture { Task { await model.open(stop) } }
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls { }  // no zoom or compass buttons, like the Mac app
        .onMapCameraChange(frequency: .onEnd) { ctx in
            if model.screen == .home { Task { await model.loadStops(near: ctx.region.center) } }
        }
        .ignoresSafeArea()
    }

    private var shownStops: [Stop] {
        switch model.screen {
        case .home: return model.homeTab == .nearby ? model.stops : model.favourites
        case .stop(let s): return [s]
        }
    }

    private func locate() {
        guard let c = model.userLocation else { return }
        withAnimation { camera = .region(MKCoordinateRegion(center: c, span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008))) }
    }

    private func refresh() async {
        if case .stop(let s) = model.screen { await model.open(s) }
    }
}
