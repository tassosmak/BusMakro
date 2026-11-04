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
    @State private var picking: SavedPlace?
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    // iPhone apps follow iOS's own per-app language setting
                    Button("Language") { openSettings() }
                    Button("Notifications") { openSettings() }
                }
                Section("Recent Stops") {
                    Toggle("Show recent stops under the search bar", isOn: $showRecents)
                    Button("Clear Recent Stops", role: .destructive) { model.clearRecents() }
                        .disabled(model.recents.isEmpty)
                }
                Section("Trips") {
                    ForEach(SavedPlace.allCases) { k in
                        Button { picking = k } label: {
                            LabeledContent(k.title, value: model[place: k]?.name ?? String(localized: "Not set"))
                        }
                        .foregroundStyle(.primary)
                        .swipeActions { if model[place: k] != nil { Button("Remove", role: .destructive) { model[place: k] = nil } } }
                        .contextMenu { if model[place: k] != nil { Button("Remove", role: .destructive) { model[place: k] = nil } } }
                    }
                }
                Section("Map") {
                    Picker("Map Style", selection: $mapStyle) {
                        Text("Match System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    Toggle("3D Buildings", isOn: $map3D)
                    ColorPicker("Favourite Stops", selection: Binding(get: { Color(hex: favColor) }, set: { favColor = $0.hex }),
                                supportsOpacity: false)
                }
                Section("Show on Map") {
                    Toggle("Bus Stops", isOn: $showStops)
                    Toggle("Live Buses", isOn: $showBuses)
                    Toggle("Metro", isOn: $showMetro)
                    Toggle("Tram", isOn: $showTram)
                }
                Section {
                    Button("Show Welcome") { dismiss(); model.showWelcome = true }
                }
                Section {
                    Link("Privacy Policy", destination: URL(string: "https://tassosmak.github.io/BusMakro-Swift/privacy.html")!)
                    Link("Website", destination: URL(string: "https://tassosmak.github.io/BusMakro-Swift/")!)
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                } header: {
                    Text("About")
                } footer: {
                    Text("Arrivals, routes and timetables from OASA's telematics; metro and tram timetables from STASY (data.gov.gr); live bus positions via the open-source athens-transit-rt project. BusMakro is an independent app, not affiliated with OASA or STASY.")
                }
            }
            .sheet(item: $picking) { k in
                NavigationStack {
                    PlaceSearch(model: model, allowHere: false) { choice in
                        if case .place(let p) = choice { model[place: k] = p }
                        picking = nil
                    }
                    .navigationTitle(k.title)
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { picking = nil } } }
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
