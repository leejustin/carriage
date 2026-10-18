import Foundation
import MetricKit

/// Crash and hang reports from iOS (MetricKit), kept on the device. Nothing is sent anywhere: the writer can
/// choose to share them from Settings, which is why the privacy label can still say "Data Not Collected".
final class DiagnosticsStore: NSObject, MXMetricManagerSubscriber {
    static let shared = DiagnosticsStore()

    /// How many reports to keep.
    nonisolated static let limit = 20

    nonisolated private static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Diagnostics", isDirectory: true)
    }

    func start() {
        MXMetricManager.shared.add(self)
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let manager = FileManager.default
        try? manager.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        for payload in payloads {
            let name = "Carriage diagnostics \(payload.timeStampEnd.formatted(.iso8601)).json"
                .replacingOccurrences(of: ":", with: "-")
            try? payload.jsonRepresentation().write(to: Self.folder.appendingPathComponent(name))
        }
        // Keep only the newest reports.
        let files = (try? manager.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        let sorted = files.sorted {
            let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return a > b
        }
        for old in sorted.dropFirst(Self.limit) { try? manager.removeItem(at: old) }
    }

    /// The saved reports, newest first.
    func reports() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func deleteAll() {
        try? FileManager.default.removeItem(at: Self.folder)
    }
}
