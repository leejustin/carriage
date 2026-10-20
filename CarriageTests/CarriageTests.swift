import CoreGraphics
import Foundation
import FoldKit
import SwiftData
import Testing
@testable import Carriage

@Suite struct ExportTests {
    @Test func plainTextDropsStruckWordsAndTheirGap() {
        // "the dgo dog" with "dgo" struck reads "the dog".
        let body = "the dgo dog"
        #expect(TextExport.plainText(body: body, strikes: [NSRange(location: 4, length: 3)]) == "the dog")
    }

    @Test func plainTextKeepsUnstruckText() {
        #expect(TextExport.plainText(body: "hello\nworld", strikes: []) == "hello\nworld")
    }

    @Test func strikeAtLineStartDoesNotLeaveALeadingSpace() {
        #expect(TextExport.plainText(body: "teh cat", strikes: [NSRange(location: 0, length: 3)]) == "cat")
    }

    @Test func markdownWrapsStruckTextAndEscapes() {
        let md = TextExport.markdown(title: "Notes", body: "a *star* dgo dog", strikes: [NSRange(location: 9, length: 3)])
        #expect(md.hasPrefix("# Notes\n\n"))
        #expect(md.contains("\\*star\\*"))
        #expect(md.contains("~~dgo~~ dog"))
    }

    @Test func markdownKeepsLineBreaks() {
        let md = TextExport.markdown(title: "", body: "one\ntwo", strikes: [])
        #expect(md == "one  \ntwo\n")
    }

    @Test func wordCountIgnoresStruckWords() {
        #expect(TextExport.wordCount(body: "one two three", strikes: [NSRange(location: 4, length: 3)]) == 2)
    }

    @Test func fileNamesAreSafe() {
        #expect(Exporter.fileName("Draft: a/b?") == "Draft  a b")
        #expect(Exporter.fileName("   ") == "Carriage Page")
    }

    @Test func exportAllWritesOneUniqueFilePerPage() throws {
        var a = PageSnapshot(Page()); a.title = "Letters"; a.body = "one"
        var b = PageSnapshot(Page()); b.title = "Letters"; b.body = "two"
        var c = PageSnapshot(Page()); c.title = "Notes/Draft"; c.body = "three"
        let folder = try Exporter.folder(for: [a, b, c], format: .plainText, face: .courier, spacing: .single)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(names == ["Letters 2.txt", "Letters.txt", "Notes Draft.txt"])
        #expect(try String(contentsOf: folder.appendingPathComponent("Letters 2.txt"), encoding: .utf8) == "two")
    }

    @Test func pdfHasPages() {
        var snapshot = PageSnapshot(Page())
        snapshot.body = String(repeating: "All work and no play makes a dull typist. ", count: 200)
        let data = TypedPagePDF.render(snapshot, face: .courier, spacing: .double)
        #expect(data.count > 1000)
        let document = CGPDFDocument(CGDataProvider(data: data as CFData)!)
        #expect((document?.numberOfPages ?? 0) > 1)
    }
}

@Suite struct StrikeRangeTests {
    @Test func roundTrips() {
        let ranges = [NSRange(location: 4, length: 2), NSRange(location: 10, length: 1)]
        #expect(StrikeRanges.decode(StrikeRanges.encode(ranges)) == ranges)
    }

    @Test func mergesTouchingRanges() {
        let merged = StrikeRanges.merge([NSRange(location: 5, length: 1), NSRange(location: 3, length: 2), NSRange(location: 9, length: 1)])
        #expect(merged == [NSRange(location: 3, length: 3), NSRange(location: 9, length: 1)])
    }

    @Test func emptyEncodesToNil() {
        #expect(StrikeRanges.encode([]) == nil)
        #expect(StrikeRanges.decode(nil).isEmpty)
    }
}

@Suite struct StreakTests {
    let calendar = Calendar(identifier: .gregorian)

    private func day(_ offset: Int, from today: Date) -> String {
        WritingDay.key(for: calendar.date(byAdding: .day, value: offset, to: today)!, calendar: calendar)
    }

    @Test func countsConsecutiveDaysMet() {
        let today = Date(timeIntervalSince1970: 1_792_000_000)
        let days = [(day(0, from: today), 600, 500), (day(-1, from: today), 500, 500), (day(-2, from: today), 800, 500), (day(-4, from: today), 900, 500)]
        #expect(WritingStats.streak(days: days, today: today, goal: 500, calendar: calendar) == 3)
    }

    @Test func todayNotYetMetKeepsYesterdaysStreak() {
        let today = Date(timeIntervalSince1970: 1_792_000_000)
        let days = [(day(0, from: today), 100, 500), (day(-1, from: today), 500, 500), (day(-2, from: today), 500, 500)]
        #expect(WritingStats.streak(days: days, today: today, goal: 500, calendar: calendar) == 2)
    }

    @Test func noGoalNoStreak() {
        #expect(WritingStats.streak(days: [], today: .now, goal: 0, calendar: calendar) == 0)
    }
}

@Suite struct LayoutTests {
    @Test func halfFoldPutsPaperOnTopAndKeysBelow() throws {
        let division = FoldDivision(frame: CGRect(x: 0, y: 461, width: 669, height: 28))
        let fold = FoldState(posture: .halfOpen, hasHinge: true, division: division)
        let layout = DeskLayout.make(size: CGSize(width: 669, height: 951), fold: fold, useSystemKeyboard: false)
        #expect(layout.kind == .hero)
        #expect(layout.paper.maxY <= division.frame.minY)
        let keys = try #require(layout.keyboard)
        #expect(keys.minY >= division.frame.maxY)
        #expect(layout.presentation == .typing)
    }

    @Test func heldLikeABookReadsAsASpreadWithNoKeys() throws {
        let division = FoldDivision(frame: CGRect(x: 461, y: 0, width: 28, height: 669))
        for posture in [FoldPosture.flat, .halfOpen] {
            let fold = FoldState(posture: posture, hasHinge: true, division: division)
            let layout = DeskLayout.make(size: CGSize(width: 951, height: 669), fold: fold, useSystemKeyboard: false)
            #expect(layout.kind == .book)
            #expect(layout.keyboard == nil)
            #expect(layout.paper.maxX <= 461)
            #expect(try #require(layout.facing).minX >= 489)
        }
    }

    @Test func closedIsForReadingAndEditing() {
        let layout = DeskLayout.make(size: CGSize(width: 390, height: 844), fold: FoldState(posture: .closed, hasHinge: true), useSystemKeyboard: false)
        #expect(layout.kind == .closed)
        #expect(layout.keyboard == nil)
        #expect(layout.presentation == .editing)
    }

    @Test func hardwareKeyboardHidesKeys() {
        let layout = DeskLayout.make(size: CGSize(width: 390, height: 844), fold: FoldState(hardwareKeyboard: true), useSystemKeyboard: false)
        #expect(layout.kind == .hardware)
        #expect(layout.keyboard == nil)
        #expect(layout.paper.size == CGSize(width: 390, height: 844))
        #expect(layout.presentation == .typing)
    }

    @Test func regularPhoneStacksPaperOverSmallerKeys() throws {
        let layout = DeskLayout.make(size: CGSize(width: 393, height: 852), fold: .regular, useSystemKeyboard: false)
        #expect(layout.kind == .regular)
        let keys = try #require(layout.keyboard)
        #expect(keys.height < 852 / 2)
        #expect(layout.paper.maxY == keys.minY)
    }

    @Test func systemKeyboardSettingWins() {
        let layout = DeskLayout.make(size: CGSize(width: 393, height: 852), fold: FoldState(hardwareKeyboard: true), useSystemKeyboard: true)
        #expect(layout.kind == .systemKeyboard)
        #expect(layout.presentation == .editing)
    }
}

@Suite struct SynthTests {
    @Test(arguments: MachineSound.allCases)
    func everyMachineMakesEverySound(machine: MachineSound) {
        let bank = SoundBankBuilder.build(machine: machine, sampleRate: 48_000)
        for kind in SoundKind.allCases {
            let takes = bank[kind] ?? []
            #expect(takes.count == kind.takes * kind.rates.count)
            for take in takes {
                #expect(!take.isEmpty)
                let peak = take.reduce(0) { max($0, abs($1)) }
                #expect(peak > 0.05 && peak <= 1, "\(machine) \(kind) peak \(peak)")
                #expect(!take.contains { $0.isNaN })
            }
        }
    }

    @Test func keyIsShortEnoughToStackWhenTypingFast() {
        let bank = SoundBankBuilder.build(machine: .portable, sampleRate: 48_000)
        let longest = bank[.key]!.map(\.count).max()!
        #expect(Double(longest) / 48_000 < 0.25)
    }
}

@Suite struct KeyLayoutTests {
    @Test(arguments: [KeyLayout.Variant.wide, .compact, .split])
    func everyLetterHasAKey(variant: KeyLayout.Variant) {
        let keys = KeyLayout.rows(variant).flatMap(\.keys)
        let characters = keys.flatMap { key -> [String] in
            if case let .character(lower, shifted) = key.action { return [lower, shifted] }
            return []
        }
        for character in "abcdefghijklmnopqrstuvwxyz0123456789.,?'-!\"" {
            #expect(characters.contains(String(character)), "missing \(character)")
        }
        for action in [KeyAction.space, .carriageReturn, .delete, .shift] {
            #expect(keys.contains { $0.action == action })
        }
    }

    @Test func compactKeysAreAsWideAsTheSystemKeyboards() {
        // On a 402 pt iPhone the system keyboard's letter keys sit about 39 pt apart.
        let pitch = (402 - 12) / (KeyLayout.widestRow(.compact) + 0.15)
        #expect(pitch >= 37)
        #expect(KeyLayout.Variant.forWidth(402) == .compact)
        #expect(KeyLayout.Variant.forWidth(669) == .wide)
    }

    @Test func splitOnlyWhereThereIsRoom() {
        #expect(KeyLayout.Variant.forWidth(669, style: .split) == .split)
        #expect(KeyLayout.Variant.forWidth(852, style: .split) == .split)
        // A portrait phone stays in one piece; halves would be too small to hit.
        #expect(KeyLayout.Variant.forWidth(402, style: .split) == .compact)
        #expect(KeyLayout.blocks(.split).count == 2)
        #expect(KeyLayout.blocks(.split)[0].count == KeyLayout.blocks(.split)[1].count)
    }

    @Test func everyKeyHasAnAccessibilityLabel() {
        for key in KeyLayout.rows.flatMap(\.keys) {
            #expect(!key.action.accessibilityLabel.isEmpty)
        }
    }

    @Test func fanRunsLeftToRight() {
        #expect(KeyLayout.fan(for: "q") < KeyLayout.fan(for: "p"))
        #expect(KeyLayout.fan(for: "a") < 0.3)
    }
}

@Suite struct UnderlineTests {
    @Test func markdownUsesEmphasisForUnderlinesAndKeepsStrikes() {
        // "a big red dog": "big" underlined, "red" struck.
        let md = TextExport.markdown(title: "", body: "a big red dog", strikes: [NSRange(location: 6, length: 3)], underlines: [NSRange(location: 2, length: 3)])
        #expect(md == "a _big_ ~~red~~ dog\n")
    }

    @Test func wordRangeFindsTheWordAroundAnIndex() {
        let text = "Mara's kettle, boiling." as NSString
        #expect(TypewriterEngine.wordRange(in: text, at: 2) == NSRange(location: 0, length: 6))
        #expect(TypewriterEngine.wordRange(in: text, at: 13) == NSRange(location: 7, length: 6))
        #expect(TypewriterEngine.wordRange(in: text, at: 14) == nil)
    }

    @Test func pageTextReadsMarksFromInk() {
        let styler = InkStyler(font: .monospacedSystemFont(ofSize: 12, weight: .regular), ink: .black, paper: .bond, face: .courier,
                               seed: 1, lineSpacing: .single, advance: 7)
        let text = styler.attributedText(body: "one two three", strikes: [NSRange(location: 4, length: 3)], underlines: [NSRange(location: 8, length: 5)])
        let read = PageText(text)
        #expect(read.strikes == [NSRange(location: 4, length: 3)])
        #expect(read.underlines == [NSRange(location: 8, length: 5)])
    }
}

@Suite(.serialized) struct HistoryTests {
    /// Kept alive for the test: a context outlives nothing without its container.
    let container: ModelContainer

    init() throws {
        let schema = Schema([Page.self, WritingDay.self, Notebook.self, PageVersion.self])
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    private func context() throws -> ModelContext {
        ModelContext(container)
    }

    @Test func snapshotsSkipUnchangedTextAndThinOldVersions() throws {
        let context = try context()
        let page = Page()
        page.body = "first"
        context.insert(page)
        PageHistory.snapshot(page, reason: "Opened", in: context, ifOlderThan: 0)
        PageHistory.snapshot(page, reason: "Opened", in: context, ifOlderThan: 0)
        #expect(PageHistory.versions(of: page, in: context).count == 1)
        for n in 0..<(PageHistory.limit + 5) {
            page.body = "edit \(n)"
            PageHistory.snapshot(page, reason: "Session", in: context, ifOlderThan: 0)
        }
        #expect(PageHistory.versions(of: page, in: context).count == PageHistory.limit)
    }

    @Test func summaryCountsTotalsAndLongestStreak() throws {
        let context = try context()
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: .now)
        for (offset, words) in [(0, 600), (-1, 500), (-3, 700), (-4, 800), (-5, 900), (-6, 100)] {
            let date = calendar.date(byAdding: .day, value: offset, to: today)!
            let day = WritingDay(day: WritingDay.key(for: date, calendar: calendar), words: words, goal: 500)
            day.activeSeconds = 600
            context.insert(day)
        }
        let stats = WritingStats(goal: 500, calendar: calendar)
        stats.attach(context)
        let summary = stats.summary()
        #expect(summary.totalWords == 3600)
        #expect(summary.daysWritten == 6)
        #expect(summary.longestStreak == 3)
        #expect(summary.currentStreak == 2)
        #expect(summary.wordsPerMinute == 60)
    }
}

@Suite struct RenderingTests {
    @Test func shareImageIsFourByFive() {
        var snapshot = PageSnapshot(Page())
        snapshot.body = String(repeating: "The rain had been going since Tuesday. ", count: 80)
        let image = TypedPageImage.render(snapshot, face: .courier)
        #expect(image.size == CGSize(width: 1080, height: 1350))
    }

    @Test func spreadPaginatesLongPages() {
        var snapshot = PageSnapshot(Page())
        snapshot.body = String(repeating: "Somewhere below, a door closed. ", count: 300)
        let pages = SpreadRenderer.pages(for: snapshot, size: CGSize(width: 440, height: 640), face: .courier, scale: 1)
        #expect(pages.count > 3)
    }
}
