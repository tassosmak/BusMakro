import AppIntents
import BusMakroKit
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

struct BusMakroShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: NextBusesIntent(), phrases: [
            "Next buses in \(.applicationName)",
            "Next buses at \(\.$stop) in \(.applicationName)",
            "When is my bus in \(.applicationName)",
        ], shortTitle: "Next Buses", systemImageName: "bus.fill")
        AppShortcut(intent: OpenStopIntent(), phrases: [
            "Open \(\.$stop) in \(.applicationName)",
            "Show my stop in \(.applicationName)",
        ], shortTitle: "Open Stop", systemImageName: "mappin.circle.fill")
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
