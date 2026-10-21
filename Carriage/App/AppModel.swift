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
    /// The first-run tour (on a regular iPhone it opens with the note that Carriage was made for iPhone Duo).
    var showOnboarding = false
    /// The page whose version history is open.
    var versionsPage: Page?
    /// Shown on the closed Duo for a moment after folding shut: the page was saved.
    var foldCurtain: FoldCurtain?
    /// The two-page reading spread on a Duo opened flat like a book.
    /// Set when it's a good moment to ask for an App Store rating.
    var reviewRequestedAt: Date?
    var showFocusSetup = false
    var filesRequest: FilesRequest?
    let focusMode = WritingFocus.shared
    var exportRequest: ExportRequest?
    var toast: Toast?

    @ObservationIgnored private(set) var context: ModelContext?
    @ObservationIgnored private var remoteChangeObserver: NSObjectProtocol?
    @ObservationIgnored private var reconcileWork: DispatchWorkItem?

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
        stats = WritingStats(goal: settings.dailyGoal)
        engine = TypewriterEngine(settings: settings, stats: stats)
        engine.onHardwareKeyPress = { [weak self] in
            #if targetEnvironment(simulator)
            // The Simulator routes the Mac's keyboard here; typing on it shouldn't hide the typewriter keys.
            // `-hardwareKeyboard` still shows the hardware layout.
            guard ProcessInfo.processInfo.arguments.contains("-hardwareKeyboard") else { return }
            #endif
            self?.fold.noteHardwareKeyPress()
        }
        engine.onSaved = { [weak self] page in self?.mirror(page) }
        engine.onSyncNotice = { [weak self] message in self?.toast = Toast(text: message, symbol: "arrow.triangle.2.circlepath") }
        engine.onMarginBell = { [weak self] in self?.teachCarriagePush() }
        engine.onCarriagePushed = { UserDefaults.standard.set(true, forKey: "pushedCarriage") }
        engine.onPause = { [weak self] endOfLine in self?.checkFreeWords(endOfLine: endOfLine) }
        engine.onLockedKey = { [weak self] in self?.showPaywall = true }
        stats.onChange = { [weak self] in self?.publishStats() }
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
        if ProcessInfo.processInfo.arguments.contains("-resetOnboarding") {
            UserDefaults.standard.removeObject(forKey: "seenOnboarding")
            UserDefaults.standard.removeObject(forKey: "hasSeenHinge")
            UserDefaults.standard.removeObject(forKey: "pushedCarriage")
            UserDefaults.standard.removeObject(forKey: "carriagePushHints")
            UserDefaults.standard.removeObject(forKey: "unveiled")
        }
        #endif
        loadNextPage(feed: false, explainLimit: false)
        #if DEBUG
        DemoContent.exportPDFIfRequested(engine.page, settings: settings)
        DemoContent.exportShareImagesIfRequested(engine.page, settings: settings)
        DemoContent.stageScreenshotScene(self)
        #endif
        Task {
            await store.load()
            updateTypingLock()
        }
        // A new machine arrives under its cover.
        if !UserDefaults.standard.bool(forKey: "unveiled"), !UserDefaults.standard.bool(forKey: "seenOnboarding") {
            UserDefaults.standard.set(true, forKey: "unveiled")
            foldCurtain = FoldCurtain(closing: false, unveiling: true)
        }
        Task {
            // Give the hinge a moment to report, so the tour knows whether this is a Duo.
            try? await Task.sleep(for: .seconds(1.5))
            if !UserDefaults.standard.bool(forKey: "seenOnboarding") { showOnboarding = true }
        }
        // Synced changes from other devices: let the machine check the open page.
        remoteChangeObserver = NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleReconcile() }
        }
        mirrorAllPages()
        publishStats()
        // An action from Siri or a widget that launched the app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, let action = IntentRouter.shared.pending else { return }
            IntentRouter.perform(action, model: self)
        }
    }

    func scheduleReconcile() {
        reconcileWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.engine.reconcileWithStore() }
        reconcileWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
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

    /// The first few times the bell rings, show how to return the carriage by hand, until the writer has done it once.
    func teachCarriagePush() {
        let defaults = UserDefaults.standard
        let shown = defaults.integer(forKey: "carriagePushHints")
        guard !defaults.bool(forKey: "pushedCarriage"), shown < 3, !focusMode.isOn else { return }
        defaults.set(shown + 1, forKey: "carriagePushHints")
        toast = Toast(text: "Ding! Push the paper to the right to return the carriage", symbol: "arrow.right.to.line")
    }

    func paperTapped() {
        engine.wakeControls()
        if focusMode.isOn { focusMode.peek() }
    }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "seenOnboarding")
        showOnboarding = false
        FocusTip.tourFinished = true
    }

    /// Shows the tour again, from Settings.
    func replayOnboarding() {
        showSettings = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showOnboarding = true }
    }

    // MARK: Pages

    var pageCount: Int {
        let descriptor = FetchDescriptor<Page>(predicate: #Predicate { $0.trashedAt == nil })
        return (try? context?.fetchCount(descriptor)) ?? 0
    }

    /// Pages ever started, so deleting pages doesn't reset the free allowance.
    /// Synced pages count too, so a reinstall doesn't reset it either.
    /// Free words left before the unlock, or nil once unlocked.
    var freeWordsLeft: Int? {
        guard let limit = store.freeWordLimit else { return nil }
        return max(0, limit - stats.totalWords)
    }

    /// Whether a fresh sheet is allowed without the unlock.
    var canStartPage: Bool { freeWordsLeft != 0 }

    /// Past the free words, the writer finishes the line (or a short paragraph's grace) before the letter.
    func checkFreeWords(endOfLine: Bool) {
        guard let limit = store.freeWordLimit, !engine.typingLocked, stats.totalWords >= limit else { return }
        guard endOfLine || stats.totalWords >= limit + 150 else { return }
        engine.typingLocked = true
        engine.save()
        showPaywall = true
    }

    /// Rests the keys when the free words are already used up (at launch, on another device), and frees them
    /// once the unlock arrives.
    func updateTypingLock() {
        engine.typingLocked = freeWordsLeft == 0
    }

    var isPresentingSheet: Bool {
        showLibrary || showSettings || showPaywall || showOnboarding || showFocusSetup || exportRequest != nil || filesRequest != nil || versionsPage != nil
    }

    @ObservationIgnored private var isFiling = false

    /// Feeds a fresh sheet into the machine, or shows the paywall once the free pages are used.
    /// The sheet goes into `notebookID`, or by default the notebook of the page in the machine (journals excepted).
    func newSheet(notebookID: UUID? = nil, inheritNotebook: Bool = true) {
        guard canStartPage else {
            showLibrary = false
            showPaywall = true
            return
        }
        engine.save()
        var notebook = notebookID
        if notebook == nil, inheritNotebook, engine.page?.journalDay == nil { notebook = engine.page?.notebookID }
        let page = makePage(notebookID: notebook)
        showLibrary = false
        engine.open(page, feed: true)
    }

    /// Files the sheet in the machine as a finished page and feeds the next one.
    func fileCurrentSheet() {
        guard let page = engine.page, !isFiling else { return }
        isFiling = true
        engine.save()
        SoundEngine.shared.play(.paperRelease)
        Haptics.shared.paperRelease()
        engine.paper.pullOut { [self] in
            page.isFiled = true
            try? context?.save()
            toast = Toast(text: "Filed under Pages", symbol: "tray.full")
            loadNextPage(feed: true, explainLimit: true)
            isFiling = false
            notePageFiled()
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
        if let name = page.mirrorName { MarkdownMirror.shared.remove(name: name) }
        if engine.page?.id == page.id {
            loadNextPage(feed: false, explainLimit: true)
        }
    }

    func restore(_ page: Page) {
        page.trashedAt = nil
        try? context?.save()
        mirror(page)
    }

    func deleteForever(_ page: Page) {
        if let context { PageHistory.deleteAll(of: page.id, in: context) }
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

    func makePage(notebookID: UUID? = nil) -> Page {
        let page = Page(mode: settings.defaultMode, paper: settings.defaultPaper, ink: settings.defaultInk)
        page.notebookID = notebookID
        context?.insert(page)
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
        SoundEngine.shared.ambience = settings.ambience
        SoundEngine.shared.volume = Float(settings.volume)
        SoundEngine.shared.playsInSilentMode = settings.playsInSilentMode
        Haptics.shared.isEnabled = settings.hapticsOn
    }

    func selectMachine(_ machine: MachineSound) {
        settings.machineSound = machine
        SoundEngine.shared.load(machine)
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
