import Foundation
import SwiftData

/// One sheet of paper. Stored as plain text plus style settings, so it syncs small and exports cleanly.
///
/// Every property has a default and nothing is unique, as CloudKit-backed SwiftData requires.
@Model
final class Page {
    var id: UUID = UUID()
    var title: String = ""
    var body: String = ""
    /// Characters struck through with x, as UTF-16 ranges into `body`. See `StrikeRanges`.
    var strikeData: Data?
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    /// False while the sheet is a draft; true once it's been pulled from the machine and filed.
    var isFiled: Bool = false
    var modeRaw: String = TypingMode.free.rawValue
    var paperRaw: String = PaperStyle.bond.rawValue
    var inkRaw: String = InkStyle.black.rawValue
    /// Seeds the per-character ink texture, so a page looks the same every time it's opened.
    var inkSeed: Int = Int.random(in: 1...Int(Int32.max))
    var wordCount: Int = 0
    /// Set when the page is moved to the wastebasket; it's emptied after 30 days.
    var trashedAt: Date?

    init(mode: TypingMode = .free, paper: PaperStyle = .bond, ink: InkStyle = .black) {
        modeRaw = mode.rawValue
        paperRaw = paper.rawValue
        inkRaw = ink.rawValue
    }

    var mode: TypingMode {
        get { TypingMode(rawValue: modeRaw) ?? .free }
        set { modeRaw = newValue.rawValue }
    }

    var paper: PaperStyle {
        get { PaperStyle(rawValue: paperRaw) ?? .bond }
        set { paperRaw = newValue.rawValue }
    }

    var ink: InkStyle {
        get { InkStyle(rawValue: inkRaw) ?? .black }
        set { inkRaw = newValue.rawValue }
    }

    var strikes: [NSRange] {
        get { StrikeRanges.decode(strikeData) }
        set { strikeData = StrikeRanges.encode(newValue) }
    }

    /// The title to show: the one the writer gave, or the first line typed.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let firstLine = TextExport.plainText(body: body, strikes: strikes)
            .split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if firstLine.isEmpty { return "Blank sheet" }
        return firstLine.count > 48 ? String(firstLine.prefix(47)) + "…" : firstLine
    }
}

/// Words written on one calendar day, for goals and streaks.
@Model
final class WritingDay {
    /// `yyyy-MM-dd` in the writer's calendar when the words were typed.
    var day: String = ""
    var words: Int = 0
    var goal: Int = 0

    init(day: String, words: Int = 0, goal: Int = 0) {
        self.day = day
        self.words = words
        self.goal = goal
    }

    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Packs strike ranges as pairs of integers in a compact JSON array.
nonisolated enum StrikeRanges {
    static func encode(_ ranges: [NSRange]) -> Data? {
        guard !ranges.isEmpty else { return nil }
        let flat = merge(ranges).flatMap { [$0.location, $0.length] }
        return try? JSONEncoder().encode(flat)
    }

    static func decode(_ data: Data?) -> [NSRange] {
        guard let data, let flat = try? JSONDecoder().decode([Int].self, from: data), flat.count % 2 == 0 else { return [] }
        return stride(from: 0, to: flat.count, by: 2).map { NSRange(location: flat[$0], length: flat[$0 + 1]) }
    }

    /// Sorts and joins touching or overlapping ranges.
    static func merge(_ ranges: [NSRange]) -> [NSRange] {
        let sorted = ranges.filter { $0.length > 0 }.sorted { $0.location < $1.location }
        var out: [NSRange] = []
        for range in sorted {
            if let last = out.last, range.location <= NSMaxRange(last) {
                out[out.count - 1] = NSRange(location: last.location, length: max(NSMaxRange(last), NSMaxRange(range)) - last.location)
            } else {
                out.append(range)
            }
        }
        return out
    }
}
