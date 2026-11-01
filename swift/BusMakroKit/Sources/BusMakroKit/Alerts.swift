import Foundation

/// OASA's announcements (oasa.gr RSS) as service alerts, with the Mac app's rules (alerts.py):
/// line numbers are read after the word for line(s); strikes and whole-network notices have no lines;
/// a notice whose dates (in its title) have all passed is dropped.
public struct ServiceAlert: Identifiable, Hashable, Sendable {
    public var id: String { link }
    public let title: String
    public let link: String
    public let date: Date
    public let lines: Set<String>
    public let strike: Bool
}

public enum Alerts {
    static let feeds = ["https://www.oasa.gr/feed/", "https://www.oasa.gr/en/feed/"]
    static let maxAge: TimeInterval = 14 * 86400
    static let networkMaxAge: TimeInterval = 3 * 86400

    static func rx(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: [.caseInsensitive]) }
    static let after = rx(#"(γραμμ\w*|lines?)\s+(.*)"#)
    static let stopWord = rx(#"\s(λόγω|στον|στην|στο|στη|στις|από|για|due|on|in|from|at|during)\s"#)
    static let token = rx(#"[A-ZΑ-Ω]?\d{1,3}[A-ZΑ-Ω]?"#)
    static let strikeRx = rx(#"στάσ\w* εργασίας|απεργ\w*|strike|work stoppage"#)
    static let dayMonth = rx(#"(\d{1,2})(?:η|ης|st|nd|rd|th)?\s+([A-Za-zΑ-Ωα-ωάέήίόύώΐϊ]{3,})"#)
    static let monthDay = rx(#"([A-Za-z]{3,})\s+(\d{1,2})(?:\s*(?:&|and|-|και)\s*(\d{1,2}))?"#)
    static let numeric = rx(#"\b(\d{1,2})[/.](\d{1,2})(?:[/.](\d{2,4}))?\b"#)
    static let months: [(String, Int)] = [("ιαν", 1), ("jan", 1), ("φεβ", 2), ("feb", 2), ("μαρ", 3), ("mar", 3), ("απρ", 4), ("apr", 4),
        ("μαΐ", 5), ("μαι", 5), ("may", 5), ("ιουν", 6), ("jun", 6), ("ιουλ", 7), ("jul", 7), ("αυγ", 8), ("aug", 8),
        ("σεπ", 9), ("sep", 9), ("οκτ", 10), ("oct", 10), ("νοε", 11), ("nov", 11), ("δεκ", 12), ("dec", 12)]

    static func groups(_ r: NSRegularExpression, _ s: String) -> [[String?]] {
        r.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { m in
            (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: s).map { String(s[$0]) } }
        }
    }
    static func month(_ w: String) -> Int? { let w = w.lowercased(); return months.first { w.hasPrefix($0.0) }?.1 }

    /// Line ids named in a title (only ones in `known`).
    public static func lines(in title: String, known: Set<String>) -> Set<String> {
        guard let m = groups(after, title).first, let rest = m[2] else { return [] }
        let part = stopWord.firstMatch(in: " \(rest) ", range: NSRange(location: 0, length: (" \(rest) " as NSString).length))
            .map { (" \(rest) " as NSString).substring(to: $0.range.location) } ?? rest
        let latin: [Character: Character] = ["A": "Α", "B": "Β", "E": "Ε", "X": "Χ"]
        var found = Set<String>()
        for g in groups(token, part) {
            guard let tok = g[0] else { continue }
            let greek = String(tok.uppercased().map { latin[$0] ?? $0 })
            if let hit = [tok, greek, tok.uppercased()].first(where: known.contains) { found.insert(hit) }
        }
        return found
    }

    /// The days a notice is about, from its title (in the year after it was posted).
    public static func dates(in title: String, posted: Date) -> [Date] {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = OASAClient.athens
        var md: [(Int, Int)] = []
        for g in groups(dayMonth, title) { if let d = Int(g[1] ?? ""), let m = month(g[2] ?? "") { md.append((m, d)) } }
        for g in groups(monthDay, title) {
            if let m = month(g[1] ?? "") { for d in [g[2], g[3]].compactMap({ $0.flatMap(Int.init) }) { md.append((m, d)) } }
        }
        for g in groups(numeric, title) { if let d = Int(g[1] ?? ""), let m = Int(g[2] ?? ""), (1...12).contains(m) { md.append((m, d)) } }
        let year = cal.component(.year, from: posted)
        return md.compactMap { m, d in
            guard var day = cal.date(from: DateComponents(year: year, month: m, day: d)) else { return nil }
            if day < posted.addingTimeInterval(-60 * 86400) { day = cal.date(byAdding: .year, value: 1, to: day)! }
            return day
        }
    }

    /// Recent alerts naming known lines, plus strikes / whole-network notices, newest first.
    public static func fetch(known: Set<String>, now: Date = Date()) async -> [ServiceAlert] {
        var out: [ServiceAlert] = [], seen = Set<String>()
        var cal = Calendar(identifier: .gregorian); cal.timeZone = OASAClient.athens
        let today = cal.startOfDay(for: now)
        for url in feeds {
            var req = URLRequest(url: URL(string: url)!, timeoutInterval: 15)
            req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            guard let (data, _) = try? await URLSession.shared.data(for: req) else { continue }
            for item in RSS.items(data) where !seen.contains(item.link) {
                let strike = strikeRx.firstMatch(in: item.title, range: NSRange(item.title.startIndex..., in: item.title)) != nil
                guard item.categories.contains("alerts") || strike, now.timeIntervalSince(item.date) < maxAge else { continue }
                let days = dates(in: item.title, posted: item.date)
                if let last = days.max(), last < today { continue }  // every day it is about has passed
                let lines = lines(in: item.title, known: known)
                let mentionsLines = after.firstMatch(in: item.title, range: NSRange(item.title.startIndex..., in: item.title)) != nil
                let network = lines.isEmpty && (strike || !mentionsLines) && (!days.isEmpty || now.timeIntervalSince(item.date) < networkMaxAge)
                guard !lines.isEmpty || network else { continue }
                seen.insert(item.link)
                out.append(ServiceAlert(title: item.title, link: item.link, date: item.date, lines: lines, strike: strike))
            }
        }
        return out.sorted { $0.date > $1.date }
    }
}

/// A tiny RSS reader: title, link, date and categories of each item.
enum RSS {
    struct Item { var title = "", link = "", date = Date.distantPast, categories = Set<String>() }

    final class Reader: NSObject, XMLParserDelegate {
        var items: [Item] = [], cur: Item?, text = ""
        static let fmt: DateFormatter = {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"; return f
        }()
        func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            if e == "item" { cur = Item() }
            text = ""
        }
        func parser(_ p: XMLParser, foundCharacters s: String) { text += s }
        func parser(_ p: XMLParser, foundCDATA d: Data) { text += String(decoding: d, as: UTF8.self) }
        func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch e {
            case "title": cur?.title = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            case "link": cur?.link = t
            case "pubDate": cur?.date = Self.fmt.date(from: t) ?? .distantPast
            case "category": cur?.categories.insert(t.lowercased())
            case "item": if let c = cur { items.append(c) }; cur = nil
            default: break
            }
        }
    }

    static func items(_ data: Data) -> [Item] {
        let r = Reader(), p = XMLParser(data: data)
        p.delegate = r
        p.shouldResolveExternalEntities = false  // never fetch anything an RSS file points at
        p.parse()
        return r.items
    }
}
