import SwiftUI

/// The left side menu (the ☰ in the search bar): app info with the logo on top, then Metro Map and
/// Settings. Slides in from the left over a dimmed map; tap outside or swipe left to close.
struct SideMenu: View {
    @Binding var open: Bool
    var onSettings: () -> Void
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
                        Text("BusMakro").font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("Athens buses, live").font(.system(size: 13)).foregroundStyle(.secondary)
                        Text(version).font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 70).padding(.bottom, 26)
                Divider()
                VStack(spacing: 4) {
                    row("tram.fill", "Metro Map", external: true) { close(); openURL(URL(string: "https://www.stasy.gr")!) }
                    row("gearshape.fill", "Settings") { close(); onSettings() }
                }
                .padding(.top, 14)
                Spacer()
                Text("Data: OASA · athens-transit-rt. Unofficial app, not affiliated with OASA or STASY.")
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

    private func row(_ symbol: String, _ title: LocalizedStringKey, external: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(.tint).frame(width: 28)
                Text(title).font(.system(size: 16, weight: .medium))
                Spacer()
                Image(systemName: external ? "arrow.up.right" : "chevron.right").font(.system(size: 13)).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12).padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
