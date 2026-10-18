import Foundation

/// Today's numbers, shared with the widgets through the app group.
nonisolated enum SharedStats {
    static let suite = "group.com.leejustin.carriage"

    static func write(wordsToday: Int, goal: Int, streak: Int, lastLine: String, date: Date = .now) {
        guard let defaults = UserDefaults(suiteName: suite) else { return }
        defaults.set(wordsToday, forKey: "wordsToday")
        defaults.set(goal, forKey: "goal")
        defaults.set(streak, forKey: "streak")
        defaults.set(lastLine, forKey: "lastLine")
        defaults.set(WritingDay.key(for: date), forKey: "day")
    }
}
