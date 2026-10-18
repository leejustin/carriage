import AppIntents
import Observation
import SwiftUI

/// Hands actions from Siri, Shortcuts and widget taps to the running app.
@Observable
final class IntentRouter {
    static let shared = IntentRouter()

    enum Action: String {
        case newSheet = "new"
        case journal
        case focus
    }

    var pending: Action?

    private init() {}

    /// Widget taps arrive as `carriage://new`, `carriage://journal` or `carriage://focus`.
    static func handle(_ url: URL, model: AppModel) {
        guard url.scheme == "carriage", let action = Action(rawValue: url.host() ?? "") else { return }
        perform(action, model: model)
    }

    static func perform(_ action: Action, model: AppModel) {
        shared.pending = nil
        model.showLibrary = false
        model.showSettings = false
        switch action {
        case .newSheet:
            model.newSheet()
        case .journal:
            model.openTodaysJournal()
        case .focus:
            if !model.focusMode.isOn { model.toggleFocus() }
        }
    }
}

struct NewSheetIntent: AppIntent {
    static let title: LocalizedStringResource = "New Sheet"
    static let description = IntentDescription("Feeds a fresh sheet into Carriage.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.pending = .newSheet
        return .result()
    }
}

struct StartWritingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Writing in Focus"
    static let description = IntentDescription("Opens Carriage with everything but the page cleared away.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.pending = .focus
        return .result()
    }
}

struct TodaysJournalIntent: AppIntent {
    static let title: LocalizedStringResource = "Today's Journal Page"
    static let description = IntentDescription("Opens today's journal page, starting it if it's the first visit today.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.pending = .journal
        return .result()
    }
}

struct WordsTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Words Written Today"
    static let description = IntentDescription("How many words you've typed in Carriage today.")

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let defaults = UserDefaults(suiteName: SharedStats.suite)
        let today = defaults?.string(forKey: "day") == WritingDay.key(for: .now)
        let words = today ? (defaults?.integer(forKey: "wordsToday") ?? 0) : 0
        let goal = defaults?.integer(forKey: "goal") ?? 0
        let line: String
        if goal > 0 {
            line = words >= goal ? "\(words) words today. Goal met." : "\(words) of \(goal) words today."
        } else {
            line = "\(words) words today."
        }
        return .result(value: words, dialog: IntentDialog(stringLiteral: line))
    }
}

struct CarriageShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartWritingIntent(), phrases: ["Start writing in \(.applicationName)", "Focus in \(.applicationName)"],
                    shortTitle: "Start Writing", systemImageName: "moon")
        AppShortcut(intent: NewSheetIntent(), phrases: ["New sheet in \(.applicationName)", "Feed a sheet into \(.applicationName)"],
                    shortTitle: "New Sheet", systemImageName: "doc.badge.plus")
        AppShortcut(intent: TodaysJournalIntent(), phrases: ["Open today's journal in \(.applicationName)", "Journal in \(.applicationName)"],
                    shortTitle: "Today's Journal", systemImageName: "book.closed")
        AppShortcut(intent: WordsTodayIntent(), phrases: ["How many words have I written in \(.applicationName)", "Words today in \(.applicationName)"],
                    shortTitle: "Words Today", systemImageName: "textformat.123")
    }
}
