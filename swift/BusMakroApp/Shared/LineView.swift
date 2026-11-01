import BusMakroKit
import SwiftUI

/// The line view's panel content: Arrivals (buses heading to your stop) and Route (the stops in
/// order, with the buses between them), like the Mac app's line tabs.
struct LineContent: View {
    @Bindable var model: Model

    var body: some View {
        Picker("", selection: $model.lineTab) {
            Text("Arrivals").tag(Model.LineTab.arrivals)
            Text("Route").tag(Model.LineTab.route)
        }
        .pickerStyle(.segmented).labelsHidden()
        if model.lineDetail == nil {
            Text("Loading the line…").font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 20)
                .frame(maxWidth: .infinity)
        } else if model.lineTab == .arrivals {
            arrivals
        } else {
            route
        }
    }

    private var arrivals: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("APPROACHING BUSES").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 6) {
                    let rows = model.approaching
                    if rows.isEmpty {
                        Text(model.lineStop == nil ? "Choose a stop to see approaching buses." : "No bus is heading to this stop right now.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 20)
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, a in
                        ArrivalCard(item: a).appearing(i)
                    }
                }
            }
        }
    }

    private var route: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let d = model.lineDetail, let vid = model.variantID, let v = d.variants[vid] {
                        ForEach(Array(v.stops.enumerated()), id: \.offset) { i, sid in
                            let buses = model.vehicles.filter { $0.variant == vid && $0.nextStopID == sid }
                            ForEach(buses) { b in RouteBusRow(id: b.id) }
                            RouteStopRow(name: d.stops[sid]?.name ?? sid, id: sid, selected: sid == model.lineStop,
                                         first: i == 0, last: i == v.stops.count - 1)
                                .id(sid)
                                .onTapGesture { model.lineStop = sid; Task { await model.refreshLine(currentLine) } }
                        }
                    }
                }
            }
            .onAppear { if let s = model.lineStop { proxy.scrollTo(s, anchor: .center) } }
        }
    }

    private var currentLine: String {
        if case .line(let id, _) = model.screen { return id }
        return ""
    }
}

/// An approaching bus: time (rolling), stops away, bus number and trip, delay.
struct ArrivalCard: View {
    let item: Approaching

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(time).font(Style.rounded(20)).contentTransition(.numericText(countsDown: true))
                Text(item.stopsAway == 0 ? "next stop" : item.stopsAway == 1 ? "1 stop away" : "\(item.stopsAway) stops away")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(width: 112, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Bus \(item.vehicle.id)").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(delay.0).font(.system(size: 12, weight: .semibold)).foregroundStyle(delay.1)
                }
                Text(item.vehicle.tripLabel ?? "Trip unavailable").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 72)
        .card()
        .background(item.seconds < 90 ? Color.green.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: Style.cardRadius))
    }

    private var time: String {
        item.seconds < 20 ? "Due" : "\(Int(item.seconds) / 60) min" + (item.official ? "" : " ~")
    }

    private var delay: (String, Color) {
        guard let d = item.vehicle.delaySeconds else { return ("", .secondary) }
        if abs(d) < 60 { return ("On time", .green) }
        return ("\(d > 0 ? "+" : "")\(d / 60) min", d > 0 ? .orange : .blue)
    }
}

/// A stop on the Route tab: a dot on the line's spine, orange and larger when selected.
struct RouteStopRow: View {
    let name: String, id: String
    let selected: Bool, first: Bool, last: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Rectangle().fill(.tertiary).frame(width: 2)
                    .padding(.top, first ? 23 : 0).padding(.bottom, last ? 23 : 0)
                Circle().fill(selected ? Color.orange : Color(red: 0.09, green: 0.47, blue: 1.0))
                    .frame(width: selected ? 16 : 10, height: selected ? 16 : 10)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
            .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13, weight: selected ? .semibold : .regular)).lineLimit(1)
                Text("Stop \(id)").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 6)
        .frame(height: 46)
        .background(selected ? Color.orange.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }
}

/// A bus between two stops on the Route tab.
struct RouteBusRow: View {
    let id: String
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Rectangle().fill(.tertiary).frame(width: 2)
                Image(systemName: "bus.fill").font(.system(size: 10)).foregroundStyle(.white)
                    .frame(width: 22, height: 22).background(.green, in: Circle())
            }
            .frame(width: 22)
            Text("Bus \(id)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.green)
            Spacer()
        }
        .padding(.horizontal, 6)
        .frame(height: 34)
    }
}
