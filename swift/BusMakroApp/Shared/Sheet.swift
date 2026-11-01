import BusMakroKit
import SwiftUI

/// The bottom panel: handle, "Browse a line…" menu, then the home tabs and stop cards, or a stop's
/// lines. One inset (Style.gap) for everything, as in the Mac app.
struct Sheet: View {
    @Bindable var model: Model
    @Binding var height: CGFloat
    let range: ClosedRange<CGFloat>
    @State private var dragStart: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            handle
            header
            content
        }
        .padding(.horizontal, Style.gap)
        .frame(height: height, alignment: .top)
        .frame(maxWidth: 480)
        .glass(RoundedRectangle(cornerRadius: Style.sheetRadius))
    }

    // Drag the handle to resize; it snaps to the nearest of strip / normal / full.
    private var handle: some View {
        Capsule().fill(.tertiary).frame(width: 40, height: 5)
            .frame(maxWidth: .infinity).padding(.top, Style.gap)
            .contentShape(Rectangle())
            .gesture(DragGesture()
                .onChanged { g in
                    let start = dragStart ?? height
                    dragStart = start
                    height = min(range.upperBound, max(range.lowerBound, start - g.translation.height))
                }
                .onEnded { _ in
                    dragStart = nil
                    let stops = [range.lowerBound, (range.lowerBound + range.upperBound) / 2, range.upperBound]
                    withAnimation(.spring(duration: 0.3)) {
                        height = stops.min { abs($0 - height) < abs($1 - height) }!
                    }
                })
    }

    @ViewBuilder private var header: some View {
        HStack(spacing: 8) {
            if case .stop = model.screen {
                Button { withAnimation { model.screen = .home } } label: { Label("Back", systemImage: "chevron.left") }
            }
            Menu {
                ForEach(model.lines) { Text("\($0.id) — \($0.nameEnglish ?? $0.name)") }
            } label: {
                Text("Browse a line…").font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)  // works on both iPhone and Mac (.borderlessButton is Mac-only)
            .padding(.horizontal, 10)
            .frame(height: Style.lineMenuHeight)
            .background(.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: Style.sheetRadius - Style.gap))
            if case .stop(let s) = model.screen {
                Button { model.toggleFavourite(s) } label: {
                    Image(systemName: model.isFavourite(s) ? "star.fill" : "star")
                        .foregroundStyle(model.isFavourite(s) ? .yellow : .secondary)
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.screen {
        case .home:
            Picker("", selection: $model.homeTab) {
                Text("Nearby Stops").tag(Model.HomeTab.nearby)
                Text("Favourites").tag(Model.HomeTab.favourites)
            }
            .pickerStyle(.segmented).labelsHidden()
            list(model.homeTab == .nearby ? model.stops : model.favourites, empty: model.homeTab == .nearby
                 ? "Finding stops near you…" : "No favourite stops yet. Tap ☆ on a stop to add it.")
        case .stop(let stop):
            Text("\(stop.title.uppercased()) · STOP \(stop.id)")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 6) {
                    if let lines = model.stopLines {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { i, line in
                            LineCard(line: line).appearing(i)
                        }
                    } else {
                        Text("Loading the lines at this stop…").font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 20)
                    }
                }
            }
        }
    }

    private func list(_ stops: [Stop], empty: String) -> some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if stops.isEmpty {
                    Text(empty).font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 20)
                }
                ForEach(Array(stops.enumerated()), id: \.element.id) { i, stop in
                    Button { Task { await model.open(stop) } } label: {
                        StopCard(stop: stop, metres: model.distance(to: stop), closest: i == 0 && model.userLocation != nil)
                    }
                    .buttonStyle(.plain)
                    .appearing(i)
                }
            }
        }
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
                withAnimation(.easeOut(duration: 0.38).delay(Double(min(index, 12)) * 0.035)) { shown = true }
            }
    }
}

extension View {
    func appearing(_ index: Int) -> some View { modifier(Appearing(index: index)) }
}
