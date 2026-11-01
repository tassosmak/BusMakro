import SwiftUI

/// The floating search capsule with round buttons beside it. While you search, the capsule grows
/// over the buttons; cleared, it gives them back (layout_bar in core.py).
struct TopBar: View {
    @Binding var text: String
    var onRefresh: () -> Void
    var onSettings: () -> Void = {}
    @FocusState private var focused: Bool

    private var expanded: Bool { focused || !text.isEmpty }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search stops or lines", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
                    .onSubmit { focused = false }
                if expanded {  // ✕ ends the search (clears it and closes the keyboard)
                    Button { text = ""; focused = false } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: Style.barHeight)
            .glass(Capsule())
            if !expanded {
                RoundButton(symbol: "arrow.clockwise", help: "Refresh", action: onRefresh)
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
                RoundButton(symbol: "gearshape", help: "Settings", action: onSettings)
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .animation(.easeInOut(duration: 0.28), value: expanded)
    }
}

/// Recent stops as small glass chips under the search bar.
struct RecentChips: View {
    let stops: [String]
    let onTap: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(stops.enumerated()), id: \.offset) { i, name in
                    Button { onTap(i) } label: {
                        Label(name, systemImage: "clock.arrow.circlepath")
                            .font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            .padding(.horizontal, 10).frame(height: Style.chipHeight)
                    }
                    .buttonStyle(.plain)
                    .glass(Capsule())
                }
            }
        }
    }
}
