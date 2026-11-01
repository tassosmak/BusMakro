#if DEBUG
import BusMakroKit
import CoreLocation
import SwiftUI
import UserNotifications

/// Developer tools, in the ☰ menu of Debug builds only (the ones Xcode installs on your phone).
/// Release builds, the App Store ones, leave this whole file out. Not translated on purpose.
struct DebugView: View {
    @Bindable var model: Model
    @Environment(\.dismiss) private var dismiss
    @State private var sent = false

    private static let syntagma = CLLocationCoordinate2D(latitude: 37.9755, longitude: 23.7348)

    var body: some View {
        NavigationStack {
            Form {
                Section("State") {
                    info("Build", "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                    info("Screen", "\(model.screen)")
                    info("Online", model.online ? "yes" : "no")
                    info("Service down", model.serviceDown ? "yes" : "no")
                    info("Location", model.userLocation.map { String(format: "%.5f, %.5f", $0.latitude, $0.longitude) } ?? "none")
                    info("Nearby stops", "\(model.stops.count)")
                    info("Lines", "\(model.lines.count)")
                    info("Stop index", model.stopIndex == nil ? "not loaded" : "loaded")
                    info("Live buses", "\(model.vehicles.count) on line · \(model.stopBuses.count) at stop")
                    info("Alerts", "\(model.alerts.count)")
                    info("Bus alerts set", "\(model.watches.count)")
                    info("Favourites / recents", "\(model.favourites.count) / \(model.recents.count)")
                }
                Section("Simulate") {
                    Button("Pretend I'm at Syntagma") {
                        model.userLocation = Self.syntagma
                        Task { await model.loadStops(near: Self.syntagma, force: true) }
                        dismiss()
                    }
                    Toggle("Offline", isOn: $model.online.inverted)
                    Toggle("Service down banner", isOn: $model.serviceDown)
                    Button(sent ? "Sent — lock the phone to see it" : "Test notification in 5 s") { testNotification() }
                }
                Section("Reset") {
                    Button("Show the welcome screen") { dismiss(); model.showWelcome = true }
                    Button("Reload everything") { Task { await model.retry() }; dismiss() }
                    Button("Clear favourites", role: .destructive) {
                        model.favourites = []; Model.saveStops([], "favorites")
                    }
                    Button("Clear recent stops", role: .destructive) { model.clearRecents() }
                    Button("Reset all settings", role: .destructive) {
                        if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
                    }
                }
            }
            .navigationTitle("Debug")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func info(_ name: String, _ value: String) -> some View {
        LabeledContent(name) { Text(value).font(.system(.footnote, design: .monospaced)).textSelection(.enabled) }
    }

    private func testNotification() {
        let content = UNMutableNotificationContent()
        content.title = "BusMakro test"
        content.body = "Notifications work."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "debug-test", content: content, trigger: trigger))
        sent = true
    }
}

private extension Bool {
    var inverted: Bool { get { !self } set { self = !newValue } }
}
#endif
