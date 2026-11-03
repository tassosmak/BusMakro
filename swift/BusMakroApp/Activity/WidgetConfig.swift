import AppIntents
import BusMakroKit
import Foundation

/// Edit Widget on the Next Buses widget: your favourite stops (as before), any one stop, or a line's
/// timetable on a chosen day. Shared by the app and the widget extension.
struct NextBusesConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Next Buses"
    static let description = IntentDescription("Your favourite stops, one stop, or a line's timetable.")

    @Parameter(title: "Show", default: .favourites) var show: WidgetShow
    @Parameter(title: "Stop") var stop: WidgetStop?
    @Parameter(title: "Line") var line: WidgetLine?
    @Parameter(title: "Day", default: .today) var day: WidgetDay

    static var parameterSummary: some ParameterSummary {
        When(\NextBusesConfig.$show, .equalTo, .stop) {
            Summary("Show \(\.$show) \(\.$stop)")
        } otherwise: {
            When(\NextBusesConfig.$show, .equalTo, .timetable) {
                Summary("Show \(\.$show) of \(\.$line) on \(\.$day)")
            } otherwise: {
                Summary("Show \(\.$show)")
            }
        }
    }
}

enum WidgetShow: String, AppEnum {
    case favourites, stop, timetable
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Show"
    static let caseDisplayRepresentations: [WidgetShow: DisplayRepresentation] = [
        .favourites: "Favourite Stops", .stop: "One Stop", .timetable: "Line Timetable",
    ]
}

/// Today, or a weekday (1 Monday ... 7 Sunday, as OASA's schedule days).
enum WidgetDay: Int, AppEnum {
    case today = 0, monday, tuesday, wednesday, thursday, friday, saturday, sunday
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Day"
    static let caseDisplayRepresentations: [WidgetDay: DisplayRepresentation] = [
        .today: "Today", .monday: "Monday", .tuesday: "Tuesday", .wednesday: "Wednesday",
        .thursday: "Thursday", .friday: "Friday", .saturday: "Saturday", .sunday: "Sunday",
    ]

    static var weekdayToday: Int {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = OASAClient.athens
        return (cal.component(.weekday, from: Date()) + 5) % 7 + 1
    }
    var weekday: Int { self == .today ? Self.weekdayToday : rawValue }
    var isToday: Bool { weekday == Self.weekdayToday }
}

struct WidgetStop: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Bus Stop"
    static let defaultQuery = WidgetStopQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)", subtitle: "Stop \(id)") }
}

struct WidgetStopQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetStop] {
        let favs = WidgetFavourites.load()
        return identifiers.map { id in WidgetStop(id: id, name: favs.first { $0.id == id }?.title ?? String(localized: "Stop \(id)")) }
    }

    /// Your favourites; typing a stop code finds any stop.
    func entities(matching string: String) async throws -> [WidgetStop] {
        let q = string.trimmingCharacters(in: .whitespaces)
        let favs = try await suggestedEntities().filter { $0.name.localizedCaseInsensitiveContains(q) || $0.id == q }
        if favs.isEmpty, !q.isEmpty, q.allSatisfy(\.isNumber) { return [WidgetStop(id: q, name: String(localized: "Stop \(q)"))] }
        return favs
    }

    func suggestedEntities() async throws -> [WidgetStop] {
        WidgetFavourites.load().map { WidgetStop(id: $0.id, name: $0.title) }
    }
}

struct WidgetLine: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Line"
    static let defaultQuery = WidgetLineQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)", subtitle: "\(name)") }
}

struct WidgetLineQuery: EntityStringQuery {
    private func all() async -> [WidgetLine] {
        ((try? await OASAClient().lineList()) ?? []).map { WidgetLine(id: $0.id, name: $0.name) }
    }

    func entities(for identifiers: [String]) async throws -> [WidgetLine] {
        identifiers.map { WidgetLine(id: $0, name: "") }
    }

    func entities(matching string: String) async throws -> [WidgetLine] {
        let k = Translit.lineKey(string)
        return await all().filter { Translit.lineKey($0.id).hasPrefix(k) || $0.name.localizedCaseInsensitiveContains(string) }
    }

    func suggestedEntities() async throws -> [WidgetLine] { await all() }
}

/// A line's departures from each end on a weekday, from OASA's timetables.
enum WidgetTimetable {
    struct Direction: Hashable { let name: String; let times: [Date] }

    static func load(line: String, weekday: Int) async -> [Direction] {
        let oasa = OASAClient()
        guard let variants = (try? await oasa.lineCodes())?[line], let first = variants.first else { return [] }
        let master = (try? await oasa.masterCodes())?[line]
        let days = (try? await oasa.scheduleDays(code: first.code)) ?? []
        guard let master, let kind = OASAClient.day(for: weekday, in: days)?.code,
              let d = try? await oasa.schedule(master: master, dayKind: kind, code: first.code) else { return [] }
        // the variant's name is "START - END": going leaves START, coming back leaves END
        let ends = first.name.components(separatedBy: " - ")
        return [Direction(name: ends.first ?? first.name, times: d.go), Direction(name: ends.count > 1 ? ends[1] : "", times: d.come)]
            .filter { !$0.times.isEmpty }
    }
}
