import SwiftUI
import UserNotifications

/// Settings, kept to a few choices as on the Mac: language, map style, recent stops, notifications.
struct SettingsView: View {
    @Bindable var model: Model
    @AppStorage("mapStyle") private var mapStyle = "system"
    @AppStorage("showRecents") private var showRecents = true
    @AppStorage("map3D") private var map3D = false
    @AppStorage("showStops") private var showStops = true
    @AppStorage("favColor") private var favColor = Style.favouriteColor
    @AppStorage("showBuses") private var showBuses = true
    @AppStorage("showMetro") private var showMetro = true
    @AppStorage("showTram") private var showTram = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    // iPhone apps follow iOS's own per-app language setting
                    Button("Language") { openSettings() }
                    Toggle("Show recent stops under the search bar", isOn: $showRecents)
                    Button("Clear Recent Stops", role: .destructive) { model.clearRecents() }
                        .disabled(model.recents.isEmpty)
                    Button("Notifications") { openSettings() }
                }
                Section("Map") {
                    Picker("Map Style", selection: $mapStyle) {
                        Text("Match System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    Toggle("3D Buildings", isOn: $map3D)
                    Toggle("Bus Stops", isOn: $showStops)
                    ColorPicker("Favourite Stops", selection: Binding(get: { Color(hex: favColor) }, set: { favColor = $0.hex }),
                                supportsOpacity: false)
                    Toggle("Live Buses", isOn: $showBuses)
                    Toggle("Metro", isOn: $showMetro)
                    Toggle("Tram", isOn: $showTram)
                }
                Section {
                    Button("Show Welcome") { dismiss(); model.showWelcome = true }
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func openSettings() {
        #if os(iOS)
        if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) }
        #else
        if let u = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { openURL(u) }
        #endif
    }
}
