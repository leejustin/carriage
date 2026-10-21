#if DEBUG
import AVFoundation
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
        story.body = lead + typo + "the river forgot its banks. The water came up past the mill, past the church steps, past the line her father had painted on the boathouse wall the year she was born.\n\nNobody in the village had seen anything like it, and nobody, afterwards, could agree on how it began.\n"
        story.strikes = [NSRange(location: (lead as NSString).length, length: 3)]
        story.wordCount = TextExport.wordCount(body: story.body, strikes: story.strikes)
        story.modifiedAt = Date()

        for page in [filed, notes, story] {
            page.wordCount = TextExport.wordCount(body: page.body, strikes: page.strikes)
            context.insert(page)
        }
        for offset in 0..<9 {
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: .now)!
            context.insert(WritingDay(day: WritingDay.key(for: date), words: [620, 480, 560, 505, 410, 230, 520, 415, 460][offset], goal: 500))
        }
        try? context.save()
    }

    /// `-laptopPreview`: lay out as a Duo turned on its side, for screenshots on a simulator that can't be turned.
    static let laptopPreview = ProcessInfo.processInfo.arguments.contains("-laptopPreview")

    /// Sets up a scene for App Store screenshots: `-screenshotScene library|focus|paywall`.
    static func stageScreenshotScene(_ model: AppModel) {
        guard let scene = UserDefaults.standard.string(forKey: "screenshotScene") else { return }
        UserDefaults.standard.set(true, forKey: "seenOnboarding")
        UserDefaults.standard.set(true, forKey: "seenFocusSetup")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            model.showOnboarding = false
            switch scene {
            case "library": model.showLibrary = true
            case "focus": model.focusMode.toggle()
            case "paywall": model.showPaywall = true
            case "settings":
                // `-screenshotScene settings`: opens Settings and closes it again three seconds later, for
                // checking what the page looks like after a sheet.
                model.showSettings = true
                if UserDefaults.standard.bool(forKey: "changeSetting") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        model.settings.lineSpacing = model.settings.lineSpacing == .single ? .oneAndHalf : .single
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { model.showSettings = false }
            default: break
            }
        }
    }

    /// `-autoType`: presses keys through the engine, as if typed, to check the margin stop on a simulator.
    @MainActor
    static func autoTypeIfRequested(_ model: AppModel) {
        guard ProcessInfo.processInfo.arguments.contains("-autoType") else { return }
        let text = "The carriage stops at the margin, the way a real machine does, until you send it home again"
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            for character in text {
                let key = String(character)
                model.engine.press(key == " " ? .space : .character(key, shifted: key.uppercased()), fan: 0.5)
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    /// `-exportSounds`: writes a listening demo of every machine and desk sound to Documents/sounds, for hearing
    /// the app where the Simulator's audio can't reach (a remote session).
    static func exportSoundsIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-exportSounds"),
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let folder = documents.appendingPathComponent("sounds")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let rate = 48_000.0
        Task.detached(priority: .utility) {
            for machine in MachineSound.allCases {
                let bank = SoundBankBuilder.build(machine: machine, sampleRate: rate)
                var out = [Float](repeating: 0, count: Int(rate * 9))
                func add(_ kind: SoundKind, at t: Double, take: Int = 0, gain: Float = 1) {
                    guard let takes = bank[kind], !takes.isEmpty else { return }
                    let samples = takes[take % takes.count]
                    let start = Int(t * rate)
                    for (i, v) in samples.enumerated() where start + i < out.count { out[start + i] += v * gain }
                }
                // A typed line with a typist's uneven rhythm, the bell near the end, a key jamming at the
                // margin, then the carriage pushed home and a fresh line started.
                let line = "The rain had been going since Tuesday and"
                var t = 0.4
                var n = 0
                for (i, character) in line.enumerated() {
                    if character == " " { add(.space, at: t, take: n) } else { add(.key, at: t, take: n * 7) }
                    if line.count - i == 7 { add(.bell, at: t + 0.02, gain: 0.9) }
                    t += character == " " ? 0.17 : [0.11, 0.14, 0.09, 0.16, 0.12][n % 5]
                    n += 1
                }
                add(.shift, at: t + 0.15, gain: 0.45)
                add(.shift, at: t + 0.55, gain: 0.45)
                add(.carriageReturn, at: t + 1.1)
                t += 2.0
                for (i, character) in "Mara set the kettle on.".enumerated() {
                    if character == " " { add(.space, at: t, take: i) } else { add(.key, at: t, take: i * 5) }
                    t += character == " " ? 0.16 : 0.12
                }
                add(.paperRelease, at: t + 0.6)
                write(out, rate: rate, to: folder.appendingPathComponent("machine-\(machine.rawValue).wav"))
            }
            for ambience in Ambience.allCases where ambience != .off {
                let generator = AmbienceGenerator()
                generator.prepare(sampleRate: rate)
                generator.target = (ambience, 0.55)
                var out = [Float](repeating: 0, count: Int(rate * 8))
                out.withUnsafeMutableBufferPointer { generator.render(into: $0.baseAddress!, frames: $0.count) }
                write(out, rate: rate, to: folder.appendingPathComponent("desk-\(ambience.rawValue).wav"))
            }
            try? "done".write(to: folder.appendingPathComponent("done.txt"), atomically: true, encoding: .utf8)
        }
    }

    nonisolated private static func write(_ samples: [Float], rate: Double, to url: URL) {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let file = try? AVAudioFile(forWriting: url, settings: format.settings) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let peak = max(1, samples.map(abs).max() ?? 1)
        for i in samples.indices { buffer.floatChannelData![0][i] = samples[i] / peak * 0.9 }
        try? file.write(from: buffer)
    }

    /// Writes the current page's share images to Documents (`-exportShareImages`), for eyeballing them.
    static func exportShareImagesIfRequested(_ page: Page?, settings: AppSettings) {
        guard ProcessInfo.processInfo.arguments.contains("-exportShareImages"), let page,
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        for format in TypedPageImage.Format.allCases {
            let image = TypedPageImage.render(PageSnapshot(page), face: settings.typeface, format: format, finish: settings.finish, engraving: settings.engraving)
            try? image.pngData()?.write(to: documents.appendingPathComponent("share-\(format).png"))
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
