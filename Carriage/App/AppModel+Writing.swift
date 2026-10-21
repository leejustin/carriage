import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import WidgetKit

/// Shown over the closed Duo for a moment after it folds shut: the cover comes down and the page is saved.
/// Also the machine's first unveiling on first launch: its plate and serial number, then the cover lifts.
struct FoldCurtain: Identifiable, Equatable {
    let id = UUID()
    var closing: Bool
    var unveiling = false
}

extension AppModel {
    // MARK: Files copy

    /// Writes the page's Markdown copy to Files, under a name that's unique among pages.
    func mirror(_ page: Page) {
        guard settings.mirrorToFiles, page.trashedAt == nil, !page.body.isEmpty else { return }
        let base = Exporter.fileName(page.displayTitle)
        var name = base + ".md"
        if name != page.mirrorName {
            var n = 2
            while isMirrorNameTaken(name, by: page) {
                name = "\(base) \(n).md"
                n += 1
            }
        }
        let old = page.mirrorName
        if old != name { page.mirrorName = name }
        MarkdownMirror.shared.write(name: name, oldName: old, title: page.displayTitle, body: page.body, strikes: page.strikes, underlines: page.underlines)
    }

    private func isMirrorNameTaken(_ name: String, by page: Page) -> Bool {
        let id = page.id
        let descriptor = FetchDescriptor<Page>(predicate: #Predicate { $0.mirrorName == name && $0.id != id && $0.trashedAt == nil })
        return ((try? context?.fetchCount(descriptor)) ?? 0) > 0
    }

    /// Brings every page's copy up to date, at launch and when the setting is turned on.
    func mirrorAllPages() {
        guard settings.mirrorToFiles else { return }
        let descriptor = FetchDescriptor<Page>(predicate: #Predicate { $0.trashedAt == nil })
        for page in (try? context?.fetch(descriptor)) ?? [] { mirror(page) }
        try? context?.save()
    }

    // MARK: Notebooks

    @discardableResult
    func createNotebook(named name: String) -> Notebook? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let context else { return nil }
        let notebook = Notebook(name: trimmed)
        context.insert(notebook)
        try? context.save()
        return notebook
    }

    func rename(_ notebook: Notebook, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        notebook.name = trimmed
        try? context?.save()
    }

    /// Deletes a notebook. Its pages stay, just no longer grouped.
    func delete(_ notebook: Notebook) {
        let id = notebook.id
        let descriptor = FetchDescriptor<Page>(predicate: #Predicate { $0.notebookID == id })
        for page in (try? context?.fetch(descriptor)) ?? [] { page.notebookID = nil }
        context?.delete(notebook)
        try? context?.save()
    }

    func move(_ page: Page, to notebook: Notebook?) {
        page.notebookID = notebook?.id
        try? context?.save()
    }

    // MARK: Journal

    /// Opens today's journal page, starting it with the date typed at the top if it's the first visit today.
    func openTodaysJournal(date: Date = .now) {
        guard let context else { return }
        let key = WritingDay.key(for: date)
        let journal = journalNotebook()
        var descriptor = FetchDescriptor<Page>(predicate: #Predicate { $0.journalDay == key && $0.trashedAt == nil })
        descriptor.fetchLimit = 1
        if let page = try? context.fetch(descriptor).first {
            open(page)
            return
        }
        guard canStartPage else {
            showLibrary = false
            showPaywall = true
            return
        }
        engine.save()
        let page = makePage(notebookID: journal.id)
        page.journalDay = key
        page.title = date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        page.body = date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()) + "\n\n"
        try? context.save()
        showLibrary = false
        engine.open(page, feed: true)
    }

    func journalNotebook() -> Notebook {
        let descriptor = FetchDescriptor<Notebook>(predicate: #Predicate { $0.isJournal })
        if let existing = try? context?.fetch(descriptor).first { return existing }
        let journal = Notebook(name: "Journal", isJournal: true)
        context?.insert(journal)
        try? context?.save()
        return journal
    }

    // MARK: Import

    static let importTypes: [UTType] = [.plainText, .text, UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "markdown") ?? .plainText]

    /// Turns text files from Files into pages. Stops at the free allowance and says so.
    func importFiles(_ urls: [URL]) {
        var imported = 0
        var last: Page?
        for url in urls {
            guard canStartPage else {
                showPaywall = true
                break
            }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { continue }
            let page = makePage(notebookID: nil)
            page.title = url.deletingPathExtension().lastPathComponent
            page.body = text.replacingOccurrences(of: "\r\n", with: "\n")
            page.wordCount = TextExport.wordCount(body: page.body, strikes: [])
            imported += 1
            last = page
        }
        try? context?.save()
        if imported > 0 {
            toast = Toast(text: imported == 1 ? "Imported 1 page" : "Imported \(imported) pages", symbol: "square.and.arrow.down")
            if imported == 1, let last { open(last) }
        }
    }

    // MARK: Print and image

    func print(_ page: Page? = nil) {
        guard let page = page ?? engine.page else { return }
        engine.save()
        let snapshot = PageSnapshot(page)
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo.printInfo()
        info.jobName = snapshot.title
        info.outputType = .general
        controller.printInfo = info
        controller.printingItem = TypedPagePDF.render(snapshot, face: settings.typeface, spacing: settings.lineSpacing)
        controller.present(animated: true)
    }

    /// A typed-page picture for sharing: the opening of the page on paper, signed "Typed on Carriage".
    func shareImage(_ page: Page? = nil) {
        guard let page = page ?? engine.page else { return }
        engine.save()
        let image = TypedPageImage.render(PageSnapshot(page), face: settings.typeface)
        exportRequest = ExportRequest(items: [image])
    }

    // MARK: Versions

    /// Restores a version of any page; the page in the machine is restored in place.
    func restore(_ version: PageVersion, of page: Page) {
        if engine.page?.id == page.id {
            engine.restore(version)
        } else if let context {
            PageHistory.snapshot(page, reason: "Before restore", in: context, ifOlderThan: 0)
            page.body = version.body
            page.strikeData = version.strikeData
            page.underlineData = version.underlineData
            page.wordCount = version.wordCount
            page.modifiedAt = .now
            try? context.save()
            mirror(page)
        }
        toast = Toast(text: "Restored the version from \(version.savedAt.formatted(date: .abbreviated, time: .shortened))", symbol: "clock.arrow.circlepath")
    }

    /// Makes an old version into its own page, leaving the original alone.
    func copyAsNewPage(_ version: PageVersion, of page: Page) {
        guard let context else { return }
        guard canStartPage else {
            showPaywall = true
            return
        }
        let copy = makePage(notebookID: page.notebookID)
        copy.title = page.displayTitle + " (" + version.savedAt.formatted(date: .abbreviated, time: .omitted) + ")"
        copy.body = version.body
        copy.strikeData = version.strikeData
        copy.underlineData = version.underlineData
        copy.wordCount = version.wordCount
        try? context.save()
        toast = Toast(text: "Saved as a new page", symbol: "doc.on.doc")
    }

    // MARK: Widgets and the outer screen

    /// Shares today's numbers with the widgets.
    func publishStats() {
        SharedStats.write(
            wordsToday: stats.wordsToday,
            goal: settings.dailyGoal,
            streak: stats.streak,
            lastLine: lastTypedLine()
        )
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// The last line with words on it, for the glance on the closed Duo.
    func lastTypedLine() -> String {
        let text = engine.paper.textView.textStorage.string
        let line = text.split(separator: "\n").last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return line.map { String($0.prefix(80)).trimmingCharacters(in: .whitespaces) } ?? ""
    }

    // MARK: Rating

    /// Asks for a rating once per version, after the third filed page: a natural pause, never mid-sentence.
    func notePageFiled() {
        let defaults = UserDefaults.standard
        let filed = defaults.integer(forKey: "pagesFiled") + 1
        defaults.set(filed, forKey: "pagesFiled")
        let version = Bundle.main.versionString
        guard filed >= 3, defaults.string(forKey: "reviewRequestedVersion") != version, !focusMode.isOn else { return }
        defaults.set(version, forKey: "reviewRequestedVersion")
        reviewRequestedAt = .now
    }
}
