import Foundation
#if canImport(MetricKit) && os(iOS)
import MetricKit
#endif

/// Crash, hang and battery reports that iOS hands the app (MetricKit), about once a day. Kept on
/// the phone only (the last 20) and shared from Settings if the user chooses to: nothing is sent.
final class Diagnostics: NSObject {
    static let shared = Diagnostics()
    private let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let f = base.appendingPathComponent("Diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
        return f
    }()

    func start() {
        #if canImport(MetricKit) && os(iOS)
        MXMetricManager.shared.add(self)
        #endif
    }

    /// The saved reports, newest last.
    var reports: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// All of them in one file, to share (Mail, AirDrop…).
    func bundle() -> URL? {
        let parts = reports.compactMap { try? String(contentsOf: $0, encoding: .utf8) }
        guard !parts.isEmpty else { return nil }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("BusMakro-diagnostics-\(version).json")
        try? ("[\n" + parts.joined(separator: ",\n") + "\n]").write(to: out, atomically: true, encoding: .utf8)
        return out
    }

    fileprivate func save(_ json: Data, kind: String) {
        let name = "\(Int(Date().timeIntervalSince1970))-\(kind).json"
        try? json.write(to: folder.appendingPathComponent(name))
        for old in reports.dropLast(20) { try? FileManager.default.removeItem(at: old) }
    }
}

#if canImport(MetricKit) && os(iOS)
extension Diagnostics: MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXMetricPayload]) {
        for p in payloads { save(p.jsonRepresentation(), kind: "metrics") }
    }
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for p in payloads { save(p.jsonRepresentation(), kind: "diagnostics") }
    }
}
#endif
