import Foundation
import os

/// Keeps a Markdown copy of every page in the Files app, so writers own their work outside Carriage:
/// iCloud Drive › Carriage when iCloud Drive is on, otherwise On My iPhone › Carriage.
///
/// Files are written off the main thread. The page model remembers each copy's file name, so a renamed page
/// replaces its old file instead of leaving it behind.
nonisolated final class MarkdownMirror: @unchecked Sendable {
    static let shared = MarkdownMirror()

    private let queue = DispatchQueue(label: "Carriage.MarkdownMirror", qos: .utility)
    private let log = Logger(subsystem: "Carriage", category: "Mirror")
    /// Resolved on the queue: looking up the iCloud container can block.
    private var folder: URL?
    private var resolved = false

    init() {}

    /// Writes (or rewrites) a page's copy. `oldName` is removed when the name changed. The Markdown is built on
    /// the mirror's own queue, so a long page never holds up typing.
    func write(name: String, oldName: String?, title: String, body: String, strikes: [NSRange], underlines: [NSRange]) {
        queue.async { [self] in
            let markdown = TextExport.markdown(title: title, body: body, strikes: strikes, underlines: underlines)
            guard let folder = resolveFolder() else { return }
            if let oldName, oldName != name {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(oldName))
            }
            let url = folder.appendingPathComponent(name)
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                log.error("Couldn't write \(name, privacy: .public): \(error.localizedDescription)")
            }
        }
    }

    func remove(name: String) {
        queue.async { [self] in
            guard let folder = resolveFolder() else { return }
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    /// Where the copies live, for showing the writer.
    func locationDescription(_ completion: @escaping @Sendable (String) -> Void) {
        queue.async { [self] in
            _ = resolveFolder()
            completion(usesICloud ? "iCloud Drive › Carriage" : "On My iPhone › Carriage")
        }
    }

    private var usesICloud = false

    private func resolveFolder() -> URL? {
        if resolved { return folder }
        resolved = true
        let manager = FileManager.default
        if let container = manager.url(forUbiquityContainerIdentifier: nil) {
            folder = container.appendingPathComponent("Documents", isDirectory: true)
            usesICloud = true
        } else {
            folder = manager.urls(for: .documentDirectory, in: .userDomainMask).first
        }
        if let folder { try? manager.createDirectory(at: folder, withIntermediateDirectories: true) }
        return folder
    }
}
