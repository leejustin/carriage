#if DEBUG
import Foundation
import SwiftData

/// Sample pages for screenshots and for checking layouts. Only in debug builds, only with `-seedDemo`.
enum DemoContent {
    static func seedIfRequested(context: ModelContext, settings: AppSettings) {
        if ProcessInfo.processInfo.arguments.contains("-seedLongPage"), (try? context.fetchCount(FetchDescriptor<Page>())) == 0 {
            // About 20,000 words with an x-out every so often, for checking typing stays quick on a long page.
            let paragraph = "The rain had been going since Tuesday. Mara set the kettle on, fed a clean sheet into the old machine and sat with her hands in her lap, listening. Somewhere below, a door closed. The radiator ticked. "
            let page = Page(mode: .typewriter)
            page.title = "Long page"
            var body = ""
            var strikes: [NSRange] = []
            for n in 0..<540 {
                if n % 9 == 0 { strikes.append(NSRange(location: (body as NSString).length + 4, length: 4)) }
                body += paragraph + (n % 3 == 2 ? "\n\n" : "")
            }
            page.body = body
            page.strikes = strikes
            page.wordCount = TextExport.wordCount(body: body, strikes: strikes)
            context.insert(page)
            try? context.save()
            return
        }
        guard ProcessInfo.processInfo.arguments.contains("-seedDemo"),
              (try? context.fetchCount(FetchDescriptor<Page>())) == 0 else { return }

        let filed = Page(mode: .free, paper: .cream, ink: .black)
        filed.title = "Letters to June"
        filed.body = "Dear June,\n\nThe tomatoes came in all at once this year. I have been giving them away to anyone who stands still long enough.\n\nWrite soon,\nH."
        filed.isFiled = true
        filed.modifiedAt = Date().addingTimeInterval(-86_400 * 3)

        let notes = Page(mode: .free, paper: .bond, ink: .black)
        notes.title = "Morning pages"
        notes.body = "Woke before the alarm. Coffee, the window, the slow grey light coming up over the roofs.\n\nThree things to do today: call Dad, finish the chapter, buy stamps."
        notes.modifiedAt = Date().addingTimeInterval(-86_400)

        let story = Page(mode: .typewriter, paper: .bond, ink: .black)
        let typo = "teh "
        let lead = "Chapter One\n\nThe rain had been going since Tuesday. Mara set the kettle on, fed a clean sheet into the old machine and sat with her hands in her lap, listening.\n\nSomewhere below, a door closed. The radiator ticked. She typed the first line slowly, the way her grandmother had taught her: no going back, only forward.\n\nIt was the summer "
        story.body = lead + typo + "the river forgot its banks.\n"
        story.strikes = [NSRange(location: (lead as NSString).length, length: 3)]
        story.wordCount = TextExport.wordCount(body: story.body, strikes: story.strikes)
        story.modifiedAt = Date()

        for page in [filed, notes, story] {
            page.wordCount = TextExport.wordCount(body: page.body, strikes: page.strikes)
            context.insert(page)
        }
        for offset in 0..<9 {
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: .now)!
            context.insert(WritingDay(day: WritingDay.key(for: date), words: [620, 540, 810, 505, 700, 230, 900, 515, 640][offset], goal: 500))
        }
        try? context.save()
    }

    /// Sets up a scene for App Store screenshots: `-screenshotScene library|focus|spread|paywall`.
    static func stageScreenshotScene(_ model: AppModel) {
        guard let scene = UserDefaults.standard.string(forKey: "screenshotScene") else { return }
        UserDefaults.standard.set(true, forKey: "seenOnboarding")
        UserDefaults.standard.set(true, forKey: "seenFocusSetup")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            model.showOnboarding = false
            switch scene {
            case "library": model.showLibrary = true
            case "focus": model.focusMode.toggle()
            case "spread": model.showSpread = true
            case "paywall": model.showPaywall = true
            default: break
            }
        }
    }

    /// Writes the current page's PDF to Documents, for eyeballing the export.
    static func exportPDFIfRequested(_ page: Page?, settings: AppSettings) {
        guard ProcessInfo.processInfo.arguments.contains("-exportDemoPDF"), let page,
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let data = TypedPagePDF.render(PageSnapshot(page), face: settings.typeface, spacing: settings.lineSpacing)
        try? data.write(to: documents.appendingPathComponent("demo.pdf"))
    }
}
#endif
