import CoreHaptics
import UIKit

/// The machine you can feel. Each action is a small Core Haptics pattern built from the same parts as its sound:
/// a key is the slug's crack and then the escapement's tick, a return is the lever, the ratchet running down the
/// rack and the thunk at the margin stop. Phones without Core Haptics get the plain feedback generators.
final class Haptics {
    static let shared = Haptics()

    var isEnabled = true

    private var engine: CHHapticEngine?
    private var patterns: [Kind: CHHapticPattern] = [:]
    private var returnSlide: TimeInterval = -1

    private let tap = UIImpactFeedbackGenerator(style: .light)
    private let space = UIImpactFeedbackGenerator(style: .soft)
    private let thunk = UIImpactFeedbackGenerator(style: .heavy)
    private let stop = UIImpactFeedbackGenerator(style: .rigid)
    private let notice = UINotificationFeedbackGenerator()

    private enum Kind: Hashable { case key, keyUp, space, bell, feed, release, carriage }

    private init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics, let engine = try? CHHapticEngine() else { return }
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = true
        // Come back by ourselves after the system stops or resets the engine (audio interruptions, backgrounding).
        engine.resetHandler = { [weak engine] in try? engine?.start() }
        engine.stoppedHandler = { _ in }
        self.engine = engine
        patterns = [
            .key: Self.pattern([
                .transient(0, intensity: 0.72, sharpness: 0.78),
                .transient(0.028, intensity: 0.22, sharpness: 0.95),
            ]),
            .keyUp: Self.pattern([.transient(0, intensity: 0.16, sharpness: 0.55)]),
            .space: Self.pattern([
                .transient(0, intensity: 0.74, sharpness: 0.32),
                .transient(0.014, intensity: 0.3, sharpness: 0.9),
            ]),
            .bell: Self.pattern([
                .transient(0, intensity: 0.5, sharpness: 1),
                .continuous(0.004, duration: 0.42, intensity: 0.16, sharpness: 1, fade: true),
            ]),
            .feed: Self.ratchet(clicks: 9, over: 0.6, intensity: 0.42),
            .release: Self.pattern([
                .transient(0, intensity: 0.6, sharpness: 0.6),
                .continuous(0.03, duration: 0.32, intensity: 0.2, sharpness: 0.15, fade: true),
            ]),
        ].compactMapValues { $0 }
    }

    func prepare() {
        guard isEnabled else { return }
        if let engine {
            try? engine.start()
        } else {
            tap.prepare()
            thunk.prepare()
        }
    }

    func key() {
        guard isEnabled else { return }
        if play(.key) { return }
        tap.impactOccurred(intensity: 0.62)
        tap.prepare()
    }

    /// The key lever coming back up as the finger lifts: barely there, but it closes the stroke.
    func keyUp() {
        guard isEnabled else { return }
        _ = play(.keyUp)
    }

    func spaceBar() {
        guard isEnabled else { return }
        if play(.space) { return }
        space.impactOccurred(intensity: 0.7)
        space.prepare()
    }

    /// The lever, the ratchet down the rack as the carriage slides, then the carriage hitting its stop.
    func carriageReturn(slide: TimeInterval) {
        guard isEnabled else { return }
        if engine != nil {
            if returnSlide != slide {
                // Built once per slide length (it changes only with the machine or the carriage setting).
                returnSlide = slide
                patterns[.carriage] = Self.carriagePattern(slide: slide)
            }
            if play(.carriage) { return }
        }
        thunk.impactOccurred(intensity: 0.85)
        stop.prepare()
        DispatchQueue.main.asyncAfter(deadline: .now() + slide) { [self] in
            stop.impactOccurred(intensity: 1)
            thunk.prepare()
        }
    }

    func bell() {
        guard isEnabled else { return }
        if play(.bell) { return }
        notice.notificationOccurred(.success)
    }

    /// A fresh sheet ratcheting in around the platen.
    func paperFeed() {
        guard isEnabled else { return }
        _ = play(.feed)
    }

    /// The paper bail lifting and the sheet sliding out.
    func paperRelease() {
        guard isEnabled else { return }
        if play(.release) { return }
        thunk.impactOccurred(intensity: 0.5)
    }

    // MARK: Patterns

    private func play(_ kind: Kind) -> Bool {
        guard let engine, let pattern = patterns[kind] else { return false }
        do {
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
            return true
        } catch {
            // The engine may have been stopped while idle; start it and try once more.
            try? engine.start()
            return (try? engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)) != nil
        }
    }

    private enum Part {
        case transient(TimeInterval, intensity: Float, sharpness: Float)
        case continuous(TimeInterval, duration: TimeInterval, intensity: Float, sharpness: Float, fade: Bool)
    }

    private static func pattern(_ parts: [Part]) -> CHHapticPattern? {
        var events: [CHHapticEvent] = []
        var curves: [CHHapticParameterCurve] = []
        for part in parts {
            switch part {
            case let .transient(time, intensity, sharpness):
                events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                ], relativeTime: time))
            case let .continuous(time, duration, intensity, sharpness, fade):
                events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                ], relativeTime: time, duration: duration))
                if fade {
                    curves.append(CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
                        .init(relativeTime: time, value: 1), .init(relativeTime: time + duration, value: 0),
                    ], relativeTime: 0))
                }
            }
        }
        return try? CHHapticPattern(events: events, parameterCurves: curves)
    }

    /// Clicks that start slow and run faster, like a ratchet being wound.
    private static func ratchet(clicks: Int, over duration: TimeInterval, intensity: Float) -> CHHapticPattern? {
        var parts: [Part] = []
        for i in 0..<clicks {
            let x = Double(i) / Double(max(1, clicks - 1))
            parts.append(.transient(duration * pow(x, 0.8), intensity: intensity * Float(0.7 + 0.3 * x), sharpness: 0.85))
        }
        return pattern(parts)
    }

    private static func carriagePattern(slide: TimeInterval) -> CHHapticPattern? {
        let start = 0.06
        var parts: [Part] = [
            .transient(0, intensity: 0.85, sharpness: 0.35),
            // The platen turning one line: two quick ratchet clicks.
            .transient(0.03, intensity: 0.4, sharpness: 0.9),
            .transient(0.054, intensity: 0.4, sharpness: 0.9),
            // The slide itself, a low rumble under the rack's teeth.
            .continuous(start, duration: slide, intensity: 0.22, sharpness: 0.12, fade: false),
        ]
        var t = start
        while t < start + slide {
            let x = (t - start) / slide
            parts.append(.transient(t, intensity: Float(0.18 + 0.2 * x), sharpness: 0.95))
            t += 1 / (30 + 90 * x)
        }
        parts.append(.transient(start + slide, intensity: 1, sharpness: 0.55))
        return pattern(parts)
    }
}
