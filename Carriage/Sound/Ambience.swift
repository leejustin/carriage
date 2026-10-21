import AVFoundation

/// A quiet sound under the keys, for writers who like a room around them.
nonisolated enum Ambience: String, CaseIterable, Identifiable, Codable, Sendable {
    case off, room, rain, fire

    var id: String { rawValue }

    var name: String {
        switch self {
        case .off: "Off"
        case .room: "Quiet room"
        case .rain: "Rain on the window"
        case .fire: "Fireplace"
        }
    }
}

/// Makes the ambience live, sample by sample, on the audio thread: nothing to load, nothing to loop, so it
/// never repeats. Shaped noise for the air, with random drops and crackles on top.
///
/// The main thread only ever sets `target`; the audio thread reads it each buffer and fades towards it, so
/// switching sounds never clicks. A read that races a write just picks up the change one buffer later.
nonisolated final class AmbienceGenerator: @unchecked Sendable {
    /// What to play, and how loud (0 to 1). Written on the main thread.
    var target: (ambience: Ambience, level: Float) = (.off, 0)

    private var current: Ambience = .off
    private var gain: Float = 0
    private var rng = SplitMix64(seed: 0xCA_221A6E)
    // Filter state.
    private var low1 = 0.0, low2 = 0.0, brown = 0.0
    private var hissBand = Biquad.bandpass(center: 3600, q: 0.45, sampleRate: 48_000)
    private var dropBand = Biquad.bandpass(center: 1900, q: 0.9, sampleRate: 48_000)
    private var event = 0.0, eventAmp = 0.0
    private var sampleRate = 48_000.0

    func prepare(sampleRate: Double) {
        self.sampleRate = sampleRate
        hissBand = Biquad.bandpass(center: 3600, q: 0.45, sampleRate: sampleRate)
        dropBand = Biquad.bandpass(center: 1900, q: 0.9, sampleRate: sampleRate)
    }

    func render(into out: UnsafeMutablePointer<Float>, frames: Int) {
        let (wanted, level) = target
        let fade = Float(1 / (0.4 * sampleRate))
        for i in 0..<frames {
            // Fade out before switching sounds, then up to the new level.
            let goal: Float = wanted == current ? level : 0
            gain += max(-fade, min(fade, goal - gain))
            if gain <= 0.0001, wanted != current { current = wanted }
            out[i] = gain > 0.0001 ? Float(sample()) * gain : 0
        }
    }

    private func sample() -> Double {
        let white = rng.signed()
        brown = (brown + white * 0.02) * 0.995
        switch current {
        case .off:
            return 0
        case .room:
            // Still air and a building breathing: very low, very soft.
            low1 += 0.004 * (white - low1)
            low2 += 0.02 * (low1 - low2)
            return low2 * 1.8 + brown * 0.35
        case .rain:
            // A steady hiss, a low wash from the street, and drops landing on the glass.
            let hiss = hissBand.process(white) * 0.11
            low1 += 0.01 * (white - low1)
            if rng.unit() < 55 / sampleRate {
                event = 1
                eventAmp = 0.15 + rng.unit() * 0.5
            }
            event *= exp(-1 / (0.0045 * sampleRate))
            let drop = dropBand.process(white) * event * eventAmp
            return hiss + low1 * 0.6 + drop
        case .fire:
            // The low roar of the logs, and crackles that come in little clusters.
            low1 += 0.006 * (white - low1)
            low2 += 0.03 * (low1 - low2)
            if rng.unit() < (event > 0.2 ? 90 : 5) / sampleRate {
                event = 1
                eventAmp = 0.2 + rng.unit() * 0.8
            }
            event *= exp(-1 / (0.0012 * sampleRate))
            let crackle = white * event * eventAmp * 0.55
            return low2 * 2.4 + brown * 0.5 + crackle
        }
    }
}

/// The audio node that pulls from the generator. Made outside the main actor, so its render block, which runs
/// on the audio thread, isn't tied to it.
nonisolated enum AmbienceNode {
    static func make(format: AVAudioFormat, generator: AmbienceGenerator) -> AVAudioSourceNode {
        generator.prepare(sampleRate: format.sampleRate)
        return AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in buffers {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                generator.render(into: data, frames: Int(frameCount))
            }
            return noErr
        }
    }
}
