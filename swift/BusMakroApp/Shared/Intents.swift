import AppIntents
import BusMakroKit
import CoreLocation
import CoreSpotlight
import Foundation

/// Siri, Shortcuts, Spotlight and the Action Button: "Next buses in BusMakro" answers without
/// opening the app; "Open stop" and "Open line" jump straight in.

struct StopEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Bus Stop"
    static let defaultQuery = StopQuery()
    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "Stop \(id)", image: .init(systemName: "mappin.circle.fill"))
    }

    init(_ s: Stop) { id = s.id; name = s.title }
    init(id: String, name: String) { self.id = id; self.name = name }
}

struct StopQuery: EntityStringQuery {
    /// Favourites first, then recent stops (what Siri offers when you don't name one).
    @MainActor private static var saved: [StopEntity] {
        var seen = Set<String>()
        return (Model.loadStops("favorites") + Model.loadStops("recents"))
            .filter { seen.insert($0.id).inserted }.map(StopEntity.init)
    }

    func entities(for identifiers: [String]) async throws -> [StopEntity] {
        let saved = await Self.saved
        let index = StopIndex.cached()
        return identifiers.compactMap { id in
            saved.first { $0.id == id } ?? index?.stops[id].map { StopEntity(id: id, name: $0.name) }
        }
    }

    func entities(matching string: String) async throws -> [StopEntity] {
        let q = Translit.normalize(string)
        let saved = await Self.saved.filter { Translit.normalize($0.name).contains(q) || $0.id == string }
        let found = StopIndex.cached()?.search(string, limit: 15).map { StopEntity(id: $0.id, name: $0.entry.name) } ?? []
        return saved + found.filter { f in !saved.contains { $0.id == f.id } }
    }

    func suggestedEntities() async throws -> [StopEntity] { await Self.saved }
}

/// "When are the next buses at Syntagma?": the next live arrivals, spoken and shown.
struct NextBusesIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Buses at a Stop"
    static let description = IntentDescription("The next live buses at a stop, from OASA.")

    @Parameter(title: "Stop") var stop: StopEntity

    static var parameterSummary: some ParameterSummary { Summary("Next buses at \(\.$stop)") }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let lines = try await OASAClient().stopLines(stopID: stop.id)
        let live = lines.filter { !$0.arrivalsMinutes.isEmpty }
            .flatMap { l in l.arrivalsMinutes.prefix(2).map { (l.line, $0) } }
            .sorted { $0.1 < $1.1 }.prefix(4)
        guard !live.isEmpty else {
            let none = String(localized: "No live buses at \(stop.name) right now.")
            return .result(value: none, dialog: IntentDialog(stringLiteral: none))
        }
        let parts = live.map { $0.1 == 0 ? String(localized: "\($0.0) now") : String(localized: "\($0.0) in \($0.1) min") }
        let text = String(localized: "\(stop.name): ") + parts.joined(separator: ", ")
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

/// A bus line, for "When is the 040 coming?" (from the saved stop index: no download).
struct LineEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Bus Line"
    static let defaultQuery = LineQuery()
    let id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)", image: .init(systemName: "bus.fill")) }
}

struct LineQuery: EntityStringQuery {
    private static var all: [String] { Array(Set(StopIndex.cached()?.stops.values.flatMap(\.lines) ?? [])).sorted() }
    func entities(for identifiers: [String]) async throws -> [LineEntity] { identifiers.map(LineEntity.init) }
    func entities(matching string: String) async throws -> [LineEntity] {
        let q = Translit.lineKey(string)
        return Self.all.filter { Translit.lineKey($0) == q }.map(LineEntity.init)
            + Self.all.filter { Translit.lineKey($0).hasPrefix(q) && Translit.lineKey($0) != q }.prefix(10).map(LineEntity.init)
    }
    /// Your favourite lines first.
    func suggestedEntities() async throws -> [LineEntity] {
        (UserDefaults.standard.stringArray(forKey: "favoriteLines") ?? []).map(LineEntity.init)
    }
}

/// "When is the 040 coming?": the line's next buses at your stop. Your stop is a favourite the line
/// serves, or else its stop nearest to where the phone last was.
struct WhenIsLineIntent: AppIntent {
    static let title: LocalizedStringResource = "When Is My Bus Coming"
    static let description = IntentDescription("The next live buses of a line at your favourite stop, or at its stop nearest you.")

    @Parameter(title: "Line") var line: LineEntity

    static var parameterSummary: some ParameterSummary { Summary("When is \(\.$line) coming") }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        guard let index = StopIndex.cached() else {
            let t = String(localized: "Open BusMakro once first, so it can learn the stops.")
            return .result(value: t, dialog: IntentDialog(stringLiteral: t))
        }
        let favs = await MainActor.run { Model.loadStops("favorites") }
        let here = CLLocationManager().location
        let served = index.stops.filter { $0.value.lines.contains(line.id) }
        let stop: (id: String, name: String)? =
            favs.first { served[$0.id] != nil }.map { ($0.id, $0.title) }
            ?? here.flatMap { loc in
                served.min { Geo.distance(loc.coordinate.latitude, loc.coordinate.longitude, $0.value.lat, $0.value.lon)
                           < Geo.distance(loc.coordinate.latitude, loc.coordinate.longitude, $1.value.lat, $1.value.lon) }
                    .map { ($0.key, $0.value.name) }
            }
        guard let stop else {
            let t = String(localized: "Star a stop the \(line.id) serves, or allow location, so BusMakro knows your stop.")
            return .result(value: t, dialog: IntentDialog(stringLiteral: t))
        }
        let name = Names.place(stop.name, "")
        let mins = (try? await OASAClient().stopLines(stopID: stop.id))?.first { $0.line == line.id }?.arrivalsMinutes ?? []
        let text: String
        if let m = mins.first {
            let first = m == 0 ? String(localized: "The \(line.id) is arriving at \(name) now")
                               : String(localized: "The \(line.id) comes to \(name) in \(m) min")
            text = mins.count > 1 ? first + String(localized: ", then in \(mins[1]) min.") : first + "."
        } else {
            text = String(localized: "No \(line.id) is on its way to \(name) right now.")
        }
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct OpenStopIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Stop"
    static let description = IntentDescription("Open a bus stop in BusMakro.")
    static let openAppWhenRun = true

    @Parameter(title: "Stop") var stop: StopEntity

    @MainActor func perform() async throws -> some IntentResult {
        Links.shared.pending = .stop(stop.id)
        return .result()
    }
}

struct OpenLineIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Line"
    static let description = IntentDescription("Open a bus line and its live buses in BusMakro.")
    static let openAppWhenRun = true

    @Parameter(title: "Line", description: "The line number, such as 040 or Α1") var line: String

    @MainActor func perform() async throws -> some IntentResult {
        Links.shared.pending = .line(line.uppercased().trimmingCharacters(in: .whitespaces))
        return .result()
    }
}

struct SearchIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Stops and Lines"
    static let openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        Links.shared.pending = .search
        return .result()
    }
}

struct TakeMeHomeIntent: AppIntent {
    static let title: LocalizedStringResource = "Take Me Home"
    static let description = IntentDescription("Plans the trip from where you are to your Home.")
    static let openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        Links.shared.pending = .home
        return .result()
    }
}

struct TakeMeToWorkIntent: AppIntent {
    static let title: LocalizedStringResource = "Take Me to Work"
    static let description = IntentDescription("Plans the trip from where you are to your Work.")
    static let openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        Links.shared.pending = .work
        return .result()
    }
}

struct BusMakroShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: NextBusesIntent(), phrases: [
            "Next buses in \(.applicationName)",
            "Next buses at \(\.$stop) in \(.applicationName)",
            "When is my bus in \(.applicationName)",
        ], shortTitle: "Next Buses", systemImageName: "bus.fill")
        AppShortcut(intent: WhenIsLineIntent(), phrases: [
            "When is the \(\.$line) coming in \(.applicationName)",
            "When is \(\.$line) in \(.applicationName)",
            "Where is my \(\.$line) in \(.applicationName)",
            "When is my bus coming in \(.applicationName)",
        ], shortTitle: "When Is My Bus", systemImageName: "clock.badge")
        AppShortcut(intent: OpenStopIntent(), phrases: [
            "Open \(\.$stop) in \(.applicationName)",
            "Show my stop in \(.applicationName)",
        ], shortTitle: "Open Stop", systemImageName: "mappin.circle.fill")
        AppShortcut(intent: TakeMeHomeIntent(), phrases: [
            "Take me home with \(.applicationName)",
            "Get me home with \(.applicationName)",
        ], shortTitle: "Take Me Home", systemImageName: "house.fill")
        AppShortcut(intent: TakeMeToWorkIntent(), phrases: [
            "Take me to work with \(.applicationName)",
            "Get me to work with \(.applicationName)",
        ], shortTitle: "Take Me to Work", systemImageName: "briefcase.fill")
        AppShortcut(intent: SearchIntent(), phrases: ["Search \(.applicationName)"],
                    shortTitle: "Search", systemImageName: "magnifyingglass")
    }
}

// MARK: Spotlight

/// Favourite and recent stops in Spotlight: typing a stop's name on the home screen finds it.
enum SpotlightStops {
    static func index(favourites: [Stop], recents: [Stop]) {
        var seen = Set<String>()
        let items = (favourites + recents).filter { seen.insert($0.id).inserted }.map { s in
            let attrs = CSSearchableItemAttributeSet(contentType: .content)
            attrs.title = s.title
            attrs.contentDescription = String(localized: "Bus stop \(s.id)") + (s.street.isEmpty ? "" : " · \(s.street)")
            attrs.keywords = [s.name, s.nameEnglish, s.id, "bus", "λεωφορείο", "στάση"].filter { !$0.isEmpty }
            return CSSearchableItem(uniqueIdentifier: "stop/\(s.id)", domainIdentifier: "stops", attributeSet: attrs)
        }
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: ["stops"]) { _ in index.indexSearchableItems(items) }
    }

    /// A tapped Spotlight result's link.
    static func link(_ activity: NSUserActivity) -> AppLink? {
        guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String, id.hasPrefix("stop/") else { return nil }
        return .stop(String(id.dropFirst(5)))
    }
}
