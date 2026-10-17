import FoldKit
import Observation
import SwiftData
import SwiftUI

/// The app's shared state: settings, store, fold, the machine and what's on screen.
@Observable
final class AppModel {
    let settings: AppSettings
    let store = Store()
    let fold = FoldMonitor()
    let stats: WritingStats
    let engine: TypewriterEngine
    let focus = FocusTimer()

    var showLibrary = false
    var showSettings = false
    var showPaywall = false
    var showShop = false
    /// The one-time note on a regular iPhone that Carriage was made for iPhone Duo.
    var showDuoLetter = false
    var showFocusSetup = false
    var filesRequest: FilesRequest?
    let focusMode = WritingFocus.shared
    var exportRequest: ExportRequest?
    var toast: Toast?

    @ObservationIgnored private(set) var context: ModelContext?

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
        stats = WritingStats(goal: settings.dailyGoal)
        engine = TypewriterEngine(settings: settings, stats: stats)
        engine.onHardwareKeyPress = { [weak self] in self?.fold.noteHardwareKeyPress() }
        focus.onFinish = { [weak self] in self?.focusFinished() }
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "foldSimulation"), let simulation = FoldSimulation(rawValue: raw) {
            fold.simulation = simulation
        }
        #endif
    }

    func start(context: ModelContext) {
        guard self.context == nil else { return }
        self.context = context
        engine.attach(context)
        stats.attach(context)
        applyAudioSettings()
        // Purchases aren't known yet; the chosen machine is re-applied once they load.
        SoundEngine.shared.start(machine: .portable)
        Haptics.shared.prepare()
        emptyOldTrash()
        #if DEBUG
        DemoContent.seedIfRequested(context: context, settings: settings)
        if ProcessInfo.processInfo.arguments.contains("-hardwareKeyboard") { fold.noteHardwareKeyPress() }
        if ProcessInfo.processInfo.arguments.contains("-resetDuoLetter") {
            UserDefaults.standard.removeObject(forKey: "seenDuoLetter")
            UserDefaults.standard.removeObject(forKey: "hasSeenHinge")
        }
        #endif
        loadNextPage(feed: false, explainLimit: false)
        #if DEBUG
        DemoContent.exportPDFIfRequested(engine.page, settings: settings)
        #endif
        Task {
            await store.load()
            enforceEntitlements()
            applyPurchasedChoices()
        }
        Task {
            // Give the hinge a moment to report before deciding this isn't a Duo.
            try? await Task.sleep(for: .seconds(1.5))
            if !isDuo, !UserDefaults.standard.bool(forKey: "seenDuoLetter") { showDuoLetter = true }
        }
    }

    // MARK: The machine

    /// Whether this is an iPhone Duo. Remembered once a hinge has been seen, so a Duo with no hinge reading at the
    /// moment (closed, or between updates) is still treated as one.
    var isDuo: Bool {
        fold.state.hasHinge || UserDefaults.standard.bool(forKey: "hasSeenHinge")
    }

    /// Called whenever the hinge reports, so `isDuo` stays true while the hinge is quiet.
    func rememberHinge() {
        guard fold.state.hasHinge, !fold.state.isSimulated, !UserDefaults.standard.bool(forKey: "hasSeenHinge") else { return }
        UserDefaults.standard.set(true, forKey: "hasSeenHinge")
    }

    // MARK: Writing focus

    func toggleFocus() {
        focusMode.toggle()
        SoundEngine.shared.play(.shift)
        guard focusMode.isOn else { return }
        toast = Toast(text: "Focus. Tap the paper for controls.", symbol: "moon")
        // The first time, offer to have iOS silence notifications too.
        if !UserDefaults.standard.bool(forKey: "seenFocusSetup") {
            UserDefaults.standard.set(true, forKey: "seenFocusSetup")
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                showFocusSetup = true
            }
        }
    }

    func paperTapped() {
        engine.wakeControls()
        if focusMode.isOn { focusMode.peek() }
    }

    func dismissDuoLetter() {
        UserDefaults.standard.set(true, forKey: "seenDuoLetter")
        showDuoLetter = false
    }

    // MARK: Pages

    var pageCount: Int {
        let descriptor = FetchDescriptor<Page>(predicate: #Predicate { $0.trashedAt == nil })
        return (try? context?.fetchCount(descriptor)) ?? 0
    }

    /// Pages ever started, so deleting pages doesn't reset the free allowance.
    /// Synced pages count too, so a reinstall doesn't reset it either.
    var pagesUsed: Int {
        let all = (try? context?.fetchCount(FetchDescriptor<Page>())) ?? 0
        return max(all, UserDefaults.standard.integer(forKey: "pagesCreated"))
    }

    /// Whether a fresh sheet is allowed without the unlock.
    var canStartPage: Bool {
        guard let limit = store.freePageLimit else { return true }
        return pagesUsed < limit
    }

    var isPresentingSheet: Bool {
        showLibrary || showSettings || showPaywall || showShop || showDuoLetter || showFocusSetup || exportRequest != nil || filesRequest != nil
    }

    @ObservationIgnored private var isFiling = false

    /// Feeds a fresh sheet into the machine, or shows the paywall once the free pages are used.
    func newSheet() {
        guard canStartPage else {
            showLibrary = false
            showPaywall = true
            return
        }
        engine.save()
        let page = makePage()
        showLibrary = false
        engine.open(page, feed: true)
    }

    /// Files the sheet in the machine as a finished page and feeds the next one.
    func fileCurrentSheet() {
        guard let page = engine.page, !isFiling else { return }
        isFiling = true
        engine.save()
        SoundEngine.shared.play(.paperFeed, gain: 0.8)
        engine.paper.pullOut { [self] in
            page.isFiled = true
            try? context?.save()
            toast = Toast(text: "Filed under Pages", symbol: "tray.full")
            loadNextPage(feed: true, explainLimit: true)
            isFiling = false
        }
    }

    func open(_ page: Page) {
        showLibrary = false
        if page.isFiled {
            page.isFiled = false
        }
        engine.open(page, feed: engine.page?.id != page.id)
    }

    func trash(_ page: Page) {
        page.trashedAt = Date()
        try? context?.save()
        if engine.page?.id == page.id {
            loadNextPage(feed: false, explainLimit: true)
        }
    }

    func restore(_ page: Page) {
        page.trashedAt = nil
        try? context?.save()
    }

    func deleteForever(_ page: Page) {
        context?.delete(page)
        try? context?.save()
    }

    /// Puts something in the machine when its page has gone: the latest draft, else a fresh sheet if the free
    /// allowance has room, else the most recent page (out of the wastebasket if need be), with the paywall to explain.
    private func loadNextPage(feed: Bool, explainLimit: Bool) {
        if let draft = mostRecentDraft() {
            engine.open(draft, feed: feed)
            return
        }
        if canStartPage {
            engine.open(makePage(), feed: true)
            return
        }
        if let page = mostRecentPage(trashed: false) ?? mostRecentPage(trashed: true) {
            page.trashedAt = nil
            page.isFiled = false
            engine.open(page, feed: feed)
            if explainLimit { showPaywall = true }
        } else {
            // Nothing exists at all (another device deleted everything); the machine still needs paper.
            engine.open(makePage(), feed: true)
        }
    }

    private func makePage() -> Page {
        let paper = store.canUse(settings.defaultPaper) ? settings.defaultPaper : .bond
        let ink = store.canUse(settings.defaultInk) ? settings.defaultInk : .black
        let used = pagesUsed
        let page = Page(mode: settings.defaultMode, paper: paper, ink: ink)
        context?.insert(page)
        UserDefaults.standard.set(used + 1, forKey: "pagesCreated")
        try? context?.save()
        return page
    }

    private func mostRecentDraft() -> Page? {
        var descriptor = FetchDescriptor<Page>(
            predicate: #Predicate { $0.trashedAt == nil && $0.isFiled == false },
            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context?.fetch(descriptor).first
    }

    private func mostRecentPage(trashed: Bool) -> Page? {
        var descriptor = trashed
            ? FetchDescriptor<Page>(predicate: #Predicate { $0.trashedAt != nil }, sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)])
            : FetchDescriptor<Page>(predicate: #Predicate { $0.trashedAt == nil }, sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try? context?.fetch(descriptor).first
    }

    private func emptyOldTrash() {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        let descriptor = FetchDescriptor<Page>(predicate: #Predicate { $0.trashedAt != nil })
        for page in (try? context?.fetch(descriptor)) ?? [] where (page.trashedAt ?? .now) < cutoff {
            context?.delete(page)
        }
        try? context?.save()
    }

    // MARK: Settings

    func applyAudioSettings() {
        SoundEngine.shared.isEnabled = settings.soundsOn
        SoundEngine.shared.volume = Float(settings.volume)
        SoundEngine.shared.playsInSilentMode = settings.playsInSilentMode
        Haptics.shared.isEnabled = settings.hapticsOn
    }

    func selectMachine(_ machine: MachineSound) {
        guard store.canUse(machine) else {
            showShop = true
            return
        }
        settings.machineSound = machine
        SoundEngine.shared.load(machine)
    }

    /// Once purchases are known, switch to the machine the writer picked (it may be from a pack).
    func applyPurchasedChoices() {
        let machine = store.canUse(settings.machineSound) ? settings.machineSound : .portable
        if SoundEngine.shared.machine != machine { SoundEngine.shared.load(machine) }
    }

    /// If a pack was refunded, fall back to free styles. Only acts on a confirmed entitlement check, so being
    /// offline at launch never resets anyone's choices; the chosen machine itself is kept in settings either way.
    func enforceEntitlements() {
        guard store.entitlementsChecked else { return }
        if !store.canUse(settings.defaultPaper) { settings.defaultPaper = .bond }
        if !store.canUse(settings.defaultInk) { settings.defaultInk = .black }
        if let page = engine.page {
            if !store.canUse(page.paper) { engine.setPaper(.bond) }
            if !store.canUse(page.ink) { engine.setInk(.black) }
        }
        applyPurchasedChoices()
    }

    // MARK: Export

    func export(_ format: ExportFormat) {
        guard let page = engine.page else { return }
        engine.save()
        export(page, format: format)
    }

    func export(_ page: Page, format: ExportFormat) {
        engine.save()
        do {
            let url = try Exporter.file(for: PageSnapshot(page), format: format, face: settings.typeface, spacing: settings.lineSpacing)
            exportRequest = ExportRequest(items: [url])
        } catch {
            toast = Toast(text: "Couldn't export: \(error.localizedDescription)", symbol: "exclamationmark.triangle")
        }
    }

    /// Saves a copy of a page into the Files app (iCloud Drive, On My iPhone, or any connected storage).
    func saveToFiles(_ page: Page? = nil, format: ExportFormat) {
        guard let page = page ?? engine.page else { return }
        engine.save()
        do {
            let url = try Exporter.file(for: PageSnapshot(page), format: format, face: settings.typeface, spacing: settings.lineSpacing)
            filesRequest = FilesRequest(urls: [url], label: "Saved to Files")
        } catch {
            toast = Toast(text: "Couldn't save: \(error.localizedDescription)", symbol: "exclamationmark.triangle")
        }
    }

    /// Saves every page (not the wastebasket) into one folder in Files, as a backup the writer owns.
    func exportAllPages(format: ExportFormat) {
        engine.save()
        let descriptor = FetchDescriptor<Page>(predicate: #Predicate { $0.trashedAt == nil }, sortBy: [SortDescriptor(\.createdAt)])
        let pages = ((try? context?.fetch(descriptor)) ?? []).map(PageSnapshot.init)
        guard !pages.isEmpty else {
            toast = Toast(text: "No pages to export yet", symbol: "doc")
            return
        }
        do {
            let folder = try Exporter.folder(for: pages, format: format, face: settings.typeface, spacing: settings.lineSpacing)
            filesRequest = FilesRequest(urls: [folder], label: "\(pages.count) pages saved to Files")
        } catch {
            toast = Toast(text: "Couldn't export: \(error.localizedDescription)", symbol: "exclamationmark.triangle")
        }
    }

    /// Notes takes plain text from the share sheet, so this shares the text itself.
    func sendToNotes(_ page: Page? = nil) {
        guard let page = page ?? engine.page else { return }
        engine.save()
        let snapshot = PageSnapshot(page)
        exportRequest = ExportRequest(items: [snapshot.title + "\n\n" + snapshot.plainText], notesHint: true)
    }

    func copyText(_ page: Page? = nil) {
        guard let page = page ?? engine.page else { return }
        engine.save()
        UIPasteboard.general.string = PageSnapshot(page).plainText
        toast = Toast(text: "Copied", symbol: "doc.on.doc")
    }

    // MARK: Focus timer

    private func focusFinished() {
        SoundEngine.shared.play(.bell)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { SoundEngine.shared.play(.bell, gain: 0.7) }
        Haptics.shared.bell()
        let words = focus.wordsAtStart.map { max(0, stats.wordsToday - $0) } ?? 0
        toast = Toast(text: words > 0 ? "Time. \(words) words." : "Time.", symbol: "bell")
    }
}

struct FilesRequest: Identifiable {
    let id = UUID()
    var urls: [URL]
    /// The confirmation to show once Files has saved the copy.
    var label: String
}

struct ExportRequest: Identifiable {
    let id = UUID()
    var items: [Any]
    var notesHint = false
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var symbol: String
}
