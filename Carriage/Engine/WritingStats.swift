import Foundation
import Observation
import SwiftData

/// Daily word goals and streaks.
@Observable
final class WritingStats {
    private(set) var wordsToday = 0
    private(set) var streak = 0
    var goal: Int {
        didSet {
            today?.goal = goal
            recomputeStreak()
        }
    }

    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var today: WritingDay?
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date

    init(goal: Int, calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.goal = goal
        self.calendar = calendar
        self.now = now
    }

    func attach(_ context: ModelContext) {
        self.context = context
        refresh()
    }

    /// Re-reads today's record, for launch and for the day rolling over while the app is open.
    func refresh() {
        let key = WritingDay.key(for: now(), calendar: calendar)
        if today?.day != key {
            today = fetchDay(key)
        }
        wordsToday = today?.words ?? 0
        recomputeStreak()
    }

    /// Adds words written. Returns true when this addition reaches the day's goal.
    @discardableResult
    func addWords(_ count: Int) -> Bool {
        let key = WritingDay.key(for: now(), calendar: calendar)
        if today?.day != key {
            today = fetchDay(key) ?? {
                let day = WritingDay(day: key, goal: goal)
                context?.insert(day)
                return day
            }()
        }
        guard let today else { return false }
        let before = today.words
        today.words += count
        today.goal = goal
        wordsToday = today.words
        let reached = goal > 0 && before < goal && today.words >= goal
        if reached { recomputeStreak() }
        return reached
    }

    /// Adds time spent typing to today, for words per minute.
    func addActiveSeconds(_ seconds: TimeInterval) {
        guard seconds > 0 else { return }
        todayRecord().activeSeconds += seconds
    }

    private func todayRecord() -> WritingDay {
        let key = WritingDay.key(for: now(), calendar: calendar)
        if let today, today.day == key { return today }
        let day = fetchDay(key) ?? {
            let day = WritingDay(day: key, goal: goal)
            context?.insert(day)
            return day
        }()
        today = day
        return day
    }

    func save() {
        try? context?.save()
        onChange?()
    }

    /// Called after stats are saved, for widgets.
    @ObservationIgnored var onChange: (() -> Void)?

    /// Everything the history screen shows.
    struct Summary {
        var days: [String: (words: Int, seconds: Double, goal: Int)]
        var totalWords: Int
        var daysWritten: Int
        var longestStreak: Int
        var currentStreak: Int
        /// Words per minute across all recorded typing time.
        var wordsPerMinute: Int?
        var bestDay: (date: String, words: Int)?
    }

    func summary() -> Summary {
        let all = (try? context?.fetch(FetchDescriptor<WritingDay>())) ?? []
        var days: [String: (words: Int, seconds: Double, goal: Int)] = [:]
        for d in all {
            let existing = days[d.day] ?? (0, 0, 0)
            days[d.day] = (existing.words + d.words, existing.seconds + d.activeSeconds, max(existing.goal, d.goal))
        }
        let totalWords = days.values.reduce(0) { $0 + $1.words }
        let totalSeconds = days.values.reduce(0) { $0 + $1.seconds }
        let written = days.filter { $0.value.words > 0 }
        // Longest run of consecutive days with any writing that met the goal (or any writing, with no goal).
        let metKeys = Set(days.filter { $0.value.words > 0 && (goal == 0 || $0.value.words >= ($0.value.goal > 0 ? $0.value.goal : goal)) }.keys)
        var longest = 0
        for key in metKeys {
            guard let date = Self.date(from: key, calendar: calendar),
                  let previous = calendar.date(byAdding: .day, value: -1, to: date),
                  !metKeys.contains(WritingDay.key(for: previous, calendar: calendar)) else { continue }
            var run = 0
            var cursor = date
            while metKeys.contains(WritingDay.key(for: cursor, calendar: calendar)) {
                run += 1
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
            longest = max(longest, run)
        }
        let best = written.max { $0.value.words < $1.value.words }
        return Summary(
            days: days,
            totalWords: totalWords,
            daysWritten: written.count,
            longestStreak: longest,
            currentStreak: streak,
            wordsPerMinute: totalSeconds > 120 ? Int((Double(totalWords) / (totalSeconds / 60)).rounded()) : nil,
            bestDay: best.map { ($0.key, $0.value.words) }
        )
    }

    static func date(from key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Days in a row the goal was met, counting today only once it's met.
    private func recomputeStreak() {
        guard let context else { streak = 0; return }
        let days = (try? context.fetch(FetchDescriptor<WritingDay>())) ?? []
        streak = Self.streak(days: days.map { ($0.day, $0.words, $0.goal) }, today: now(), goal: goal, calendar: calendar)
    }

    static func streak(days: [(day: String, words: Int, goal: Int)], today: Date, goal: Int, calendar: Calendar) -> Int {
        guard goal > 0 else { return 0 }
        var met: [String: Bool] = [:]
        for d in days {
            let target = d.goal > 0 ? d.goal : goal
            met[d.day] = (met[d.day] ?? false) || d.words >= target
        }
        var count = 0
        var date = today
        // Today counts if it's met; if not yet, the streak still stands from yesterday.
        if met[WritingDay.key(for: date, calendar: calendar)] != true {
            date = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        }
        while met[WritingDay.key(for: date, calendar: calendar)] == true {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: date) else { break }
            date = previous
        }
        return count
    }

    private func fetchDay(_ key: String) -> WritingDay? {
        var descriptor = FetchDescriptor<WritingDay>(predicate: #Predicate { $0.day == key })
        descriptor.fetchLimit = 1
        return try? context?.fetch(descriptor).first
    }

    /// The last `count` days, oldest first, for the little bar chart in the library.
    func recentDays(_ count: Int = 14) -> [(date: Date, words: Int, met: Bool)] {
        let all = (try? context?.fetch(FetchDescriptor<WritingDay>())) ?? []
        var byDay: [String: (Int, Int)] = [:]
        for d in all {
            let existing = byDay[d.day] ?? (0, 0)
            byDay[d.day] = (existing.0 + d.words, max(existing.1, d.goal))
        }
        let today = now()
        return (0..<count).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let entry = byDay[WritingDay.key(for: date, calendar: calendar)] ?? (0, 0)
            let target = entry.1 > 0 ? entry.1 : goal
            return (date, entry.0, target > 0 && entry.0 >= target)
        }
    }
}
