import SwiftUI

/// The left side menu (the ☰ in the search bar): app info with the logo on top, then Metro Map and
/// Settings. Slides in from the left over a dimmed map; tap outside or swipe left to close.
struct SideMenu: View {
    @Binding var open: Bool
    var onMetroMap: () -> Void
    var onSettings: () -> Void
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
                        Text("BusMakro").font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("Athens buses, live").font(.system(size: 13)).foregroundStyle(.secondary)
                        Text(version).font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 70).padding(.bottom, 26)
                Divider()
                VStack(spacing: 4) {
                    row("tram.fill", "Metro Map") { close(); onMetroMap() }
                    row("gearshape.fill", "Settings") { close(); onSettings() }
                }
                .padding(.top, 14)
                Spacer()
                Text("Data: OASA · athens-transit-rt. Unofficial app, not affiliated with OASA.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary).padding(.bottom, 30)
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

    private func row(_ symbol: String, _ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(.tint).frame(width: 28)
                Text(title).font(.system(size: 16, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(.tertiary)
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
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.36, dampingFraction: 1)) {
                            if scale > 1 { reset() } else { scale = 2.5; baseScale = 2.5 }
                        }
                    }
            }
            .background(Color(white: 0.93))
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
