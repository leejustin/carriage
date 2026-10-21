import Foundation

/// Every sound the machine makes.
nonisolated enum SoundKind: String, CaseIterable, Sendable {
    case key, strike, space, backspace, shift, bell, carriageReturn, paperFeed, paperRelease

    /// How many distinct takes to synthesize. Each take has its own randomized resonances.
    var takes: Int {
        switch self {
        case .key: 8
        case .strike, .space: 4
        case .backspace, .shift, .bell, .carriageReturn: 2
        case .paperFeed, .paperRelease: 1
        }
    }

    /// Playback-rate copies of each take, so the pitch wanders a little on every press.
    var rates: [Double] {
        switch self {
        case .key, .strike: [0.955, 0.98, 1.0, 1.02, 1.045]
        case .space, .backspace, .shift: [0.97, 1.0, 1.03]
        case .bell: [0.993, 1.0, 1.007]
        case .carriageReturn, .paperFeed, .paperRelease: [0.98, 1.0, 1.02]
        }
    }
}

/// The voice of a machine. Every machine is included; the portable is the default.
nonisolated enum MachineSound: String, CaseIterable, Identifiable, Codable, Sendable {
    case portable, upright, electric, tin

    var id: String { rawValue }

    var name: String {
        switch self {
        case .portable: "Portable"
        case .upright: "Office Upright"
        case .electric: "Electric"
        case .tin: "Tin Traveller"
        }
    }

    var blurb: String {
        switch self {
        case .portable: "A 1950s portable. Crisp, bright, a little bell."
        case .upright: "A heavy desk machine. Deep thunk, long carriage."
        case .electric: "An office electric. Quick, tight, motor-driven return."
        case .tin: "A tin travel machine. Rattly and cheerful."
        }
    }

    var profile: SynthProfile {
        switch self {
        case .portable:
            SynthProfile(body: 230, impact: 2300, bright: 1.0, decay: 1.0, rattle: 0.6, bell: 2350, bellDecay: 1.0, travel: 1.0, escapement: 1.0, hum: 0)
        case .upright:
            SynthProfile(body: 160, impact: 1700, bright: 0.8, decay: 1.35, rattle: 0.35, bell: 1980, bellDecay: 1.3, travel: 1.25, escapement: 1.2, hum: 0)
        case .electric:
            SynthProfile(body: 140, impact: 2900, bright: 1.25, decay: 0.7, rattle: 0.1, bell: 2600, bellDecay: 0.8, travel: 0.8, escapement: 0.2, hum: 0.06)
        case .tin:
            SynthProfile(body: 320, impact: 3300, bright: 1.35, decay: 0.8, rattle: 1.0, bell: 2900, bellDecay: 0.7, travel: 0.85, escapement: 1.0, hum: 0)
        }
    }
}

/// Knobs for one machine's character.
nonisolated struct SynthProfile: Sendable {
    /// The frame's low resonance, in Hz.
    var body: Double
    /// The slug and platen ring, in Hz.
    var impact: Double
    /// Multiplier on noise filter frequencies.
    var bright: Double
    /// Multiplier on decay times.
    var decay: Double
    /// How much loose-part rattle follows each strike.
    var rattle: Double
    /// The bell's fundamental, in Hz.
    var bell: Double
    var bellDecay: Double
    /// Multiplier on the carriage return's slide time.
    var travel: Double
    /// Loudness of the escapement click that follows each strike.
    var escapement: Double
    /// Motor hum under the return, for electrics.
    var hum: Double
}

/// Synthesizes typewriter sounds from scratch: filtered noise for the strikes, damped sine modes for the
/// metal, and an inharmonic partial set for the bell. Nothing is sampled, so there's nothing to license.
nonisolated struct TypewriterSynth {
    let sampleRate: Double
    let profile: SynthProfile
    private var rng: SplitMix64

    init(sampleRate: Double, profile: SynthProfile, seed: UInt64) {
        self.sampleRate = sampleRate
        self.profile = profile
        rng = SplitMix64(seed: seed)
    }

    mutating func render(_ kind: SoundKind) -> [Float] {
        switch kind {
        case .key: key(heavy: false)
        case .strike: key(heavy: true)
        case .space: space()
        case .backspace: backspace()
        case .shift: shift()
        case .bell: bell()
        case .carriageReturn: carriageReturn()
        case .paperFeed: paperFeed()
        case .paperRelease: paperRelease()
        }
    }

    // MARK: Sounds

    private mutating func key(heavy: Bool) -> [Float] {
        let p = profile
        var out = buffer(seconds: 0.17 * p.decay)
        let weight = heavy ? 1.25 : 1.0
        let t0 = 0.0015
        // The slug hitting the platen: a sharp broadband crack, then a duller body.
        noiseBurst(&out, at: t0, amp: 1.0 * weight, decay: 0.0011, center: 3100 * p.bright * jitter(0.15), q: 0.7)
        noiseBurst(&out, at: t0, amp: 0.55 * weight, decay: 0.0042 * p.decay, center: 1150 * p.bright * jitter(0.15), q: 1.1)
        // The metal ringing.
        let f = p.impact * jitter(0.07)
        dampedSine(&out, at: t0, freq: f, amp: 0.32, decay: 0.010 * p.decay)
        dampedSine(&out, at: t0, freq: f * 1.63 * jitter(0.03), amp: 0.17, decay: 0.006 * p.decay)
        dampedSine(&out, at: t0, freq: p.body * jitter(0.09), amp: 0.5 * weight, decay: 0.026 * p.decay)
        dampedSine(&out, at: t0, freq: p.body * 2.41 * jitter(0.05), amp: 0.16, decay: 0.017 * p.decay)
        // The escapement letting the carriage step one space.
        let esc = 0.026 + rng.unit() * 0.012
        noiseBurst(&out, at: esc, amp: 0.2 * p.escapement, decay: 0.0014, center: 4600 * p.bright * jitter(0.1), q: 1.6)
        dampedSine(&out, at: esc, freq: 3300 * jitter(0.1), amp: 0.05 * p.escapement, decay: 0.004)
        rattle(&out, from: 0.045, to: 0.11, amount: p.rattle)
        // The key lever coming back up.
        noiseBurst(&out, at: 0.085 + rng.unit() * 0.025, amp: 0.07, decay: 0.002, center: 2100 * p.bright, q: 1.2)
        if p.hum > 0 {
            dampedSine(&out, at: t0, freq: 140 * jitter(0.05), amp: 0.25, decay: 0.02)
        }
        normalize(&out, peak: heavy ? 0.85 : 0.78)
        return out
    }

    private mutating func space() -> [Float] {
        let p = profile
        var out = buffer(seconds: 0.15 * p.decay)
        dampedSine(&out, at: 0.001, freq: p.body * 0.72 * jitter(0.08), amp: 0.6, decay: 0.032 * p.decay)
        noiseBurst(&out, at: 0.001, amp: 0.5, decay: 0.006, center: 700 * p.bright * jitter(0.1), q: 0.8)
        noiseBurst(&out, at: 0.012, amp: 0.28 * p.escapement, decay: 0.0015, center: 4200 * p.bright, q: 1.5)
        rattle(&out, from: 0.03, to: 0.09, amount: p.rattle * 0.7)
        noiseBurst(&out, at: 0.08 + rng.unit() * 0.02, amp: 0.1, decay: 0.003, center: 1500 * p.bright, q: 1)
        normalize(&out, peak: 0.62)
        return out
    }

    private mutating func backspace() -> [Float] {
        let p = profile
        var out = buffer(seconds: 0.09)
        noiseBurst(&out, at: 0.001, amp: 0.5, decay: 0.0015, center: 3800 * p.bright, q: 1.4)
        dampedSine(&out, at: 0.001, freq: p.body * 1.3, amp: 0.25, decay: 0.012)
        noiseBurst(&out, at: 0.019, amp: 0.35, decay: 0.0014, center: 4400 * p.bright, q: 1.6)
        normalize(&out, peak: 0.5)
        return out
    }

    private mutating func shift() -> [Float] {
        let p = profile
        var out = buffer(seconds: 0.16)
        dampedSine(&out, at: 0.001, freq: p.body * 0.55 * jitter(0.06), amp: 0.7, decay: 0.05)
        noiseBurst(&out, at: 0.001, amp: 0.45, decay: 0.01, center: 520 * p.bright, q: 0.7)
        // The type basket landing on its stop.
        noiseBurst(&out, at: 0.068, amp: 0.4, decay: 0.002, center: 2400 * p.bright, q: 1)
        dampedSine(&out, at: 0.068, freq: p.impact * 0.6, amp: 0.15, decay: 0.008)
        normalize(&out, peak: 0.55)
        return out
    }

    private mutating func bell() -> [Float] {
        let p = profile
        var out = buffer(seconds: 1.7 * p.bellDecay)
        // The little hammer.
        noiseBurst(&out, at: 0.0005, amp: 0.25, decay: 0.0012, center: 5000, q: 1)
        let f0 = p.bell * jitter(0.01)
        let partials: [(ratio: Double, amp: Double, decay: Double)] = [
            (1.0, 1.0, 1.25), (1.0036, 0.35, 1.1), (2.02, 0.16, 0.5),
            (2.76, 0.42, 0.62), (4.07, 0.12, 0.3), (5.43, 0.15, 0.2),
        ]
        for partial in partials {
            dampedSine(&out, at: 0.0008, freq: f0 * partial.ratio, amp: partial.amp, decay: partial.decay * 0.32 * p.bellDecay, attack: 0.0012)
        }
        normalize(&out, peak: 0.5)
        return out
    }

    private mutating func carriageReturn() -> [Float] {
        let p = profile
        let slide = 0.32 * p.travel
        let start = 0.07
        var out = buffer(seconds: start + slide + 0.3)
        // The lever, then the platen ratcheting one line.
        dampedSine(&out, at: 0.001, freq: p.body * 0.8, amp: 0.45, decay: 0.03)
        noiseBurst(&out, at: 0.001, amp: 0.45, decay: 0.006, center: 900 * p.bright, q: 0.8)
        for t in [0.03, 0.054] {
            noiseBurst(&out, at: t, amp: 0.32, decay: 0.0015, center: 3000 * p.bright, q: 1.3)
            dampedSine(&out, at: t, freq: 2400 * jitter(0.05), amp: 0.08, decay: 0.006)
        }
        // The carriage sliding back: friction plus the rack's teeth.
        let n0 = index(start), n1 = index(start + slide)
        var bp = Biquad.bandpass(center: 1500 * p.bright, q: 0.6, sampleRate: sampleRate)
        for n in n0..<min(n1, out.count) {
            let x = Double(n - n0) / Double(max(1, n1 - n0))
            let env = pow(sin(.pi * x), 0.7)
            out[n] += Float(bp.process(rng.signed()) * env * 0.16)
            if p.hum > 0 {
                out[n] += Float(sin(2 * .pi * 118 * Double(n) / sampleRate) * env * p.hum)
            }
        }
        if p.escapement > 0.3 {
            var t = start
            while t < start + slide {
                let x = (t - start) / slide
                noiseBurst(&out, at: t, amp: 0.07 * (0.6 + x), decay: 0.0007, center: 4300 * p.bright, q: 2)
                t += 1 / (34 + 110 * x) * jitter(0.15)
            }
        }
        // The margin stop.
        let stop = start + slide
        noiseBurst(&out, at: stop, amp: 0.9, decay: 0.0022, center: 1400 * p.bright, q: 0.8)
        dampedSine(&out, at: stop, freq: p.body * 0.9, amp: 0.7, decay: 0.045 * p.decay)
        dampedSine(&out, at: stop, freq: p.impact * 0.8, amp: 0.28, decay: 0.012 * p.decay)
        rattle(&out, from: stop + 0.02, to: stop + 0.12, amount: p.rattle)
        normalize(&out, peak: 0.72)
        return out
    }

    private mutating func paperFeed() -> [Float] {
        let p = profile
        var out = buffer(seconds: 0.75)
        var bp = Biquad.bandpass(center: 2200, q: 0.5, sampleRate: sampleRate)
        for n in 0..<out.count {
            let x = Double(n) / Double(out.count)
            out[n] += Float(bp.process(rng.signed()) * sin(.pi * x) * 0.05)
        }
        var t = 0.02
        var i = 0
        while t < 0.62 {
            noiseBurst(&out, at: t, amp: 0.3, decay: 0.0014, center: 3200 * p.bright, q: 1.4)
            dampedSine(&out, at: t, freq: 2600 * jitter(0.06), amp: 0.05, decay: 0.005)
            i += 1
            t += (0.07 - min(0.035, Double(i) * 0.003)) * jitter(0.1)
        }
        normalize(&out, peak: 0.45)
        return out
    }

    /// The paper bail lifting off the sheet, then the sheet sliding up and out past the platen.
    private mutating func paperRelease() -> [Float] {
        let p = profile
        var out = buffer(seconds: 0.62)
        // The bail: a light spring click and a little metal.
        noiseBurst(&out, at: 0.002, amp: 0.55, decay: 0.0016, center: 3400 * p.bright, q: 1.3)
        dampedSine(&out, at: 0.002, freq: p.impact * 1.1 * jitter(0.05), amp: 0.12, decay: 0.01)
        // The release lever easing the platen's grip.
        dampedSine(&out, at: 0.045, freq: p.body * 1.1, amp: 0.3, decay: 0.03)
        noiseBurst(&out, at: 0.045, amp: 0.25, decay: 0.004, center: 900 * p.bright, q: 0.8)
        // Paper sliding: soft noise that rises in pitch and fades as the sheet clears the rollers.
        let n0 = index(0.08), n1 = min(out.count, index(0.58))
        // Two bands crossfading low to high stand in for the pitch rising as the sheet speeds up.
        var low = Biquad.bandpass(center: 1700 * p.bright, q: 0.5, sampleRate: sampleRate)
        var high = Biquad.bandpass(center: 4200 * p.bright, q: 0.5, sampleRate: sampleRate)
        for n in n0..<n1 {
            let x = Double(n - n0) / Double(max(1, n1 - n0))
            let env = pow(sin(.pi * min(1, x * 1.15)), 1.4) * (1 - x * 0.6)
            let noise = rng.signed()
            out[n] += Float((low.process(noise) * (1 - x) + high.process(noise) * x) * env * 0.12)
        }
        normalize(&out, peak: 0.42)
        return out
    }

    // MARK: Building blocks

    private func buffer(seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * sampleRate))
    }

    private func index(_ t: Double) -> Int { Int(t * sampleRate) }

    private mutating func jitter(_ amount: Double) -> Double {
        1 + (rng.unit() * 2 - 1) * amount
    }

    /// Adds an exponentially decaying sine.
    private func dampedSine(_ out: inout [Float], at t: Double, freq: Double, amp: Double, decay: Double, attack: Double = 0.0003) {
        let start = index(t)
        let length = min(out.count - start, Int(decay * 7 * sampleRate))
        guard length > 0 else { return }
        let w = 2 * .pi * freq / sampleRate
        let k = exp(-1 / (decay * sampleRate))
        let attackSamples = max(1, attack * sampleRate)
        var env = 1.0
        for i in 0..<length {
            let a = min(1, Double(i) / attackSamples)
            out[start + i] += Float(sin(w * Double(i)) * env * a * amp)
            env *= k
        }
    }

    /// Adds a burst of band-passed noise with an exponential tail.
    private mutating func noiseBurst(_ out: inout [Float], at t: Double, amp: Double, decay: Double, center: Double, q: Double) {
        let start = index(t)
        let length = min(out.count - start, Int(decay * 8 * sampleRate))
        guard length > 0 else { return }
        var filter = Biquad.bandpass(center: min(center, sampleRate * 0.45), q: q, sampleRate: sampleRate)
        let k = exp(-1 / (decay * sampleRate))
        var env = 1.0
        // Band-passing loses level; make it up so `amp` means roughly the same at any Q.
        let makeup = 1.6 + q
        for i in 0..<length {
            out[start + i] += Float(filter.process(rng.signed()) * env * amp * makeup)
            env *= k
        }
    }

    /// Loose parts chattering after a strike.
    private mutating func rattle(_ out: inout [Float], from t0: Double, to t1: Double, amount: Double) {
        guard amount > 0 else { return }
        let count = Int((2 + rng.unit() * 3) * amount)
        for _ in 0..<count {
            let t = t0 + rng.unit() * (t1 - t0)
            noiseBurst(&out, at: t, amp: 0.05 * amount, decay: 0.0009, center: 2600 + rng.unit() * 3000, q: 2.2)
        }
    }

    private func normalize(_ out: inout [Float], peak: Float) {
        let maxValue = out.reduce(0) { max($0, abs($1)) }
        guard maxValue > 0 else { return }
        let gain = peak / maxValue
        // A short fade keeps the tail from clicking.
        let fade = min(out.count, Int(0.004 * sampleRate))
        for i in out.indices {
            var sample = out[i] * gain
            let fromEnd = out.count - i
            if fromEnd < fade { sample *= Float(fromEnd) / Float(fade) }
            out[i] = sample
        }
    }

    /// Resamples by linear interpolation, which shifts pitch and length together like a tape played faster.
    static func resample(_ input: [Float], rate: Double) -> [Float] {
        guard rate != 1, input.count > 1 else { return input }
        let count = Int(Double(input.count) / rate)
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let x = Double(i) * rate
            let j = Int(x)
            guard j + 1 < input.count else { break }
            let f = Float(x - Double(j))
            out[i] = input[j] * (1 - f) + input[j + 1] * f
        }
        return out
    }
}

/// An RBJ-cookbook biquad.
nonisolated struct Biquad {
    var b0, b1, b2, a1, a2: Double
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    static func bandpass(center: Double, q: Double, sampleRate: Double) -> Biquad {
        let w0 = 2 * .pi * center / sampleRate
        let alpha = sin(w0) / (2 * q)
        let a0 = 1 + alpha
        return Biquad(b0: alpha / a0, b1: 0, b2: -alpha / a0, a1: -2 * cos(w0) / a0, a2: (1 - alpha) / a0)
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x
        y2 = y1; y1 = y
        return y
    }
}

/// A tiny, fast, seedable random source, so a machine sounds the same from launch to launch.
nonisolated struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A value in 0..<1.
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

    /// A value in -1..<1.
    mutating func signed() -> Double { unit() * 2 - 1 }
}
