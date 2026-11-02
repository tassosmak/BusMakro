import SwiftUI

/// The floating search capsule with round buttons beside it. While you search, the capsule grows
/// over the buttons; cleared, it gives them back (layout_bar in core.py).
struct TopBar: View {
    @Binding var text: String
    @Binding var searching: Bool
    var refreshing = false
    var onRefresh: () -> Void
    var onMenu: () -> Void = {}
    @FocusState private var focused: Bool
    /// Searching: set when the field gets focus, cleared only by ✕ (or emptying it unfocused). Tapping ✕
    /// takes the focus first, so a state tied to focus removed the button before its tap landed.

    private var expanded: Bool { searching || !text.isEmpty }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                // ☰ opens the side menu (where the magnifier was)
                Button(action: onMenu) {
                    Image(systemName: "line.3.horizontal").font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary).frame(width: 28, height: Style.barHeight).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Menu")
                TextField("Search stops or lines", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
                    .onSubmit { focused = false }
                    .onChange(of: focused) { if focused { searching = true } else if text.isEmpty { searching = false } }
                    .onChange(of: searching) { focused = searching }  // a result was chosen: close the keyboard; a Search link: open it
            }
            .padding(.leading, 8).padding(.trailing, 14)
            .frame(height: Style.barHeight)
            .glass(Capsule())
            if expanded {
                // ✕ ends the search: a full round button beside the field (a small ✕ inside the field
                // lost its taps to the text field)
                RoundButton(symbol: "xmark", help: "Close") { text = ""; focused = false; searching = false }
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
            } else {
                RoundButton(symbol: "arrow.clockwise", help: "Refresh", spinning: refreshing, action: onRefresh)
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
