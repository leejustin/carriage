import Foundation
import Testing
@testable import Carriage
import UIKit

/// Renders the keyboard to PNGs for a visual check. Runs only when `TEST_RUNNER_KEYBOARD_SNAPSHOT_DIR` is passed to
/// `xcodebuild test` (it reaches the test as `KEYBOARD_SNAPSHOT_DIR`), so normal test runs skip it.
@MainActor
@Suite struct KeyboardSnapshotTests {
    nonisolated static let outputDir = ProcessInfo.processInfo.environment["KEYBOARD_SNAPSHOT_DIR"]

    struct Deck {
        let name: String
        let size: CGSize
        let style: KeyboardStyle
    }

    static let decks: [Deck] = [
        Deck(name: "wide-halffolded", size: CGSize(width: 860, height: 320), style: .full),
        Deck(name: "wide-openflat", size: CGSize(width: 700, height: 560), style: .full),
        Deck(name: "compact", size: CGSize(width: 393, height: 260), style: .full),
        Deck(name: "split", size: CGSize(width: 860, height: 320), style: .split),
    ]

    @Test(.enabled(if: outputDir != nil)) func renderKeyboards() throws {
        let dir = URL(fileURLWithPath: Self.outputDir!)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let states: [(String, KeyboardView.ShiftState)] = [("shift-off", .off), ("shift-on", .once), ("shift-locked", .locked)]
        for deck in Self.decks {
            for mode in [TypingMode.typewriter, .free] {
                for (shiftName, shift) in states {
                    let view = KeyboardView(frame: CGRect(origin: .zero, size: deck.size))
                    view.style = deck.style
                    view.mode = mode
                    view.shiftState = shift
                    view.setNeedsLayout()
                    view.layoutIfNeeded()
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = 3
                    let image = UIGraphicsImageRenderer(size: deck.size, format: format).image { ctx in
                        view.layer.render(in: ctx.cgContext)
                    }
                    let url = dir.appendingPathComponent("\(deck.name)-\(mode.rawValue)-\(shiftName).png")
                    try #require(image.pngData()).write(to: url)
                }
            }
        }
    }
}
