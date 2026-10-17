import UIKit

/// A short tap per key and a heavier thunk on return. Generators are created once and kept prepared.
final class Haptics {
    static let shared = Haptics()

    var isEnabled = true

    private let tap = UIImpactFeedbackGenerator(style: .light)
    private let space = UIImpactFeedbackGenerator(style: .soft)
    private let thunk = UIImpactFeedbackGenerator(style: .heavy)
    private let stop = UIImpactFeedbackGenerator(style: .rigid)
    private let notice = UINotificationFeedbackGenerator()

    private init() {}

    func prepare() {
        guard isEnabled else { return }
        tap.prepare()
        thunk.prepare()
    }

    func key() {
        guard isEnabled else { return }
        tap.impactOccurred(intensity: 0.62)
        tap.prepare()
    }

    func spaceBar() {
        guard isEnabled else { return }
        space.impactOccurred(intensity: 0.7)
        space.prepare()
    }

    /// The lever, then the carriage hitting its stop when the slide finishes.
    func carriageReturn(slide: TimeInterval) {
        guard isEnabled else { return }
        thunk.impactOccurred(intensity: 0.85)
        stop.prepare()
        DispatchQueue.main.asyncAfter(deadline: .now() + slide) { [self] in
            stop.impactOccurred(intensity: 1)
            thunk.prepare()
        }
    }

    func bell() {
        guard isEnabled else { return }
        notice.notificationOccurred(.success)
    }
}
