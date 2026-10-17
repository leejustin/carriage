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

    func save() {
        try? context?.save()
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
