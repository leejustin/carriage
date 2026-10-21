import Foundation

/// Every sound the machine makes. Each one is a real recording (see docs/sounds/SOURCES.md).
nonisolated enum SoundKind: String, CaseIterable, Sendable {
    case key, strike, space, backspace, shift, bell, carriageReturn, paperFeed, paperRelease

    /// Kinds without recordings of their own borrow a near relative: an x-out is a key struck again, backspace a
    /// lighter key, and shift (also the jam at the margin) the space bar's duller thud.
    var standIn: SoundKind? {
        switch self {
        case .strike, .backspace: .key
        case .shift: .space
        default: nil
        }
    }

    /// Playback-rate copies of each take, so the same key never sounds quite the same twice.
    var rates: [Double] {
        switch self {
        case .key, .strike, .backspace: [0.985, 1.0, 1.015]
        case .space, .shift: [0.99, 1.0, 1.01]
        default: [1.0]
        }
    }
}

/// The voice of a machine: each is a real typewriter recorded by a Freesound contributor and released CC0.
/// The portable is free; the others come with the unlock.
nonisolated enum MachineSound: String, CaseIterable, Identifiable, Codable, Sendable {
    case portable, upright, electric, tin

    var id: String { rawValue }

    var name: String {
        switch self {
        case .portable: "Italian Portable"
        case .upright: "Swiss Portable"
        case .electric: "Office Electric"
        case .tin: "American Portable"
        }
    }

    var blurb: String {
        switch self {
        case .portable: "A 1950s Italian portable. Crisp, quick and light."
        case .upright: "A 1960s Swiss portable. Solid, deep and steady."
        case .electric: "A 1970s office electric. A soft hum, a quick tap."
        case .tin: "A 1950s American portable. Bright, snappy and loud."
        }
    }

    var isIncluded: Bool { self == .portable }
}

/// Changes a take's pitch and length together, like tape played a touch faster or slower.
nonisolated enum Resample {
    static func by(_ rate: Double, _ input: [Float]) -> [Float] {
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
