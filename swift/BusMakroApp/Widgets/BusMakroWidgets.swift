import ActivityKit
import SwiftUI
import WidgetKit

@main
struct BusMakroWidgets: WidgetBundle {
    var body: some Widget {
        BusLiveActivity()
        NextBusesWidget()
    }
}

/// The bus alert on the lock screen and in the Dynamic Island: line, stop, a live countdown and
/// how many stops the bus still has to go.
struct BusLiveActivity: Widget {
    private static let green = Color(red: 0.10, green: 0.53, blue: 0.33)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BusActivityAttributes.self) { ctx in
            LockScreenView(ctx: ctx)
                .activityBackgroundTint(nil)
                // a ride opens its line (your bus on the map); an alert opens the stop you're waiting at
                .widgetURL(URL(string: ctx.attributes.riding ? "busmakro://line/\(ctx.attributes.line)" : "busmakro://stop/\(ctx.attributes.stopID)"))
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LineBadge(line: ctx.attributes.line).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: ctx.state, stale: ctx.isStale).font(.system(size: 22, weight: .bold, design: .rounded))
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ctx.attributes.riding ? String(localized: "Get off at \(ctx.attributes.stopName)") : ctx.attributes.stopName).font(.headline).lineLimit(1)
                        StopsBar(state: ctx.state, alertAt: ctx.attributes.alertAt)
                    }
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Image(systemName: "bus.fill").foregroundStyle(Self.green)
                    Text(ctx.attributes.line).font(.system(size: 14, weight: .bold, design: .rounded))
                }
            } compactTrailing: {
                Countdown(state: ctx.state, stale: ctx.isStale).font(.system(size: 14, weight: .semibold, design: .rounded))
                    .frame(maxWidth: 64)
            } minimal: {
                Image(systemName: "bus.fill").foregroundStyle(Self.green)
            }
            .widgetURL(URL(string: ctx.attributes.riding ? "busmakro://line/\(ctx.attributes.line)" : "busmakro://stop/\(ctx.attributes.stopID)"))
        }
    }
}

private struct LockScreenView: View {
    let ctx: ActivityViewContext<BusActivityAttributes>
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                LineBadge(line: ctx.attributes.line)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ctx.attributes.riding ? String(localized: "Get off at \(ctx.attributes.stopName)") : ctx.attributes.stopName).font(.headline).lineLimit(1)
                    Text("Bus \(ctx.attributes.bus)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Countdown(state: ctx.state, stale: ctx.isStale).font(.system(size: 26, weight: .bold, design: .rounded))
            }
            StopsBar(state: ctx.state, alertAt: ctx.attributes.alertAt)
        }
        .padding(16)
        .accessibilityElement(children: .combine)
    }
}

/// "4 min" counting down by itself between updates, then "Now".
/// Minutes to the stop, short: "3'". Set by the app on each reading; if no fresh reading came for a
/// minute (iOS paused the app), the minutes would be stale, so it shows the arrival time ("17:42").
private struct Countdown: View {
    let state: BusActivityAttributes.ContentState
    var stale = false
    var body: some View {
        if state.arrived || state.arrival <= .now {
            Text("Now").foregroundStyle(.orange)
        } else if stale {
            Text(state.arrival, style: .time).monospacedDigit()
        } else {
            let m = max(1, Int((state.arrival.timeIntervalSinceNow / 60).rounded(.up)))
            Text("\(m)'").monospacedDigit()
                .accessibilityLabel(m == 1 ? Text("in 1 minute") : Text("in \(m) minutes"))  // not "4 apostrophe"
        }
    }
}

/// Dots for the stops still to go (up to 8), and the words.
private struct StopsBar: View {
    let state: BusActivityAttributes.ContentState
    let alertAt: Int
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<min(8, max(state.stopsAway, 1)), id: \.self) { i in
                    Circle().fill(i < alertAt ? Color.orange : Color.secondary.opacity(0.5)).frame(width: 7, height: 7)
                }
                Image(systemName: "mappin.circle.fill").foregroundStyle(.orange).font(.system(size: 13))
            }
            .accessibilityHidden(true)  // the dots say what the words next to them say
            Text(state.arrived || state.stopsAway == 0 ? String(localized: "Arriving")
                 : state.stopsAway == 1 ? String(localized: "1 stop away")
                 : String(localized: "\(state.stopsAway) stops away"))
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
    }
}

private struct LineBadge: View {
    let line: String
    var body: some View {
        Text(line).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
            .frame(minWidth: 46).frame(height: 28).padding(.horizontal, 4)
            .background(.blue, in: RoundedRectangle(cornerRadius: 8))
    }
}
