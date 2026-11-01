import BusMakroKit
import SwiftUI

/// Search results in a glass card that drops down from the search field: lines, then stops (with the
/// lines that serve them). Choosing one closes the search and opens it in the bottom panel.
struct SearchResults: View {
    @Bindable var model: Model

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                let lines = model.lineResults, stops = model.stopResults
                if !lines.isEmpty { sectionTitle("LINES") }
                ForEach(Array(lines.enumerated()), id: \.element.id) { i, l in
                    Button { close(); withAnimation { model.openLine(l.id, at: nil) } } label: { LineRow(line: l) }
                        .buttonStyle(.plain).appearing(i)
                }
                let stations = model.stationResults
                if !stations.isEmpty { sectionTitle("METRO AND TRAM") }
                ForEach(Array(stations.enumerated()), id: \.element.id) { i, r in
                    Button { close(); withAnimation { model.openStation(r.id) } } label: {
                        HStack(spacing: 10) {
                            StationPin(station: r.station)
                            Text(r.station.shown).font(.system(size: 13, weight: .semibold))
                            Spacer()
                            ForEach(r.station.lines, id: \.self) { RailBadge(line: $0, small: true) }
                        }
                        .padding(10)
                        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: Style.cardRadius))
                    }
                    .buttonStyle(.plain).appearing(lines.count + i)
                }
                if model.stopIndex == nil {
                    Text("Preparing stop search…").font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 12)
                } else if !stops.isEmpty {
                    sectionTitle("STOPS")
                }
                ForEach(Array(stops.enumerated()), id: \.element.stop.id) { i, r in
                    Button { close(); model.open(r.stop) } label: {
                        StopCard(stop: r.stop, metres: model.distance(to: r.stop),
                                 subtitle: String(localized: "Lines \(r.lines.prefix(8).joined(separator: ", "))"))
                    }
                    .buttonStyle(.plain).appearing(lines.count + i)
                }
                if lines.isEmpty && stops.isEmpty && stations.isEmpty && model.stopIndex != nil {
                    Text("No results for \"\(model.searchText)\"").font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 20)
                }
            }
            .padding(Style.gap)
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(maxHeight: 420)
        .fixedSize(horizontal: false, vertical: true)
        .glass(RoundedRectangle(cornerRadius: Style.sheetRadius, style: .continuous))
    }

    /// Closing the search: field cleared, keyboard down, the panel comes back with the choice.
    private func close() {
        model.searchText = ""
        model.searchActive = false
    }

    private func sectionTitle(_ t: LocalizedStringKey) -> some View {
        Text(t).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 4)
    }
}
