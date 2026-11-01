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
            if !model.online || model.serviceDown { offline }
            // fades out as the panel nears the slim strip (the strip shows just the handle and the menu)
            // fades with the panel's height, so it follows the drag and the snap exactly
            content.opacity(Double(min(1, max(0, (height - 90) / 70))))
        }
        .padding(.horizontal, Style.gap)
        .padding(.bottom, 16)  // clear of the rounded bottom corners and the home indicator
        .frame(height: height, alignment: .top)
        .frame(maxWidth: 480)
        // what doesn't fit stays inside the panel (dragged small, the tabs and list were drawn below it)
        .clipShape(Style.panelShape)
        .panelGlass(Style.panelShape)
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
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                        height = stops.min { abs($0 - height) < abs($1 - height) }!
                    }
                })
    }

    /// No connection, or the bus service didn't answer: say so; it retries by itself, or tap.
    private var offline: some View {
        Button { Task { await model.retry() } } label: {
            HStack(spacing: 10) {
                Image(systemName: model.online ? "exclamationmark.icloud" : "wifi.slash").foregroundStyle(.orange)
                Text(model.online ? "Couldn't reach the bus service. Tap to try again."
                                  : "No internet connection. Retrying when you're back online.")
                    .font(.system(size: 12, weight: .semibold)).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: Style.cardRadius))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var header: some View {
        HStack(spacing: 8) {
            if case .stop = model.screen {
                Button { withAnimation { model.screen = .home } } label: { Label("Back", systemImage: "chevron.left") }
            }
            if case .line = model.screen {
                Button { withAnimation { model.closeLine() } } label: { Label("Back", systemImage: "chevron.left") }
            }
            Menu {
                ForEach(model.lines) { l in
                    Button("\(l.id) — \(l.shown)") { withAnimation { model.openLine(l.id, at: nil) } }
                }
            } label: {
                Text(menuTitle).font(.system(size: 12)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
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

    private var menuTitle: String {
        if case .line(let id, _) = model.screen {
            return "\(id) — " + (model.lines.first { $0.id == id }?.shown ?? "")
        }
        return String(localized: "Browse a line…")
    }

    @ViewBuilder private var content: some View {
        if !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            results
        } else {
            screenContent
        }
    }

    /// Search results: lines, then stops (with the lines that serve them), as the Mac app.
    private var results: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                let lines = model.lineResults, stops = model.stopResults
                if !lines.isEmpty { sectionTitle("LINES") }
                ForEach(Array(lines.enumerated()), id: \.element.id) { i, l in
                    Button { model.searchText = ""; withAnimation { model.openLine(l.id, at: nil) } } label: { LineRow(line: l) }
                        .buttonStyle(.plain).appearing(i)
                }
                if model.stopIndex == nil {
                    Text("Preparing stop search…").font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 12)
                } else if !stops.isEmpty {
                    sectionTitle("STOPS")
                }
                ForEach(Array(stops.enumerated()), id: \.element.stop.id) { i, r in
                    Button { model.searchText = ""; model.open(r.stop) } label: {
                        StopCard(stop: r.stop, metres: model.distance(to: r.stop),
                                 subtitle: String(localized: "Lines \(r.lines.prefix(8).joined(separator: ", "))"))
                    }
                    .buttonStyle(.plain).appearing(lines.count + i)
                }
                if lines.isEmpty && stops.isEmpty && model.stopIndex != nil {
                    Text("No results for \"\(model.searchText)\"").font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.top, 20)
                }
            }
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 4)
    }

    @ViewBuilder private var screenContent: some View {
        switch model.screen {
        case .home:
            Picker("", selection: $model.homeTab) {
                Text("Nearby Stops").tag(Model.HomeTab.nearby)
                Text("Favourites").tag(Model.HomeTab.favourites)
            }
            .pickerStyle(.segmented).labelsHidden()
            list(model.homeTab == .nearby ? model.stops : model.favourites, empty: model.homeTab == .nearby
                 ? String(localized: "Finding stops near you…") : String(localized: "No favourite stops yet. Tap ☆ on a stop to add it."))
        case .line:
            LineContent(model: model)
        case .stop(let stop):
            Text(String(localized: "\(stop.title) · Stop \(stop.id)").uppercased())
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.networkAlerts.prefix(2)) { AlertCard(alert: $0) }
                    ForEach(model.alerts(for: (model.stopLines ?? []).map(\.line))) { AlertCard(alert: $0) }
                    if let lines = model.stopLines, lines.isEmpty {
                        Text(model.error == nil ? "No lines stop here." : "Couldn't reach the bus service. Tap ↻ to try again.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 20)
                    } else if let lines = model.stopLines {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { i, line in
                            Button { withAnimation { model.openLine(line.line, at: stop) } } label: { LineCard(line: line) }
                                .buttonStyle(.plain)
                                .appearing(i)
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
                ForEach(model.networkAlerts.prefix(2)) { AlertCard(alert: $0) }
                if stops.isEmpty {
                    Text(empty).font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 20)
                }
                ForEach(Array(stops.enumerated()), id: \.element.id) { i, stop in
                    Button { model.open(stop) } label: {
                        StopCard(stop: stop, metres: model.distance(to: stop), closest: i == 0 && (model.distance(to: stop) ?? .infinity) < 500,  // only when the list is around you
                                 subtitle: model.homeTab == .favourites ? favouriteSubtitle(model.favLines[stop.id]) : nil)
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
