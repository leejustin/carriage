import Observation
import os
import SwiftData
import UIKit

/// The machine: takes key presses, puts ink on the page, and drives the sound, haptics and carriage.
///
/// The page's text lives in the paper view's text storage while it's open, so a key press never goes through
/// SwiftUI. The `Page` model is updated on a short debounce and whenever the app steps away.
@Observable
final class TypewriterEngine {
    @ObservationIgnored let paper = PaperView()
    @ObservationIgnored let keyboard = KeyboardView()

    private(set) var page: Page?
    private(set) var mode: TypingMode = .free
    private(set) var wordCount = 0
    /// Flips on with each key press and off after a pause; the controls fade while it's on.
    private(set) var isTyping = false
    /// True while nothing has been typed on the sheet, for the welcome hint.
    private(set) var isBlank = true
    /// Set when the writer reaches the day's goal, for the little celebration.
    var goalReachedAt: Date?

    /// Called on any hardware key press, so the layout can hide the on-screen keys.
    @ObservationIgnored var onHardwareKeyPress: (() -> Void)?
    /// Called after every save that changed the page, for the Files copy and widgets.
    @ObservationIgnored var onSaved: ((Page) -> Void)?
    /// Called when the same page was edited on another device; the message says what happened.
    @ObservationIgnored var onSyncNotice: ((String) -> Void)?
    /// The margin bell rang, so the end of the line is near.
    @ObservationIgnored var onMarginBell: (() -> Void)?
    @ObservationIgnored var onCarriagePushed: (() -> Void)?
    /// Set when the free words are used up: the keys rest until the unlock.
    @ObservationIgnored var typingLocked = false
    /// A key was pressed while the keys rest.
    @ObservationIgnored var onLockedKey: (() -> Void)?
    /// A word or a line was finished: a natural place to stop for the unlock letter.
    @ObservationIgnored var onPause: ((_ endOfLine: Bool) -> Void)?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let stats: WritingStats
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var shift: KeyboardView.ShiftState = .off
    @ObservationIgnored private var shiftIsAutomatic = false
    @ObservationIgnored private var lastShiftTap: Date = .distantPast
    @ObservationIgnored private var bellRungOnLine = false
    @ObservationIgnored private var saveWork: DispatchWorkItem?
    @ObservationIgnored private var typingWork: DispatchWorkItem?
    @ObservationIgnored private var spellWork: DispatchWorkItem?
    @ObservationIgnored private var pendingEdit: NSRange?
    @ObservationIgnored private var lastSave = Date()
    /// The most words the open page has held, for counting words written today.
    @ObservationIgnored private var wordPeak = 0
    /// What this device last read from or wrote to the page model. If the model differs, another device wrote it.
    @ObservationIgnored private var lastSynced = PageText()
    @ObservationIgnored private var lastVersionAt: Date = .distantPast
    @ObservationIgnored private var lastKeyAt: Date = .distantPast
    @ObservationIgnored private lazy var textDelegate = PaperTextDelegate(engine: self)
    /// Key-to-ink timing, visible in Instruments' Points of Interest. The budget is about 20 ms.
    @ObservationIgnored private let signposter = OSSignposter(subsystem: "Carriage", category: .pointsOfInterest)

    init(settings: AppSettings, stats: WritingStats) {
        self.settings = settings
        self.stats = stats
        keyboard.onKey = { [weak self] action, fan in self?.press(action, fan: fan) }
        paper.keyCatcher.onInsert = { [weak self] text in self?.hardwareInsert(text) }
        paper.keyCatcher.onDelete = { [weak self] in self?.press(.delete, fan: 0.9) }
        paper.keyCatcher.onHardwarePress = { [weak self] in self?.onHardwareKeyPress?() }
        paper.onReturnLever = { [weak self] in self?.press(.carriageReturn, fan: 0.05) }
        paper.onCarriagePushed = { [weak self] in self?.onCarriagePushed?() }
        paper.onRackTick = { SoundEngine.shared.play(.backspace, gain: 0.22) }
        paper.textView.delegate = textDelegate
        paper.onRestyle = { [weak self] in self?.scheduleSpellCheck() }
        paper.onDoubleTap = { [weak self] index in self?.toggleUnderline(wordAt: index) }
    }

    func attach(_ context: ModelContext) {
        self.context = context
    }

    // MARK: Pages

    /// Puts a page in the machine.
    func open(_ page: Page, feed: Bool = false) {
        // Always save first: reopening the page in the machine must not drop the last second of typing.
        save()
        self.page = page
        wordPeak = page.wordCount
        lastSynced = PageText(page)
        lastVersionAt = .distantPast
        if let context { PageHistory.snapshot(page, reason: "Opened", in: context, ifOlderThan: 30 * 60) }
        mode = page.mode
        keyboard.mode = mode
        setShift(.off)
        bellRungOnLine = false
        applyConfiguration()
        let text = paper.styler.attributedText(body: page.body, strikes: page.strikes, underlines: page.underlines)
        let storage = paper.textView.textStorage
        storage.beginEditing()
        storage.setAttributedString(text)
        storage.endEditing()
        paper.textView.refreshStrikes()
        paper.textView.selectedRange = NSRange(location: storage.length, length: 0)
        paper.textView.undoManager?.removeAllActions()
        paper.textView.allowsUndo = mode == .free
        wordCount = page.wordCount
        isBlank = storage.length == 0
        paper.layoutIfNeeded()
        paper.textView.ensureLayoutNearEnd()
        paper.syncCarriage(.none)
        settleCarriage()
        updateAutoShift()
        if feed {
            SoundEngine.shared.play(.paperFeed)
            Haptics.shared.paperFeed()
            paper.feedIn()
        }
        scheduleSpellCheck()
    }

    /// TextKit 2 refines its height estimates for a long page over the next few passes; line the typing line
    /// back up once it has.
    private func settleCarriage() {
        for delay in [0.0, 0.15, 0.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, !self.isTyping else { return }
                self.paper.textView.ensureLayoutNearEnd()
                self.paper.syncCarriage(.none)
            }
        }
    }

    func setMode(_ newMode: TypingMode) {
        guard newMode != mode else { return }
        mode = newMode
        page?.mode = newMode
        keyboard.mode = newMode
        paper.textView.undoManager?.removeAllActions()
        paper.textView.allowsUndo = newMode == .free
        SoundEngine.shared.play(.shift)
        scheduleSave()
    }

    func setPaper(_ style: PaperStyle) {
        page?.paper = style
        applyConfiguration()
        scheduleSave()
    }

    func setInk(_ ink: InkStyle) {
        page?.ink = ink
        applyConfiguration()
        scheduleSave()
    }

    /// Pushes settings and the page's own style into the paper and keyboard.
    func applyConfiguration(presentation: PaperPresentation? = nil, reduceMotion: Bool? = nil, night: Bool? = nil) {
        var c = paper.configuration
        if let presentation, presentation != c.presentation {
            c.presentation = presentation
            // Typing mode edits the text directly, outside the text view's undo stack; don't let undo replay stale edits.
            paper.textView.undoManager?.removeAllActions()
        }
        if let reduceMotion { c.reduceMotion = reduceMotion }
        if let night { c.night = night }
        c.face = settings.typeface
        c.lineWidth = settings.lineWidth
        c.spacing = settings.lineSpacing
        c.carriage = settings.carriage
        c.finish = settings.finish
        c.typebars = settings.typebarsOn
        c.paper = page?.paper ?? settings.defaultPaper
        c.ink = page?.ink ?? settings.defaultInk
        c.inkSeed = page?.inkSeed ?? 1
        paper.configure(c)
        keyboard.finish = settings.finish
        keyboard.style = settings.keyboardStyle
        keyboard.reduceMotion = c.reduceMotion
        if c.presentation == .typing {
            paper.textView.selectedRange = NSRange(location: paper.textView.textStorage.length, length: 0)
        }
    }

    // MARK: Keys

    func press(_ action: KeyAction, fan: CGFloat) {
        guard page != nil else { return }
        let interval = signposter.beginInterval("Key")
        defer { signposter.endInterval("Key", interval) }
        markTyping()
        // Time spent typing, for words per minute. A pause over a minute is a break, not writing.
        let now = Date()
        let gap = now.timeIntervalSince(lastKeyAt)
        if gap < 60 { stats.addActiveSeconds(gap) }
        lastKeyAt = now
        switch action {
        case let .character(lower, shifted):
            let text = shift == .off ? lower : shifted
            if shift == .once { setShift(.off) }
            type(text, fan: fan)
        case .space:
            type(" ", fan: 0.5)
        case .tab:
            type("\t", fan: 0.1)
        case .carriageReturn:
            carriageReturn()
        case .delete:
            mode == .typewriter ? strikeOut() : deleteBackward()
        case .shift:
            tapShift()
        }
        if action != .shift { updateAutoShift() }
    }

    private func type(_ text: String, fan: CGFloat) {
        guard !typingLocked else {
            onLockedKey?()
            return
        }
        // Sound and touch first; they're what makes a key feel instant.
        let whitespace = text == " " || text == "\t"
        SoundEngine.shared.play(whitespace ? .space : .key, pan: Float(fan * 2 - 1))
        whitespace ? Haptics.shared.spaceBar() : Haptics.shared.key()

        let storage = paper.textView.textStorage
        let location = storage.length
        let lineBefore = paper.currentLineY
        storage.append(NSAttributedString(string: text, attributes: paper.styler.attributes(at: location)))
        let range = NSRange(location: location, length: (text as NSString).length)

        if paper.currentLineY > lineBefore + 1 {
            // The word ran past the margin and wrapped: the carriage returns on its own.
            SoundEngine.shared.play(.carriageReturn, gain: 0.55)
            paper.syncCarriage(.carriageReturn(slideDuration * 0.8))
            bellRungOnLine = false
        } else {
            paper.syncCarriage(.step)
        }
        paper.strike(fan: fan, character: text, at: range)
        ringMarginBellIfNeeded()
        didEdit()
        if whitespace { onPause?(false) }
    }

    private func carriageReturn() {
        let storage = paper.textView.textStorage
        if settings.bellOnReturn && !bellRungOnLine {
            SoundEngine.shared.play(.bell, gain: 0.8)
        }
        SoundEngine.shared.play(.carriageReturn)
        let slide = slideDuration
        Haptics.shared.carriageReturn(slide: slide)
        storage.append(NSAttributedString(string: "\n", attributes: paper.styler.attributes(at: storage.length)))
        paper.syncCarriage(.carriageReturn(slide))
        bellRungOnLine = false
        didEdit()
        onPause?(true)
    }

    private func deleteBackward() {
        let storage = paper.textView.textStorage
        guard storage.length > 0 else {
            SoundEngine.shared.play(.backspace, gain: 0.5)
            return
        }
        SoundEngine.shared.play(.backspace)
        Haptics.shared.key()
        let text = storage.string as NSString
        let last = text.rangeOfComposedCharacterSequence(at: storage.length - 1)
        let wasNewline = text.substring(with: last) == "\n"
        storage.deleteCharacters(in: last)
        paper.syncCarriage(wasNewline ? .snap : .back)
        paper.textView.refreshStrikes()
        didEdit()
    }

    /// Typewriter mode: type an x over the last character instead of erasing it.
    private func strikeOut() {
        let storage = paper.textView.textStorage
        let text = storage.string as NSString
        var i = text.length - 1
        // Back over the line until there's an unstruck character; never past the start of the line.
        while i >= 0 {
            let c = text.character(at: i)
            if c == 0x0A { break }
            if !Self.isSpace(c), storage.attribute(.carriageStrike, at: i, effectiveRange: nil) == nil { break }
            i -= 1
        }
        guard i >= 0, text.character(at: i) != 0x0A else {
            SoundEngine.shared.play(.backspace, gain: 0.5)
            return
        }
        let range = text.rangeOfComposedCharacterSequence(at: i)
        SoundEngine.shared.play(.strike, pan: 0.6)
        Haptics.shared.key()
        storage.addAttribute(.carriageStrike, value: true, range: range)
        paper.textView.refreshStrikes()
        paper.strike(fan: 0.6, character: "x", at: range)
        didEdit()
    }

    private func tapShift() {
        let now = Date()
        switch shift {
        case .off:
            setShift(.once)
        case .once:
            setShift(now.timeIntervalSince(lastShiftTap) < 0.4 ? .locked : .off)
        case .locked:
            setShift(.off)
        }
        lastShiftTap = now
        SoundEngine.shared.play(.shift)
        Haptics.shared.key()
    }

    private func setShift(_ state: KeyboardView.ShiftState, automatic: Bool = false) {
        shift = state
        shiftIsAutomatic = automatic && state == .once
        keyboard.shiftState = state
    }

    /// Lights shift at the start of a sentence (page start, after a return, or after ". " "? " "! "), and turns an
    /// automatic shift back off if the writer moves on without using it. A shift the writer set is never touched.
    private func updateAutoShift() {
        guard settings.autoCapitalize, shift != .locked, shift == .off || shiftIsAutomatic else { return }
        let text = paper.textView.textStorage.string
        var wantsCapital = false
        var sawSpace = false
        for character in text.reversed() {
            if character == " " || character == "\t" {
                sawSpace = true
                continue
            }
            wantsCapital = character == "\n" || (sawSpace && ".?!".contains(character))
            break
        }
        if text.isEmpty { wantsCapital = true }
        if wantsCapital, shift == .off {
            setShift(.once, automatic: true)
        } else if !wantsCapital, shiftIsAutomatic {
            setShift(.off)
        }
    }

    private func hardwareInsert(_ text: String) {
        for character in text {
            switch character {
            case "\n", "\r": press(.carriageReturn, fan: 0.95)
            case "\t": press(.tab, fan: 0.05)
            case " ": press(.space, fan: 0.5)
            default:
                markTyping()
                type(String(character), fan: KeyLayout.fan(for: character))
            }
        }
    }

    private func ringMarginBellIfNeeded() {
        guard settings.marginBell, !bellRungOnLine, paper.currentColumn >= paper.metrics.bellColumn else { return }
        bellRungOnLine = true
        SoundEngine.shared.play(.bell)
        Haptics.shared.bell()
        onMarginBell?()
    }

    private var slideDuration: TimeInterval {
        switch settings.carriage {
        case .classic: 0.42
        case .gentle: 0.3
        case .fixed: 0.22
        }
    }

    private func markTyping() {
        if !isTyping { isTyping = true }
        typingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.isTyping = false }
        typingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }

    /// Brings the controls back, for a tap on the paper.
    func wakeControls() {
        typingWork?.cancel()
        if isTyping { isTyping = false }
    }

    private static func isSpace(_ c: unichar) -> Bool {
        c == 0x20 || c == 0x09 || c == 0x0A
    }

    // MARK: Saving

    private func didEdit() {
        let blank = paper.textView.textStorage.length == 0
        if blank != isBlank { isBlank = blank }
        scheduleSave()
        scheduleSpellCheck()
    }

    private func scheduleSave() {
        // Typing without pause would keep pushing the debounce back; never go more than a few seconds unsaved.
        if Date().timeIntervalSince(lastSave) > 4 {
            save()
            return
        }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    /// Writes the paper back to the page model.
    func save() {
        saveWork?.cancel()
        lastSave = Date()
        guard let page else { return }
        let local = PageText(paper.textView.textStorage)
        let stored = PageText(page)
        if stored != lastSynced, local != lastSynced {
            // Both this device and another one changed the page since they last agreed. Keep both: the other
            // version becomes its own page, and this one carries on.
            keepOtherDevicesCopy(of: page, stored)
        } else if stored != lastSynced {
            // Only the other device changed it; nothing typed here to save.
            lastSynced = stored
            return
        }
        guard local != stored else { return }
        page.body = local.body
        page.strikes = local.strikes
        page.underlines = local.underlines
        page.modifiedAt = Date()
        page.wordCount = TextExport.wordCount(body: local.body, strikes: local.strikes)
        lastSynced = local
        wordCount = page.wordCount
        // Words written today are new words beyond the most this page has held since it was opened, so
        // deleting and retyping, or x-ing out, never pads the goal.
        if page.wordCount > wordPeak {
            if stats.addWords(page.wordCount - wordPeak) { goalReachedAt = Date() }
            wordPeak = page.wordCount
        }
        stats.save()
        if let context, Date().timeIntervalSince(lastVersionAt) > 10 * 60 {
            lastVersionAt = Date()
            PageHistory.snapshot(page, reason: "Session", in: context, ifOlderThan: 10 * 60)
        }
        try? context?.save()
        onSaved?(page)
    }

    /// Called when synced changes may have arrived. If only the other device changed the open page, show its
    /// version; if both did, keep both.
    func reconcileWithStore() {
        guard let page else { return }
        let stored = PageText(page)
        guard stored != lastSynced else { return }
        let local = PageText(paper.textView.textStorage)
        if local == lastSynced {
            reload(page)
            onSyncNotice?("Updated from your other device")
        } else {
            save()
        }
    }

    private func keepOtherDevicesCopy(of page: Page, _ text: PageText) {
        guard let context else { return }
        let copy = Page(mode: page.mode, paper: page.paper, ink: page.ink)
        copy.title = page.displayTitle + " (other device)"
        copy.body = text.body
        copy.strikes = text.strikes
        copy.underlines = text.underlines
        copy.notebookID = page.notebookID
        copy.wordCount = TextExport.wordCount(body: text.body, strikes: text.strikes)
        context.insert(copy)
        onSyncNotice?("Edited on two devices: the other version is saved as a separate page")
    }

    /// Re-reads the page into the paper without moving it out of the machine.
    private func reload(_ page: Page) {
        let storage = paper.textView.textStorage
        storage.beginEditing()
        storage.setAttributedString(paper.styler.attributedText(body: page.body, strikes: page.strikes, underlines: page.underlines))
        storage.endEditing()
        lastSynced = PageText(page)
        wordPeak = max(wordPeak, page.wordCount)
        wordCount = page.wordCount
        isBlank = storage.length == 0
        paper.textView.refreshStrikes()
        paper.textView.selectedRange = NSRange(location: storage.length, length: 0)
        paper.textView.ensureLayoutNearEnd()
        paper.syncCarriage(.snap)
    }

    /// Puts an older version back. The current text is kept as a version first, so a restore can be undone.
    func restore(_ version: PageVersion) {
        guard let page, let context, version.pageID == page.id else { return }
        save()
        PageHistory.snapshot(page, reason: "Before restore", in: context, ifOlderThan: 0)
        page.body = version.body
        page.strikeData = version.strikeData
        page.underlineData = version.underlineData
        page.wordCount = version.wordCount
        page.modifiedAt = Date()
        try? context.save()
        reload(page)
        onSaved?(page)
    }

    // MARK: Underlining

    /// Types underscores over the word at `index`, or takes them away if it's already underlined.
    func toggleUnderline(wordAt index: Int) {
        let storage = paper.textView.textStorage
        guard let range = Self.wordRange(in: storage.string as NSString, at: index) else { return }
        toggleUnderline(range)
    }

    func toggleUnderline(_ range: NSRange) {
        let storage = paper.textView.textStorage
        let range = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
        guard range.length > 0 else { return }
        var allUnderlined = true
        storage.enumerateAttribute(.carriageUnderline, in: range) { value, _, stop in
            if value == nil { allUnderlined = false; stop.pointee = true }
        }
        storage.beginEditing()
        if allUnderlined {
            paper.styler.removeUnderline(from: storage, range: range)
        } else {
            paper.styler.addUnderline(to: storage, range: range)
        }
        storage.endEditing()
        // The sound of backing up and typing a row of underscores.
        let count = min(range.length, 12)
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.045) {
                SoundEngine.shared.play(i == 0 ? .backspace : .key, gain: 0.8)
                Haptics.shared.key()
            }
        }
        didEdit()
    }

    /// The word around `index`: letters, digits and apostrophes.
    static func wordRange(in text: NSString, at index: Int) -> NSRange? {
        guard text.length > 0 else { return nil }
        let isWord: (unichar) -> Bool = { c in
            guard let scalar = Unicode.Scalar(c) else { return false }
            return CharacterSet.alphanumerics.contains(scalar) || c == 0x27 || c == 0x2019
        }
        var i = min(max(index, 0), text.length - 1)
        if !isWord(text.character(at: i)), i > 0, isWord(text.character(at: i - 1)) { i -= 1 }
        guard isWord(text.character(at: i)) else { return nil }
        var start = i, end = i + 1
        while start > 0, isWord(text.character(at: start - 1)) { start -= 1 }
        while end < text.length, isWord(text.character(at: end)) { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    // MARK: Spell check

    private func scheduleSpellCheck() {
        spellWork?.cancel()
        guard settings.spellCheck else {
            SpellUnderliner.clear(paper.textView.textStorage)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.paper.textView.markedTextRange == nil else { return }
            SpellUnderliner.underline(self.paper.textView.textStorage)
        }
        spellWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    func refreshSpellCheck() { scheduleSpellCheck() }

    // MARK: System keyboard editing

    fileprivate func shouldChange(range: NSRange, replacement: String) -> Bool {
        let storage = paper.textView.textStorage
        if paper.configuration.presentation == .typing { return false }
        if typingLocked, !replacement.isEmpty {
            onLockedKey?()
            return false
        }
        // Composing (Japanese, Chinese, Korean and the like) replaces marked text step by step; let it through.
        let composing = paper.textView.markedTextRange != nil
        if mode == .typewriter, range.length > 0, !composing {
            // No delete in Typewriter mode, even with the system keyboard: strike the text instead.
            let safe = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
            storage.addAttribute(.carriageStrike, value: true, range: safe)
            SoundEngine.shared.play(.strike)
            paper.textView.refreshStrikes()
            if replacement.isEmpty {
                // Step back over what was struck, so holding delete keeps striking backwards.
                paper.textView.selectedRange = NSRange(location: safe.location, length: 0)
            } else {
                let at = NSMaxRange(safe)
                storage.insert(NSAttributedString(string: replacement, attributes: paper.styler.attributes(at: at)), at: at)
                paper.textView.selectedRange = NSRange(location: at + (replacement as NSString).length, length: 0)
            }
            didEdit()
            return false
        }
        if !replacement.isEmpty {
            SoundEngine.shared.play(replacement == "\n" ? .carriageReturn : (replacement == " " ? .space : .key), gain: 0.7)
        } else {
            SoundEngine.shared.play(.backspace, gain: 0.7)
        }
        pendingEdit = NSRange(location: range.location, length: (replacement as NSString).length)
        return true
    }

    /// New typing never inherits an x or a spelling underline from the character before the cursor.
    fileprivate func didChangeSelection() {
        paper.textView.typingAttributes = paper.styler.baseAttributes
    }

    fileprivate func didChangeText() {
        let textView = paper.textView
        if textView.markedTextRange == nil, let edit = pendingEdit {
            let storage = textView.textStorage
            let paragraph = (storage.string as NSString).paragraphRange(for: NSIntersectionRange(edit, NSRange(location: 0, length: storage.length)))
            let selection = textView.selectedRange
            storage.beginEditing()
            paper.styler.style(storage, range: paragraph)
            storage.endEditing()
            textView.selectedRange = selection
            pendingEdit = nil
        }
        textView.typingAttributes = paper.styler.baseAttributes
        textView.refreshStrikes()
        didEdit()
    }
}

/// Routes the text view's delegate calls to the engine (the engine itself isn't an NSObject).
private final class PaperTextDelegate: NSObject, UITextViewDelegate {
    unowned let engine: TypewriterEngine

    init(engine: TypewriterEngine) {
        self.engine = engine
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        engine.shouldChange(range: range, replacement: text)
    }

    func textViewDidChange(_ textView: UITextView) {
        engine.didChangeText()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        engine.didChangeSelection()
    }

    /// Adds Underline to the edit menu when text is selected with the system keyboard.
    func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard range.length > 0 else { return nil }
        let engine = self.engine
        let underline = UIAction(title: "Underline", image: UIImage(systemName: "underline")) { [weak engine] _ in
            engine?.toggleUnderline(range)
        }
        return UIMenu(children: [underline] + suggestedActions)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        (scrollView as? PaperTextView)?.refreshStrikes()
    }
}

extension KeyLayout {
    /// Roughly where a character's key sits on the keyboard, for the sound's pan and the typebar's angle.
    static func fan(for character: Character) -> CGFloat {
        let s = String(character).lowercased()
        for row in rows {
            let total = row.units
            var x = row.offset
            for key in row.keys {
                if case let .character(lower, shifted) = key.action, lower == s || shifted == String(character) {
                    return (x + key.units / 2) / max(total, 1)
                }
                x += key.units
            }
        }
        return 0.5
    }
}
