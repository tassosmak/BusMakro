import SwiftUI

/// The left side menu (the ☰ in the search bar): app info with the logo on top, then Metro Map and
/// Settings. Slides in from the left over a dimmed map; tap outside or swipe left to close.
struct SideMenu: View {
    @Binding var open: Bool
    var onMetroMap: () -> Void
    var onSettings: () -> Void
    var onTrip: () -> Void = {}
    var onPlace: (SavedPlace) -> Void = { _ in }
    var onDebug: () -> Void = {}
    @Environment(\.openURL) private var openURL
    @State private var dragX: CGFloat = 0
    private let width: CGFloat = 290

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return String(localized: "Version \(v)")
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(open ? 0.35 : 0).ignoresSafeArea()
                .onTapGesture { close() }
                .allowsHitTesting(open)
            VStack(alignment: .leading, spacing: 0) {
                // app info
                HStack(spacing: 14) {
                    Image("Logo").resizable().frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BusMakro").font(.scaled(22, .bold, design: .rounded))
                        Text("Athens buses, live").font(.scaled(13)).foregroundStyle(.secondary)
                        Text(version).font(.scaled(11)).foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 70).padding(.bottom, 26)
                Divider()
                VStack(spacing: 4) {
                    ForEach(SavedPlace.allCases) { k in row(k.icon, k.action) { close(); onPlace(k) } }
                    row("arrow.triangle.turn.up.right.diamond.fill", "Plan a Trip") { close(); onTrip() }
                    row("tram.fill", "Metro Map") { close(); onMetroMap() }
                    row("gearshape.fill", "Settings") { close(); onSettings() }
                    row("envelope.fill", "Contact", external: true) {
                        close(); openURL(URL(string: "mailto:amakrostergios@icloud.com?subject=BusMakro")!)
                    }
                    if DebugTools.available {  // Xcode and TestFlight builds only
                        row("ladybug.fill", "Debug") { close(); onDebug() }
                    }
                }
                .padding(.top, 14)
                Spacer()
                Text("Data: OASA and STASY; live positions via athens-transit-rt. Unofficial app, not affiliated with OASA or STASY.")
                    .font(.scaled(11)).foregroundStyle(.tertiary).padding(.bottom, 30)
            }
            .padding(.horizontal, 22)
            .frame(width: width, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(.regularMaterial)
            .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 28, topTrailingRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 16, x: 4)
            .ignoresSafeArea()
            .offset(x: open ? min(0, dragX) : -width - 20)
            .gesture(DragGesture()
                .onChanged { dragX = $0.translation.width }
                .onEnded { g in
                    if g.translation.width < -80 || g.predictedEndTranslation.width < -160 { close() }
                    withAnimation(.spring(response: 0.36, dampingFraction: 1)) { dragX = 0 }
                })
        }
        .animation(.spring(response: 0.36, dampingFraction: 1), value: open)
    }

    private func close() { open = false }

    private func row(_ symbol: String, _ title: LocalizedStringKey, external: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.scaled(17)).foregroundStyle(.tint).frame(width: 28)
                Text(title).font(.scaled(16, .medium))
                Spacer()
                Image(systemName: external ? "arrow.up.right" : "chevron.right").font(.scaled(13)).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12).padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The STASY metro / tram map: pinch to zoom, drag to pan, double-tap to zoom in or out.
struct MetroMapView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            Group {
            #if os(iOS)
            ZoomableImage(name: "MetroMap")  // the system's own pinch, pan, bounce and double-tap
            #else
            GeometryReader { geo in
                Image("MetroMap").resizable().scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(SimultaneousGesture(
                        MagnifyGesture()
                            .onChanged { scale = min(6, max(1, baseScale * $0.magnification)) }
                            .onEnded { _ in baseScale = scale; if scale == 1 { reset() } },
                        DragGesture()
                            .onChanged { g in
                                guard scale > 1 else { return }
                                offset = CGSize(width: baseOffset.width + g.translation.width,
                                                height: baseOffset.height + g.translation.height)
                            }
                            .onEnded { _ in baseOffset = offset }))
            }
            #endif
            }
            .background(Color(white: 0.93))
            .overlay(alignment: .bottom) {
                Text("Map: STASY S.A.").font(.scaled(11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule()).padding(.bottom, 10)
            }
            .environment(\.colorScheme, .light)  // the map is a light image: keep the title and Done readable
            .navigationTitle("Metro Map")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { Button("Done") { dismiss() } }
        }
        .preferredColorScheme(.light)
    }

    private func reset() { scale = 1; baseScale = 1; offset = .zero; baseOffset = .zero }
}

#if os(iOS)
/// An image in a UIScrollView: pinch zooms around your fingers, pans with edges that stop at the
/// image, and a double tap zooms in on that spot (or back out).
struct ZoomableImage: UIViewRepresentable {
    let name: String

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 6
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        let image = UIImageView(image: UIImage(named: name))
        image.contentMode = .scaleAspectFit
        scroll.addSubview(image)
        context.coordinator.image = image
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        tap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(tap)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        DispatchQueue.main.async { context.coordinator.fit(scroll) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var image: UIImageView?
        private var size: CGSize = .zero

        /// The whole image fits the screen at zoom 1 (again whenever the view's size changes).
        func fit(_ scroll: UIScrollView) {
            guard let image, let img = image.image, scroll.bounds.size != size, scroll.bounds.width > 0 else { return }
            size = scroll.bounds.size
            scroll.zoomScale = 1
            let k = min(size.width / img.size.width, size.height / img.size.height)
            image.frame = CGRect(x: 0, y: 0, width: img.size.width * k, height: img.size.height * k)
            scroll.contentSize = image.frame.size
            centre(scroll)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { image }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { centre(scrollView) }

        /// Smaller than the screen: keep it in the middle rather than the top-left corner.
        private func centre(_ s: UIScrollView) {
            let dx = max(0, (s.bounds.width - s.contentSize.width) / 2), dy = max(0, (s.bounds.height - s.contentSize.height) / 2)
            s.contentInset = UIEdgeInsets(top: dy, left: dx, bottom: dy, right: dx)
        }

        @objc func doubleTap(_ g: UITapGestureRecognizer) {
            guard let s = g.view as? UIScrollView, let image else { return }
            if s.zoomScale > 1.01 { s.setZoomScale(1, animated: true); return }
            let p = g.location(in: image), w = s.bounds.width / 3, h = s.bounds.height / 3
            s.zoom(to: CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h), animated: true)
        }
    }
}
#endif
